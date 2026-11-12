import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// File I/O is asynchronous, but SHA-256 chunk processing is CPU work. Keep it
/// off the UI isolate, including the first scan and periodic integrity audits.
Future<String> sha256FileInBackground(String path) => Isolate.run(
  () async => (await sha256.bind(File(path).openRead()).first).toString(),
);

typedef _FileStamp = (int size, int modified, int changed);
_FileStamp _stamp(FileStat stat) => (
  stat.size,
  stat.modified.microsecondsSinceEpoch,
  stat.changed.microsecondsSinceEpoch,
);

class _VerifiedDigest {
  const _VerifiedDigest(this.stamp, this.hash, this.verifiedAt);
  final _FileStamp stamp;
  final String hash;
  final DateTime verifiedAt;
}

/// Session-local cache of verified bytes, never a substitute for validating new
/// downloads. Reads/playback change access time, which must not invalidate it.
class FileDigestCache {
  FileDigestCache({
    Future<String> Function(String)? digestFile,
    DateTime Function()? now,
    this.auditInterval = const Duration(minutes: 5),
    this.maxEntries = 512,
  }) : assert(maxEntries > 0),
       _digestFile = digestFile ?? sha256FileInBackground,
       _now = now ?? DateTime.now;

  final Future<String> Function(String) _digestFile;
  final DateTime Function() _now;
  final Duration auditInterval;
  final int maxEntries;
  final _entries = <String, _VerifiedDigest>{};
  final _running = <String, Future<String>>{};

  Future<String> digest(File file, {bool refresh = false}) async {
    final path = file.absolute.path;
    while (true) {
      final before = await file.stat();
      if (before.type != FileSystemEntityType.file) {
        _entries.remove(path);
        throw FileSystemException('文件不存在或无法读取', path);
      }
      final cached = _entries[path];
      final age = cached == null ? null : _now().difference(cached.verifiedAt);
      if (!refresh &&
          cached != null &&
          cached.stamp == _stamp(before) &&
          age! >= Duration.zero &&
          age < auditInterval) {
        _entries.remove(path);
        _entries[path] = cached;
        return cached.hash;
      }
      final running = _running[path];
      if (running != null) {
        await running;
        continue; // Recheck the current file, which may have changed meanwhile.
      }
      final work = _verify(file, before);
      _running[path] = work;
      try {
        return await work;
      } finally {
        _running.remove(path);
      }
    }
  }

  Future<String> _verify(File file, FileStat before) async {
    final path = file.absolute.path;
    _entries.remove(path);
    for (var attempt = 0; attempt < 2; attempt++) {
      final hash = await _digestFile(path);
      final after = await file.stat();
      if (after.type == FileSystemEntityType.file &&
          _stamp(before) == _stamp(after)) {
        if (_entries.length >= maxEntries) {
          _entries.remove(_entries.keys.first);
        }
        _entries[path] = _VerifiedDigest(_stamp(after), hash, _now());
        return hash;
      }
      before = after;
    }
    throw FileSystemException('校验时文件发生变化，请稍后重试', path);
  }
}
