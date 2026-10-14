import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/app_database.dart';
import 'managed_file_storage.dart';

/// Cached, bounded-resolution image thumbnails. Office/PDF/video use icons.
class ThumbnailCache {
  ThumbnailCache(this.storage);
  final ManagedFileStorage storage;
  static final _pending = <String, Future<File?>>{};
  String _pendingKey(String key) =>
      '${p.normalize(p.absolute(storage.root))}|$key';
  String _key(AttachmentRecord file) => sha256
      .convert(utf8.encode('${file.id}|${file.relativePath}|${file.fileSize}'))
      .toString();
  Future<File?> get(AttachmentRecord file) {
    if (file.deletedAt != null || !file.mimeType.startsWith('image/')) {
      return Future.value(null);
    }
    final key = _key(file);
    final pendingKey = _pendingKey(key);
    return _pending.putIfAbsent(
      pendingKey,
      () => _create(file, key).whenComplete(() {
        _pending.remove(pendingKey);
      }),
    );
  }

  Future<File?> _create(AttachmentRecord file, String key) async {
    try {
      final cache = File(
        storage.absolute(p.join('cache', 'thumbnails', '$key.png')),
      );
      if (await cache.exists()) return cache;
      final buffer = await ui.ImmutableBuffer.fromFilePath(
        storage.absolute(file.relativePath),
      );
      final codec = await ui.instantiateImageCodecFromBuffer(
        buffer,
        targetWidth: 240,
        allowUpscaling: false,
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final bytes = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (bytes == null) return null;
          await cache.parent.create(recursive: true);
          await cache.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
          return cache;
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return null; /* Broken/unsupported images retain a file icon. */
    }
  }

  Future<void> remove(AttachmentRecord file) async {
    final pending = _pending[_pendingKey(_key(file))];
    if (pending != null) await pending;
    await storage.deleteOwned(
      p.join('cache', 'thumbnails', '${_key(file)}.png'),
    );
  }
}
