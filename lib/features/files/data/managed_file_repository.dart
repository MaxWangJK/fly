import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import 'managed_file_storage.dart';

enum DuplicateFileAction { skip, keepCopy, replace }

class DuplicateManagedFile implements Exception {
  const DuplicateManagedFile(this.existing);
  final AttachmentRecord existing;
}

class ManagedFileRepository {
  ManagedFileRepository(this.db, {this.storage});
  final AppDatabase db;
  final ManagedFileStorage? storage;
  Stream<List<AttachmentRecord>> watchAll() => (db.select(
    db.attachments,
  )..orderBy([(r) => OrderingTerm.desc(r.updatedAt)])).watch();
  Future<void> _folder(String? id) async {
    if (id != null &&
        await (db.select(db.fileFolders)
                  ..where((r) => r.id.equals(id) & r.deletedAt.isNull()))
                .getSingleOrNull() ==
            null) {
      throw StateError('目标文件夹不存在');
    }
  }

  Future<AttachmentRecord?> find(String id) => (db.select(
    db.attachments,
  )..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<List<AttachmentRecord>> imagesInLocation(AttachmentRecord anchor) =>
      (db.select(db.attachments)..where(
            (r) =>
                r.deletedAt.isNull() &
                r.mimeType.like('image/%') &
                r.ownerType.equals(anchor.ownerType) &
                (anchor.ownerType == 'library'
                    ? (anchor.folderId == null
                          ? r.folderId.isNull()
                          : r.folderId.equals(anchor.folderId!))
                    : r.ownerId.equals(anchor.ownerId)),
          ))
          .get();
  Future<void> validateMoveDestination(String? folderId) => _folder(folderId);

  Future<String?> commit(
    ImportedFile file, {
    String? folderId,
    DuplicateFileAction? duplicateAction,
    String? noteId,
  }) => db.transaction(() async {
    await _folder(folderId);
    if (noteId != null &&
        await (db.select(db.workspaceNotes)
                  ..where((r) => r.id.equals(noteId) & r.deletedAt.isNull()))
                .getSingleOrNull() ==
            null) {
      throw StateError('笔记不存在或已删除');
    }
    final existing =
        await (db.select(db.attachments)..where(
              (r) =>
                  r.ownerType.equals(noteId == null ? 'library' : 'note') &
                  (noteId == null
                      ? const Constant(true)
                      : r.ownerId.equals(noteId)) &
                  r.deletedAt.isNull() &
                  r.sha256.equals(file.sha256) &
                  (folderId == null
                      ? r.folderId.isNull()
                      : r.folderId.equals(folderId)),
            ))
            .get();
    if (existing.isNotEmpty) {
      if (duplicateAction == null) throw DuplicateManagedFile(existing.first);
      if (duplicateAction == DuplicateFileAction.skip) return null;
      if (duplicateAction == DuplicateFileAction.replace) {
        await remove(existing.first.id);
      }
    }
    final now = DateTime.now();
    await db
        .into(db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            id: file.id,
            ownerType: noteId == null ? 'library' : 'note',
            ownerId: noteId ?? file.id,
            fileName: p.basename(file.relativePath),
            originalName: file.name,
            displayName: Value(file.name),
            folderId: Value(folderId),
            relativePath: file.relativePath,
            sha256: Value(file.sha256),
            mimeType: Value(mime(file.name)),
            fileSize: file.size,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return file.id;
  });
  static String mime(String name) => switch (p.extension(name).toLowerCase()) {
    '.png' => 'image/png',
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.gif' => 'image/gif',
    '.webp' => 'image/webp',
    '.heic' || '.heif' => 'image/heic',
    '.avif' => 'image/avif',
    '.bmp' => 'image/bmp',
    '.mp4' => 'video/mp4',
    '.mov' => 'video/quicktime',
    '.m4v' => 'video/x-m4v',
    '.webm' => 'video/webm',
    '.mkv' => 'video/x-matroska',
    '.avi' => 'video/x-msvideo',
    '.3gp' => 'video/3gpp',
    '.pdf' => 'application/pdf',
    '.txt' => 'text/plain',
    '.docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    '.pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    _ => 'application/octet-stream',
  };
  Future<void> rename(String id, String name) async {
    final files = storage;
    if (files == null) throw StateError('文件存储尚未初始化');
    String? oldPath, newPath;
    var moved = false;
    try {
      await db.transaction(() async {
        final row = await find(id);
        if (row == null || row.deletedAt != null) throw StateError('文件不存在');
        var checked = ManagedFileStorage.checkedFileName(name);
        if (p.extension(checked).isEmpty) {
          checked = ManagedFileStorage.checkedFileName(
            '$checked${p.extension(row.fileName)}',
          );
        }
        oldPath = row.relativePath;
        newPath = p.posix.join(
          p.posix.dirname(row.relativePath.replaceAll('\\', '/')),
          checked,
        );
        moved = await files.renameOwned(oldPath!, newPath!);
        await (db.update(db.attachments)..where((r) => r.id.equals(id))).write(
          AttachmentsCompanion(
            fileName: Value(checked),
            originalName: Value(checked),
            displayName: Value(checked),
            relativePath: Value(newPath!),
            mimeType: Value(
              p.extension(checked).toLowerCase() ==
                      p.extension(row.fileName).toLowerCase()
                  ? row.mimeType
                  : mime(checked),
            ),
            updatedAt: Value(DateTime.now()),
          ),
        );
      });
    } catch (_) {
      if (moved) await files.renameOwned(newPath!, oldPath!);
      rethrow;
    }
  }

  Future<void> move(String id, String? folderId) => db.transaction(() async {
    await _folder(folderId);
    final file = await find(id);
    if (file == null || file.deletedAt != null) throw StateError('文件不存在');
    if (file.ownerType != 'library') {
      throw StateError('业务附件不能剪切离开所属记录，请复制到我的文件');
    }
    await (db.update(db.attachments)..where((r) => r.id.equals(id))).write(
      AttachmentsCompanion(
        folderId: Value(folderId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  });
  Future<void> opened(String id) =>
      (db.update(
        db.attachments,
      )..where((r) => r.id.equals(id) & r.deletedAt.isNull())).write(
        AttachmentsCompanion(
          lastOpenedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
  Future<void> remove(String id, {bool allowBusinessAttachment = false}) async {
    final row = await find(id);
    if (row == null) throw StateError('文件不存在');
    if (row.ownerType != 'library' && !allowBusinessAttachment) {
      throw StateError('业务附件请从所属客户或订单中删除');
    }
    await (db.update(
      db.attachments,
    )..where((r) => r.id.equals(id) & r.deletedAt.isNull())).write(
      AttachmentsCompanion(
        deletedAt: Value(DateTime.now()),
        deletionBatch: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> restore(String id) => db.transaction(() async {
    final file = await find(id);
    if (file == null ||
        file.ownerType != 'library' ||
        file.deletionBatch == 'permanent') {
      throw StateError('文件无法恢复');
    }
    final folder = file.folderId == null
        ? null
        : await (db.select(db.fileFolders)..where(
                (r) => r.id.equals(file.folderId!) & r.deletedAt.isNull(),
              ))
              .getSingleOrNull();
    await (db.update(db.attachments)..where((r) => r.id.equals(id))).write(
      AttachmentsCompanion(
        folderId: Value(folder?.id),
        deletedAt: const Value(null),
        deletionBatch: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  });
  Stream<List<FileTagRecord>> watchTags() => (db.select(
    db.fileTags,
  )..orderBy([(r) => OrderingTerm.asc(r.name)])).watch();
  Stream<List<FileTagLink>> watchLinks() => db.select(db.fileTagLinks).watch();
  Future<String> createTag(String name) => db.transaction(() async {
    final title = name.trim();
    if (title.isEmpty || title.length > 100) {
      throw ArgumentError('标签长度需要 1–100 字');
    }
    final normalized = title.toLowerCase();
    final existing = await (db.select(
      db.fileTags,
    )..where((r) => r.normalizedName.equals(normalized))).getSingleOrNull();
    if (existing != null) return existing.id;
    final id = const Uuid().v7();
    await db
        .into(db.fileTags)
        .insert(
          FileTagsCompanion.insert(
            id: id,
            name: title,
            normalizedName: normalized,
          ),
        );
    return id;
  });
  Future<void> setTag(String fileId, String tagId, bool selected) async {
    if (selected) {
      await db
          .into(db.fileTagLinks)
          .insert(
            FileTagLinksCompanion.insert(fileId: fileId, tagId: tagId),
            mode: InsertMode.insertOrIgnore,
          );
    } else {
      await (db.delete(
        db.fileTagLinks,
      )..where((r) => r.fileId.equals(fileId) & r.tagId.equals(tagId))).go();
    }
  }
}
