import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class ImportCancelled implements Exception {}

class ImportCancellation {
  bool _cancelled = false;
  void cancel() => _cancelled = true;
  void check() {
    if (_cancelled) throw ImportCancelled();
  }
}

class ImportedFile {
  const ImportedFile({
    required this.id,
    required this.relativePath,
    required this.name,
    required this.size,
    required this.sha256,
  });
  final String id, relativePath, name, sha256;
  final int size;
}

class ManagedFileStorage {
  ManagedFileStorage(this.root);
  final String root;
  String absolute(String relative) {
    final base = p.normalize(p.absolute(root));
    final path = p.normalize(p.join(base, relative));
    if (p.isAbsolute(relative) || !p.isWithin(base, path)) {
      throw ArgumentError('文件路径不在 FlyData 中');
    }
    return path;
  }

  Future<ImportedFile> import(
    String source, {
    String? folderId,
    ImportCancellation? cancellation,
    void Function(int copied, int total)? progress,
  }) async {
    if (folderId != null && !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(folderId)) {
      throw ArgumentError('无效文件夹 ID');
    }
    final input = File(source);
    if (await FileSystemEntity.type(source, followLinks: false) !=
        FileSystemEntityType.file) {
      throw ArgumentError('仅支持普通文件');
    }
    final id = const Uuid().v7();
    final name = p
        .basename(source)
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
    final relative = p.join('files', folderId ?? 'inbox', id, name);
    final target = File(absolute(relative));
    final partial = File('${target.path}.importing');
    await target.parent.create(recursive: true);
    final length = await input.length();
    final output = await partial.open(mode: FileMode.writeOnly);
    var closed = false;
    var copied = 0;
    try {
      cancellation?.check();
      await for (final chunk in input.openRead()) {
        cancellation?.check();
        await output.writeFrom(chunk);
        copied += chunk.length;
        progress?.call(copied, length);
      }
      await output.flush();
      await output.close();
      closed = true;
      cancellation?.check();
      if (copied != length) throw StateError('复制期间源文件大小发生变化，请重试');
      final hash = await sha256
          .bind(
            partial.openRead().map((chunk) {
              cancellation?.check();
              return chunk;
            }),
          )
          .first;
      cancellation?.check();
      await partial.rename(target.path);
      progress?.call(length, length);
      return ImportedFile(
        id: id,
        relativePath: relative,
        name: name,
        size: length,
        sha256: hash.toString(),
      );
    } catch (_) {
      if (!closed) await output.close();
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  /// Only clean up the exact file created by this import, never a user-supplied directory.
  Future<void> discard(ImportedFile file) async {
    final path = absolute(file.relativePath);
    if (p.basename(p.dirname(path)) != file.id) throw StateError('无法确认临时文件归属');
    if (await File(path).exists()) await File(path).delete();
  }
}
