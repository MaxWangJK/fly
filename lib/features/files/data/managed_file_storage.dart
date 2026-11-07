import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class ImportCancelled implements Exception {}

class ImportCancellation {
  bool _cancelled = false;
  final _listeners = <void Function()>{};
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  void Function() onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
    return () => _listeners.remove(listener);
  }

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

  /// Native drops from our own managed library are not new imports. Explicit
  /// file selection still uses the normal duplicate-confirmation workflow.
  bool isManagedSourcePath(String path) {
    final source = p.normalize(p.absolute(path));
    return [
      'files',
      'attachments',
    ].any((directory) => p.isWithin(absolute(directory), source));
  }

  String absolute(String relative) {
    final base = p.normalize(p.absolute(root));
    final portable = relative.replaceAll('\\', '/');
    final path = p.normalize(p.join(base, portable));
    if (p.posix.isAbsolute(portable) ||
        p.windows.isAbsolute(relative) ||
        !p.isWithin(base, path)) {
      throw ArgumentError('文件路径不在 FlyData 中');
    }
    return path;
  }

  Future<void> deleteOwned(String relative) async {
    final file = File(absolute(relative));
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }
    final resolvedRoot = await Directory(root).resolveSymbolicLinks();
    final resolved = await file.resolveSymbolicLinks();
    if (!p.isWithin(resolvedRoot, resolved)) throw StateError('拒绝删除数据目录外的文件');
    await file.delete();
  }

  Future<void> removeShareCopies({String? fileId, Duration? olderThan}) async {
    final cache = Directory(absolute('cache/share'));
    if (!await cache.exists()) return;
    final before = olderThan == null
        ? null
        : DateTime.now().subtract(olderThan);
    await for (final session in cache.list(followLinks: false)) {
      if (session is! Directory) continue;
      await for (final folder in session.list(followLinks: false)) {
        if (folder is! Directory ||
            (fileId != null && p.basename(folder.path) != fileId)) {
          continue;
        }
        await for (final copy in folder.list(followLinks: false)) {
          if (copy is! File) continue;
          if (before != null && !(await copy.lastModified()).isBefore(before)) {
            continue;
          }
          await deleteOwned(p.relative(copy.path, from: root));
        }
      }
    }
  }

  Future<ImportedFile> import(
    String source, {
    XFile? pickedFile,
    String? folderId,
    ImportCancellation? cancellation,
    void Function(int copied, int total)? progress,
  }) async {
    if (folderId != null && !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(folderId)) {
      throw ArgumentError('无效文件夹 ID');
    }
    final input = File(source);
    if (pickedFile == null &&
        await FileSystemEntity.type(source, followLinks: false) !=
            FileSystemEntityType.file) {
      throw ArgumentError('仅支持普通文件');
    }
    final id = const Uuid().v7();
    final name = p
        .basename(pickedFile?.name ?? source)
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
    final relative = p.posix.join('files', folderId ?? 'inbox', id, name);
    final target = File(absolute(relative));
    final partial = File('${target.path}.importing');
    await target.parent.create(recursive: true);
    final length = pickedFile == null
        ? await input.length()
        : await pickedFile.length();
    final output = await partial.open(mode: FileMode.writeOnly);
    var closed = false;
    var copied = 0;
    try {
      cancellation?.check();
      await for (final chunk in pickedFile?.openRead() ?? input.openRead()) {
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
