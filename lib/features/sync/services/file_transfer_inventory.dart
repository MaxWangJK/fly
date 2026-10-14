import 'dart:convert';
import 'dart:io';

import '../../../core/database/app_database.dart';
import '../../files/data/managed_file_storage.dart';
import '../data/sync_outbox_repository.dart';

String remoteFileStateKey(String scope, String hash) =>
    'fileRemote:${jsonEncode([scope, hash])}';

class FileTransferInventory {
  const FileTransferInventory({
    this.uploads = 0,
    this.downloads = 0,
    this.waitingForSource = 0,
  });
  final int uploads, downloads, waitingForSource;
  static Future<FileTransferInventory> load(AppDatabase db, String root) async {
    final outbox = SyncOutboxRepository(db);
    final scope = await outbox.state('workspace') ?? 'local';
    final states = await db
        .customSelect(
          "SELECT key,value FROM sync_state WHERE key LIKE 'fileRemote:%' OR key LIKE 'localBlob:%'",
        )
        .get();
    final confirmed = states
        .where((s) => s.read<String>('value') == 'true')
        .map((s) => s.read<String>('key'))
        .toSet();
    final localHashes = {
      for (final s in states)
        if (s.read<String>('key').startsWith('localBlob:'))
          s.read<String>('key').substring('localBlob:'.length): s.read<String>(
            'value',
          ),
    };
    final records = await (db.select(
      db.attachments,
    )..where((f) => f.deletedAt.isNull())).get();
    var uploads = 0, downloads = 0, waiting = 0;
    final storage = ManagedFileStorage(root);
    for (final file in records) {
      final local = File(storage.absolute(file.relativePath));
      if (await local.exists()) {
        final known = localHashes[file.id];
        if (file.sha256 != null && known != null && known != file.sha256) {
          // A newer remote revision can arrive before its physical file.
          downloads++;
        } else if (file.sha256 == null ||
            await local.length() != file.fileSize ||
            !confirmed.contains(remoteFileStateKey(scope, file.sha256!))) {
          uploads++;
        }
      } else {
        downloads++;
        if (file.sha256 == null) waiting++;
      }
    }
    return FileTransferInventory(
      uploads: uploads,
      downloads: downloads,
      waitingForSource: waiting,
    );
  }
}

Future<void> forgetRemoteFileState(AppDatabase db, String hash) async {
  final rows = await db
      .customSelect("SELECT key FROM sync_state WHERE key LIKE 'fileRemote:%'")
      .get();
  for (final row in rows) {
    final key = row.read<String>('key');
    try {
      final data = jsonDecode(key.substring('fileRemote:'.length));
      if (data is List && data.length == 2 && data[1] == hash) {
        await db.customStatement('DELETE FROM sync_state WHERE key=?', [key]);
      }
    } on FormatException {
      /* Ignore invalid older state values. */
    }
  }
}
