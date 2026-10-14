import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../data/sync_outbox_repository.dart';
import '../data/sync_schema.dart';

/// Preserve each coordinator's versions and pending requests when changing modes.
/// Business rows and file paths stay in place; switching cloud accounts is rejected.
class SyncWorkspaceBinding {
  SyncWorkspaceBinding(this.outbox);
  final SyncOutboxRepository outbox;
  static const tables = [
    'sync_metadata',
    'sync_outbox',
    'sync_incoming',
    'sync_conflicts',
  ];

  Future<void> activate(String workspace) => outbox.db.transaction(() async {
    final db = outbox.db;
    final previous = await outbox.state('workspace');
    final kind = workspace.startsWith('cloud:') ? 'cloud' : 'lan';
    if (previous != null) {
      final previousKind = previous.startsWith('cloud:') ? 'cloud' : 'lan';
      await outbox.saveState(
        'binding:$previousKind',
        await outbox.state('binding:$previousKind') ?? previous,
      );
    }
    final pinned = await outbox.state('binding:$kind');
    if (pinned != null && pinned != workspace) {
      throw StateError(
        '此数据目录已连接其它${kind == 'cloud' ? '账号或服务器' : '电脑'}。请使用独立数据目录，避免混入其它工作区的数据。',
      );
    }
    await outbox.saveState('binding:$kind', workspace);
    if (previous == null || previous == workspace) {
      await outbox.bind(workspace);
      return;
    }
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS sync_workspace_contexts (workspace TEXT PRIMARY KEY, data TEXT NOT NULL)',
    );
    final snapshot = <String, Object?>{};
    for (final table in tables) {
      snapshot[table] = [
        for (final row in await db.customSelect('SELECT * FROM "$table"').get())
          row.data,
      ];
    }
    final cursorKey = previous.startsWith('cloud:')
        ? 'cloudCursor'
        : 'lanCursor';
    snapshot['cursor'] = await outbox.state(cursorKey) ?? '0';
    await db.customStatement(
      'INSERT INTO sync_workspace_contexts(workspace,data) VALUES(?,?) ON CONFLICT(workspace) DO UPDATE SET data=excluded.data',
      [previous, jsonEncode(snapshot)],
    );

    // Capture live local rows, including edits made while the other mode was active.
    final local = <String, Map<String, dynamic>>{};
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final entity in syncTables) {
      final columns =
          (await db.customSelect('PRAGMA table_info("$entity")').get())
              .map((r) => r.read<String>('name'))
              .where((c) => !deviceOnlyColumns.contains(c))
              .toList();
      final keys = await syncPrimaryKeys(db, entity);
      final filter = entity == 'app_settings'
          ? " WHERE key IN (${syncSettingKeys.map((k) => "'$k'").join(',')})"
          : '';
      for (final row
          in await db
              .customSelect(
                'SELECT ${columns.map((c) => '"$c"').join(',')} FROM "$entity"$filter',
              )
              .get()) {
        final key = jsonEncode(keys.map((k) => row.data[k]).toList());
        local['$entity:$key'] = {
          'entity_type': entity,
          'record_key': key,
          'payload': row.data,
          'deleted_at': row.data['deleted_at'],
        };
      }
    }
    // Keep hard-delete tombstones too; they have no remaining business row.
    for (final raw in snapshot['sync_metadata'] as List) {
      final row = (raw as Map).cast<String, dynamic>();
      if (row['deleted_at'] != null) {
        local.putIfAbsent(
          '${row['entity_type']}:${row['record_key']}',
          () => {...row, 'payload': jsonDecode(row['payload'] as String)},
        );
      }
    }
    for (final table in tables) {
      await db.customStatement('DELETE FROM "$table"');
    }
    final saved = await db
        .customSelect(
          'SELECT data FROM sync_workspace_contexts WHERE workspace=?',
          variables: sqlVariables([workspace]),
        )
        .getSingleOrNull();
    final restored = saved == null
        ? null
        : jsonDecode(saved.read<String>('data')) as Map;
    if (restored != null) {
      for (final table in tables) {
        for (final raw in restored[table] as List) {
          final row = (raw as Map).cast<String, dynamic>();
          await db.customStatement(
            'INSERT INTO "$table" (${row.keys.map((k) => '"$k"').join(',')}) VALUES(${List.filled(row.length, '?').join(',')})',
            row.values.toList(),
          );
        }
      }
    }
    await outbox.saveState(
      workspace.startsWith('cloud:') ? 'cloudCursor' : 'lanCursor',
      '${restored?['cursor'] ?? 0}',
    );
    for (final row in local.values) {
      final entity = row['entity_type'] as String,
          key = row['record_key'] as String;
      final payload = (row['payload'] as Map).cast<String, dynamic>();
      final metadata = await db
          .customSelect(
            'SELECT * FROM sync_metadata WHERE entity_type=? AND record_key=?',
            variables: sqlVariables([entity, key]),
          )
          .getSingleOrNull();
      if (metadata == null) {
        await db.customStatement(
          'INSERT INTO sync_metadata(entity_type,record_key,local_updated_at,deleted_at,payload) VALUES(?,?,?,?,?)',
          [entity, key, timestamp, row['deleted_at'], jsonEncode(payload)],
        );
        continue; // bind() seeds a new record once.
      }
      final projected = (jsonDecode(metadata.read<String>('payload')) as Map)
          .cast<String, dynamic>();
      var deleted = metadata.data['deleted_at'] != null;
      final pending = await db
          .customSelect(
            'SELECT * FROM sync_outbox WHERE entity_type=? AND record_key=? ORDER BY ordinal',
            variables: sqlVariables([entity, key]),
          )
          .get();
      for (final mutation in pending) {
        final data = jsonDecode(mutation.read<String>('payload')) as Map;
        for (final field
            in jsonDecode(mutation.read<String>('changed_fields')) as List) {
          projected[field as String] = data[field];
        }
        deleted = mutation.read<String>('operation') == 'delete';
      }
      final changed = payload.keys
          .where((k) => payload[k] != projected[k])
          .toList();
      final targetDeleted = row['deleted_at'] != null;
      if (changed.isEmpty && deleted == targetDeleted) continue;
      final operation = targetDeleted
          ? 'delete'
          : deleted
          ? 'restore'
          : 'upsert';
      await db.customStatement(
        'INSERT INTO sync_outbox(mutation_id,entity_type,record_key,base_version,changed_fields,payload,operation,created_at) VALUES(?,?,?,?,?,?,?,?)',
        [
          const Uuid().v4(),
          entity,
          key,
          metadata.read<int>('sync_version'),
          jsonEncode(changed),
          jsonEncode(payload),
          operation,
          timestamp,
        ],
      );
      await db.customStatement(
        "UPDATE sync_metadata SET sync_status='dirty',payload=?,deleted_at=? WHERE entity_type=? AND record_key=?",
        [jsonEncode(payload), row['deleted_at'], entity, key],
      );
    }
    await outbox.saveState('workspace', workspace);
    await outbox.bind(workspace);
  });
}
