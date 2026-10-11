import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/sync_protocol.dart';
import '../services/sync_conflict_service.dart';
import 'sync_schema.dart';

class SyncOutboxRepository {
  SyncOutboxRepository(this.db);
  final AppDatabase db;
  static const namespace = 'e8cd67db-7ae2-4ea8-bba7-baeeb52375a1';
  static String identity(String entity, String key) =>
      const Uuid().v5(namespace, '$entity:$key');

  Future<String?> state(String key) async =>
      (await db
              .customSelect(
                'SELECT value FROM sync_state WHERE key=?',
                variables: sqlVariables([key]),
              )
              .getSingleOrNull())
          ?.read<String>('value');
  Future<void> saveState(String key, String value) => db.customStatement(
    'INSERT INTO sync_state(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, value],
  );
  Future<int> pendingCount() async =>
      (await db
              .customSelect('SELECT count(*) AS count FROM sync_outbox')
              .getSingle())
          .read<int>('count');
  Future<Map<String, int>> initialCounts() async {
    final rows = await db
        .customSelect(
          'SELECT entity_type,count(*) AS count FROM sync_metadata WHERE deleted_at IS NULL GROUP BY entity_type',
        )
        .get();
    return {
      for (final r in rows) r.read<String>('entity_type'): r.read<int>('count'),
    };
  }

  Future<void> bind(String workspace) => db.transaction(() async {
    final previous = await state('workspace');
    if (previous != null && previous != workspace) {
      throw StateError('此本地数据库已绑定其它同步工作区。请为新账号选择独立的数据目录。');
    }
    await saveState('workspace', workspace);
    // Migrated 1.0 rows enter the outbox exactly once. Existing dirty mutations remain intact.
    final records = await db
        .customSelect(
          'SELECT * FROM sync_metadata WHERE sync_version=0 AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.entity_type=sync_metadata.entity_type AND o.record_key=sync_metadata.record_key)',
        )
        .get();
    for (final row in records) {
      final data = jsonObject(row.read<String>('payload'));
      await db.customStatement(
        'INSERT INTO sync_outbox(mutation_id,entity_type,record_key,base_version,changed_fields,payload,operation,created_at) VALUES(?,?,?,?,?,?,?,?)',
        [
          const Uuid().v4(),
          row.read<String>('entity_type'),
          row.read<String>('record_key'),
          0,
          jsonEncode(data.keys.toList()),
          jsonEncode(data),
          row.data['deleted_at'] == null ? 'upsert' : 'delete',
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ],
      );
    }
  });

  Future<List<Map<String, dynamic>>> prepare({
    int limit = 100,
  }) => db.transaction(() async {
    // At most one mutation per record in flight. Later edits rebase only before dispatch.
    final rows = await db.customSelect(
      '''SELECT o.*,m.sync_version FROM sync_outbox o
      JOIN sync_metadata m ON m.entity_type=o.entity_type AND m.record_key=o.record_key
      WHERE o.ordinal=(SELECT min(n.ordinal) FROM sync_outbox n WHERE n.entity_type=o.entity_type AND n.record_key=o.record_key)
      ORDER BY o.ordinal LIMIT ?''',
      variables: sqlVariables([limit]),
    ).get();
    final result = <Map<String, dynamic>>[];
    var batchBytes = 0;
    for (final row in rows) {
      if (row.data['dispatched'] != null) {
        final frozen = row.read<String>('dispatched');
        final bytes = utf8.encode(frozen).length;
        if (result.isNotEmpty && batchBytes + bytes > 2 * 1024 * 1024) break;
        batchBytes += bytes;
        result.add(jsonObject(frozen));
        continue;
      }
      final entity = row.read<String>('entity_type');
      final key = row.read<String>('record_key');
      final id = identity(entity, key);
      var operation = row.read<String>('operation');
      final version = row.read<int>('sync_version');
      var payload = jsonObject(row.read<String>('payload'));
      final fields = (jsonDecode(row.read<String>('changed_fields')) as List)
          .cast<String>();
      final following = await db
          .customSelect(
            'SELECT * FROM sync_outbox WHERE entity_type=? AND record_key=? AND ordinal>? AND dispatched IS NULL ORDER BY ordinal',
            variables: sqlVariables([entity, key, row.read<int>('ordinal')]),
          )
          .get();
      for (final edit in following) {
        payload = jsonObject(edit.read<String>('payload'));
        operation = edit.read<String>('operation');
        fields.addAll(
          (jsonDecode(edit.read<String>('changed_fields')) as List)
              .cast<String>(),
        );
        await db.customStatement('DELETE FROM sync_outbox WHERE ordinal=?', [
          edit.read<int>('ordinal'),
        ]);
      }
      final mutation = <String, dynamic>{
        'mutationId': row.read<String>('mutation_id'),
        'entityType': entity,
        'recordId': id,
        'baseVersion': version,
        'changedFields': operation == 'delete'
            ? <String>[]
            : (version == 0 ? payload.keys.toList() : fields.toSet().toList()),
        'payload': payload,
        'operation': operation,
      };
      await db.customStatement(
        'UPDATE sync_outbox SET payload=?,operation=?,changed_fields=? WHERE ordinal=?',
        [
          jsonEncode(payload),
          operation,
          jsonEncode(fields.toSet().toList()),
          row.read<int>('ordinal'),
        ],
      );
      final serialized = jsonEncode(mutation);
      final bytes = utf8.encode(serialized).length;
      if (result.isNotEmpty && batchBytes + bytes > 2 * 1024 * 1024) break;
      batchBytes += bytes;
      await db.customStatement(
        'UPDATE sync_metadata SET sync_id=? WHERE entity_type=? AND record_key=?',
        [id, entity, key],
      );
      await db.customStatement(
        'UPDATE sync_outbox SET dispatched=? WHERE ordinal=?',
        [serialized, row.read<int>('ordinal')],
      );
      result.add(mutation);
    }
    return result;
  });

