import 'dart:convert';

import '../../../core/database/app_database.dart';

class SyncConflictService {
  SyncConflictService(this.db);
  final AppDatabase db;
  Future<void> archiveLegacyCandidates() async {
    await db.customStatement(
      'UPDATE sync_conflicts SET resolved=1 WHERE resolved=0',
    );
    await db.customStatement(
      "UPDATE sync_metadata SET sync_status=CASE WHEN EXISTS "
      "(SELECT 1 FROM sync_outbox o WHERE o.entity_type=sync_metadata.entity_type "
      "AND o.record_key=sync_metadata.record_key) THEN 'dirty' ELSE 'synced' END "
      "WHERE sync_status='conflict'",
    );
  }

  Future<void> store(List<dynamic> records) => db.transaction(() async {
    for (final raw in records) {
      final data = (raw as Map).cast<String, dynamic>();
      await db.customStatement(
        'INSERT INTO sync_conflicts(id,data,resolved) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data,resolved=excluded.resolved',
        [data['id'], jsonEncode(data), data['resolved'] == true ? 1 : 0],
      );
      if (data['resolved'] == true) continue;
      await db.customStatement(
        "UPDATE sync_metadata SET sync_status='conflict' WHERE entity_type=? AND sync_id=?",
        [data['entityType'], data['recordId']],
      );
    }
  });
  Future<void> resolve(String id, String entity, String recordId) =>
      db.transaction(() async {
        await db.customStatement(
          'UPDATE sync_conflicts SET resolved=1 WHERE id=?',
          [id],
        );
        await db.customStatement(
          r"""UPDATE sync_metadata SET sync_status=CASE
      WHEN EXISTS(SELECT 1 FROM sync_conflicts c WHERE c.resolved=0 AND json_extract(c.data,'$.entityType')=? AND json_extract(c.data,'$.recordId')=?) THEN 'conflict'
      WHEN EXISTS(SELECT 1 FROM sync_outbox o WHERE o.entity_type=sync_metadata.entity_type AND o.record_key=sync_metadata.record_key) THEN 'dirty'
      ELSE 'synced' END WHERE entity_type=? AND sync_id=?""",
          [entity, recordId, entity, recordId],
        );
      });
}
