import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import 'managed_file_repository.dart';
import 'managed_file_storage.dart';
import 'permanent_file_deletion.dart';
import 'thumbnail_cache.dart';

class PreparedShareFile {
  const PreparedShareFile(this.path, this.mimeType, this.name);
  final String path, mimeType, name;
}

class PreparedFileShare {
  PreparedFileShare(this.storage, this.files, this.relativePaths);
  final ManagedFileStorage storage;
  final List<PreparedShareFile> files;
  final List<String> relativePaths;
  Future<void> cleanup() async {
    for (final path in relativePaths) {
      await storage.deleteOwned(path);
    }
  }
}

class FileBatchResult {
  const FileBatchResult(
    this.completed,
    this.errors, {
    this.unchanged = const {},
  });
  final Set<String> completed;
  final Map<String, String> errors;
  final Set<String> unchanged;
}

class FileBatchActions {
  FileBatchActions(this.db, this.storage);
  final AppDatabase db;
  final ManagedFileStorage storage;

  Future<FileBatchResult> move(
    Set<String> ids,
    String? folderId, {
    void Function(int, int)? progress,
  }) async {
    if (ids.isEmpty) throw StateError('请先选择文件');
    final selected = ids.toList(growable: false);
    final repository = ManagedFileRepository(db);
    // Reject an unavailable destination before changing any selected file.
    await repository.validateMoveDestination(folderId);
    final completed = <String>{}, unchanged = <String>{};
    final errors = <String, String>{};
    for (var index = 0; index < selected.length; index++) {
      final id = selected[index];
      try {
        final changed = await db.transaction(() async {
          await repository.validateMoveDestination(folderId);
          final file = await repository.find(id);
          if (file != null &&
              file.deletedAt == null &&
              file.ownerType == 'library' &&
              file.folderId == folderId) {
            return false;
          }
          await repository.move(id, folderId);
          return true;
        });
        (changed ? completed : unchanged).add(id);
      } catch (error) {
        errors[id] = error is StateError ? error.message : '$error';
      }
      progress?.call(index + 1, selected.length);
    }
    return FileBatchResult(completed, errors, unchanged: unchanged);
  }

  Future<PreparedFileShare> prepareShare(
    Set<String> ids, {
    void Function(int, int)? progress,
  }) async {
    if (ids.isEmpty) throw StateError('请先选择文件');
    final records = await (db.select(
      db.attachments,
    )..where((f) => f.id.isIn(ids) & f.deletedAt.isNull())).get();
    if (records.length != ids.length) throw StateError('部分文件已删除或发生变化，请重新选择');
    var missing = 0;
    for (final file in records) {
      if (!await File(storage.absolute(file.relativePath)).exists()) missing++;
    }
    if (missing > 0) throw StateError('$missing 个文件尚未下载，请先同步后再分享');
    await storage.removeShareCopies(olderThan: const Duration(days: 1));
    final session = const Uuid().v4();
    final names = <String>{};
    final relativePaths = <String>[];
    final files = <PreparedShareFile>[];
    final result = PreparedFileShare(storage, files, relativePaths);
    try {
      for (final file in records) {
        final display = file.displayName.isEmpty
            ? file.originalName
            : file.displayName;
        final withExtension = p.extension(display).isEmpty
            ? '$display${p.extension(file.originalName)}'
            : display;
        final safe = p
            .basename(withExtension.replaceAll('\\', '/'))
            .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
        final original = safe.isEmpty || safe == '.' || safe == '..'
            ? 'file'
            : safe;
        var name = original, index = 2;
        while (!names.add(name.toLowerCase())) {
          name =
              '${p.basenameWithoutExtension(original)} (${index++})${p.extension(original)}';
        }
        final relative = 'cache/share/$session/${file.id}/$name';
        final target = File(storage.absolute(relative));
        relativePaths.add(relative);
        await target.parent.create(recursive: true);
        await File(storage.absolute(file.relativePath)).copy(target.path);
        await target.setLastModified(DateTime.now());
        files.add(PreparedShareFile(target.path, file.mimeType, name));
        progress?.call(files.length, records.length);
      }
      return result;
    } catch (_) {
      await result.cleanup();
      rethrow;
    }
  }

  Future<FileBatchResult> delete(
    Set<String> ids, {
    bool permanent = false,
    void Function(int, int)? progress,
  }) async {
    final completed = <String>{}, errors = <String, String>{};
    final repo = ManagedFileRepository(db);
    for (final id in ids) {
      try {
        final file = await repo.find(id);
        if (file == null) throw StateError('文件不存在');
        if (permanent) {
          // Each purge already removes this file's content. Avoid rescanning
          // every prior tombstone once per item in a large selection.
          await PermanentFileDeletion(
            db,
            storage,
          ).purge(id, cleanupPrevious: false);
        } else {
          if (file.deletedAt != null) throw StateError('文件已被删除');
          await repo.remove(id, allowBusinessAttachment: true);
          completed.add(id);
          await ThumbnailCache(storage).remove(file);
        }
        completed.add(id);
      } catch (error) {
        if (!completed.contains(id)) errors[id] = '$error';
      }
      progress?.call(completed.length + errors.length, ids.length);
    }
    return FileBatchResult(completed, errors);
  }
}