  Future<void> acknowledge(List<dynamic> results) => db.transaction(() async {
    for (final raw in results) {
      final ack = (raw as Map).cast<String, dynamic>();
      final queued = await db
          .customSelect(
            'SELECT * FROM sync_outbox WHERE mutation_id=?',
            variables: sqlVariables([ack['mutationId']]),
          )
          .getSingleOrNull();
      if (queued == null) continue;
      final record = (ack['record'] as Map).cast<String, dynamic>();
      await db.customStatement(
        'UPDATE sync_metadata SET sync_version=?,sync_status=? WHERE entity_type=? AND record_key=?',
        [
          record['version'],
          ack['status'] == 'conflict' ? 'conflict' : 'synced',
          queued.read<String>('entity_type'),
          queued.read<String>('record_key'),
        ],
      );
      await db.customStatement('DELETE FROM sync_outbox WHERE mutation_id=?', [
        ack['mutationId'],
      ]);
      await stage(record);
    }
    await drainIncoming();
  });

  Future<void> stage(Map<String, dynamic> record) async {
    if (!syncTables.contains(record['entityType'])) {
      throw StateError('服务器返回未知实体');
    }
    await db.customStatement(
      'INSERT INTO sync_incoming(entity_type,record_id,data) VALUES(?,?,?) ON CONFLICT(entity_type,record_id) DO UPDATE SET data=excluded.data',
      [record['entityType'], record['recordId'], jsonEncode(record)],
    );
  }

  Future<void> applyPage(Map<String, dynamic> page, String cursorKey) =>
      db.transaction(() async {
        for (final raw in page['changes'] as List) {
          await stage((raw as Map).cast<String, dynamic>());
        }
        await drainIncoming();
        // Deferred relations are durable before advancing the cursor and replay on every page.
        await saveState(cursorKey, '${page['nextCursor']}');
      });

  Future<void> drainIncoming() async {
    await db.customStatement('UPDATE sync_control SET applying=1 WHERE id=1');
    try {
      var progress = true;
      while (progress) {
        progress = false;
        final rows = await db.customSelect('SELECT * FROM sync_incoming').get();
        for (final row in rows) {
          final record = jsonObject(row.read<String>('data'));
          try {
            // Savepoints make deferred FK/unique failures harmless to this page transaction.
            await db.transaction(() => _applyRecord(record));
          } on Object catch (e) {
            if (!e.toString().contains('FOREIGN KEY constraint') &&
                !e.toString().contains('UNIQUE constraint')) {
              rethrow;
            }
            continue;
          }
          await db.customStatement(
            'DELETE FROM sync_incoming WHERE entity_type=? AND record_id=?',
            [row.read<String>('entity_type'), row.read<String>('record_id')],
          );
          progress = true;
        }
      }
    } finally {
      await db.customStatement('UPDATE sync_control SET applying=0 WHERE id=1');
    }
  }

