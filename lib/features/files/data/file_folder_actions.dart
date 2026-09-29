import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/data/workspace_folder_repository.dart';
import 'thumbnail_cache.dart';

/// Coordinates metadata deletion with disposable cache cleanup, never originals.
class FileFolderActions {
  FileFolderActions(this.db, this.folders, this.cache);
  final AppDatabase db;
  final WorkspaceFolderRepository folders;
  final ThumbnailCache cache;

  Future<List<AttachmentRecord>> directFiles(String id) =>
      (db.select(db.attachments)
            ..where((r) => r.folderId.equals(id) & r.deletedAt.isNull())
            ..orderBy([(r) => OrderingTerm.asc(r.displayName)]))
          .get();

  /// Cache failures do not roll back an already committed recoverable deletion.
  /// Return their count so the UI does not silently conceal a cleanup failure.
  Future<int> remove(String id) async {
    final ids = folders.descendants(id, await folders.all());
    final affected = await (db.select(
      db.attachments,
    )..where((r) => r.folderId.isIn(ids) & r.deletedAt.isNull())).get();
    await folders.remove(id);
    var failures = 0;
    for (final file in affected) {
      try {
        await cache.remove(file);
      } catch (_) {
        failures++;
      }
    }
    return failures;
  }
}
