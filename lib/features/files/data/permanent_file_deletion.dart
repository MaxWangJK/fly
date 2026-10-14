import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import 'managed_file_storage.dart';
import 'thumbnail_cache.dart';
import '../../sync/services/file_transfer_inventory.dart';

/// Retains a synced tombstone while removing the actual file and cached copies.
class PermanentFileDeletion {
  PermanentFileDeletion(this.db, this.storage);
  final AppDatabase db;
  final ManagedFileStorage storage;
  static const marker = 'permanent';

  Future<void> purge(String id, {bool cleanupPrevious = true}) async {
    final file = await (db.select(
      db.attachments,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (file == null || file.deletedAt == null) {
      throw StateError('只能永久删除最近删除中的文件');
    }
    await _removeContent(file);
    await (db.update(db.attachments)..where((r) => r.id.equals(id))).write(
      AttachmentsCompanion(
        deletionBatch: const Value(marker),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (cleanupPrevious) await cleanup();
  }

  Future<void> cleanup() async {
    final rows = await (db.select(
      db.attachments,
    )..where((r) => r.deletionBatch.equals(marker))).get();
    for (final file in rows) {
      await _removeContent(file);
    }
  }

  Future<void> _removeContent(AttachmentRecord file) async {
    await ThumbnailCache(storage).remove(file);
    await storage.removeShareCopies(fileId: file.id);
    final shared =
        await (db.select(db.attachments)..where(
              (r) =>
                  r.id.equals(file.id).not() &
                  r.relativePath.equals(file.relativePath) &
                  (r.deletionBatch.isNull() |
                      r.deletionBatch.equals(marker).not()),
            ))
            .get();
    if (shared.isEmpty) {
      await storage.deleteOwned(file.relativePath);
      await storage.deleteOwned('${file.relativePath}.part');
    }
    final hash = file.sha256;
    if (hash != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      final other =
          await (db.select(db.attachments)..where(
                (r) =>
                    r.id.equals(file.id).not() &
                    r.sha256.equals(hash) &
                    (r.deletionBatch.isNull() |
                        r.deletionBatch.equals(marker).not()),
              ))
              .get();
      if (other.isEmpty) {
        await forgetRemoteFileState(db, hash);
        await storage.deleteOwned('sync_blobs/$hash');
        await storage.deleteOwned('sync_blobs/$hash.part');
      }
    }
  }
}