  Future<void> _applyRecord(Map<String, dynamic> record) async {
    final entity = record['entityType'] as String;
    final id = record['recordId'] as String;
    final data = (record['data'] as Map).cast<String, dynamic>();
    if (data.containsKey('deleted_at')) {
      data['deleted_at'] = record['deletedAt'] == null
          ? null
          : DateTime.parse(record['deletedAt'] as String)
                    .millisecondsSinceEpoch ~/
                1000;
    }
    final keys = await syncPrimaryKeys(db, entity);
    if (keys.any((k) => !data.containsKey(k))) {
      if (record['deletedAt'] != null) {
        return; // Delete of a never-created record.
      }
      throw StateError('同步记录缺少主键');
    }
    final key = jsonEncode(keys.map((k) => data[k]).toList());
    final expectedId = identity(entity, key);
    if (id != expectedId) throw StateError('同步 ID 与业务主键不一致');
    if (entity == 'app_settings' && !syncSettingKeys.contains(data['key'])) {
      throw StateError('不能同步设备专属设置');
    }
    final metadata = await db
        .customSelect(
          'SELECT * FROM sync_metadata WHERE entity_type=? AND record_key=?',
          variables: sqlVariables([entity, key]),
        )
        .getSingleOrNull();
    if (metadata != null &&
        metadata.read<int>('sync_version') > (record['version'] as int)) {
      return;
    }
    final canonical = Map<String, dynamic>.from(data);
    final pending = await db
        .customSelect(
          'SELECT * FROM sync_outbox WHERE entity_type=? AND record_key=? ORDER BY ordinal',
          variables: sqlVariables([entity, key]),
        )
        .get();
    if (record['deletedAt'] == null) {
      for (final p in pending) {
        final candidate = jsonObject(p.read<String>('payload'));
        for (final field
            in jsonDecode(p.read<String>('changed_fields')) as List) {
          data[field as String] = candidate[field];
        }
        if (p.read<String>('operation') == 'delete' &&
            data.containsKey('deleted_at')) {
          data['deleted_at'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        }
      }
    }
    final info = await db.customSelect('PRAGMA table_info("$entity")').get();
    final columns = info.map((r) => r.read<String>('name')).toSet();
    if (data.keys.any(
      (k) => !columns.contains(k) || deviceOnlyColumns.contains(k),
    )) {
      throw StateError('无效同步字段');
    }
    final where = keys.map((k) => '"$k"=?').join(' AND ');
    final keyValues = keys.map((k) => data[k]).toList();
    final existing = await db
        .customSelect(
          'SELECT * FROM "$entity" WHERE $where',
          variables: sqlVariables(keyValues),
        )
        .getSingleOrNull();
    if (record['deletedAt'] != null) {
      if (columns.contains('deleted_at')) {
        data['deleted_at'] =
            DateTime.parse(record['deletedAt'] as String)
                .millisecondsSinceEpoch ~/
            1000;
      } else {
        await db.customStatement(
          'DELETE FROM "$entity" WHERE $where',
          keyValues,
        );
      }
    }
    if (record['deletedAt'] == null || columns.contains('deleted_at')) {
      if (existing == null) {
        if (entity == 'attachments') {
          data['relative_path'] =
              'files/sync/$id/${_safeName(data['original_name'] as String? ?? 'file')}';
        }
        if (entity == 'order_files') {
          data['local_relative_path'] =
              'files/sync/$id/${_safeName(data['original_name'] as String? ?? 'file')}';
        }
        await db.customStatement(
          'INSERT INTO "$entity" (${data.keys.map((k) => '"$k"').join(',')}) VALUES(${List.filled(data.length, '?').join(',')})',
          data.values.toList(),
        );
      } else {
        await db.customStatement(
          'UPDATE "$entity" SET ${data.keys.map((k) => '"$k"=?').join(',')} WHERE $where',
          [...data.values, ...keyValues],
        );
      }
    }
    await db.customStatement(
      '''INSERT INTO sync_metadata(entity_type,record_key,sync_id,sync_version,local_updated_at,deleted_at,sync_status,payload)
      VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(entity_type,record_key) DO UPDATE SET
      sync_id=excluded.sync_id,sync_version=excluded.sync_version,deleted_at=excluded.deleted_at,
      sync_status=excluded.sync_status,payload=excluded.payload''',
      [
        entity,
        key,
        id,
        record['version'],
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        record['deletedAt'] == null
            ? null
            : DateTime.parse(record['deletedAt'] as String)
                      .millisecondsSinceEpoch ~/
                  1000,
        pending.isEmpty ? 'synced' : 'dirty',
        jsonEncode(canonical),
      ],
    );
    // Raw SQL applies must notify existing Drift watchers too.
    db.notifyUpdates({
      for (final table in db.allTables.where(
        (t) => t.actualTableName == entity,
      ))
        TableUpdate.onTable(table),
    });
  }

  static String _safeName(String value) =>
      value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');

  Future<void> storeConflicts(List<dynamic> records) =>
      SyncConflictService(db).store(records);
}
