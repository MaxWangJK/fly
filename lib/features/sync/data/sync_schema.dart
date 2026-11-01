import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

// Additive sidecar metadata keeps all 1.0 row classes, keys and foreign keys intact.
// Each business write and its durable mutation are captured by the same SQLite statement.
const syncTables = [
  'app_settings',
  'dashboard_focuses',
  'dashboard_focus_histories',
  'dashboard_daily_focuses',
  'daily_reviews',
  'file_folders',
  'file_tags',
  'file_tag_links',
  'note_folders',
  'workspace_notes',
  'knowledge_favorites',
  'note_blocks',
  'note_tag_links',
  'task_lists',
  'tasks',
  'tags',
  'task_tags',
  'checklist_items',
  'reminders',
  'customer_categories',
  'customer_statuses',
  'customer_sources',
  'customers',
  'customer_contacts',
  'customer_notes',
  'customer_custom_field_definitions',
  'customer_custom_field_values',
  'customer_follow_ups',
  'customer_tag_links',
  'order_statuses',
  'orders',
  'order_notes',
  'factories',
  'products',
  'order_production_items',
  'order_payments',
  'order_cost_entries',
  'order_tag_links',
  'order_files',
  'attachments',
  'container_presets',
  'cargo_packages',
  'loading_plans',
  'loading_plan_groups',
  'container_sections',
  'section_cargo_entries',
];
const deviceOnlyColumns = {
  'relative_path',
  'local_relative_path',
  'thumbnail_relative_path',
  'last_opened_at',
};
const syncSettingKeys = ['themeMode', 'locale', 'colorPalette'];

Future<void> createSyncSchema(AppDatabase db) async {
  for (final sql in [
    'CREATE TABLE IF NOT EXISTS sync_control (id INTEGER PRIMARY KEY CHECK(id=1), applying INTEGER NOT NULL DEFAULT 0)',
    'INSERT OR IGNORE INTO sync_control(id) VALUES(1)',
    '''CREATE TABLE IF NOT EXISTS sync_metadata (
      entity_type TEXT NOT NULL, record_key TEXT NOT NULL, sync_id TEXT,
      sync_version INTEGER NOT NULL DEFAULT 0, local_updated_at INTEGER NOT NULL,
      deleted_at INTEGER, sync_status TEXT NOT NULL DEFAULT 'dirty', payload TEXT NOT NULL,
      PRIMARY KEY(entity_type,record_key), UNIQUE(entity_type,sync_id))''',
    '''CREATE TABLE IF NOT EXISTS sync_outbox (
      ordinal INTEGER PRIMARY KEY AUTOINCREMENT, mutation_id TEXT NOT NULL UNIQUE,
      entity_type TEXT NOT NULL, record_key TEXT NOT NULL, base_version INTEGER NOT NULL,
      changed_fields TEXT NOT NULL, payload TEXT NOT NULL, operation TEXT NOT NULL,
      created_at INTEGER NOT NULL, dispatched TEXT)''',
    'CREATE INDEX IF NOT EXISTS sync_outbox_record ON sync_outbox(entity_type,record_key,ordinal)',
    'CREATE TABLE IF NOT EXISTS sync_state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    'CREATE TABLE IF NOT EXISTS sync_conflicts (id TEXT PRIMARY KEY, data TEXT NOT NULL, resolved INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS sync_incoming (entity_type TEXT NOT NULL, record_id TEXT NOT NULL, data TEXT NOT NULL, PRIMARY KEY(entity_type,record_id))',
    'CREATE TABLE IF NOT EXISTS lan_devices (id TEXT PRIMARY KEY, name TEXT NOT NULL, token_hash TEXT NOT NULL, revoked INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS lan_records (entity_type TEXT NOT NULL, record_id TEXT NOT NULL, version INTEGER NOT NULL, data TEXT NOT NULL, deleted_at TEXT, PRIMARY KEY(entity_type,record_id))',
    'CREATE TABLE IF NOT EXISTS lan_changes (seq INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT NOT NULL)',
    'CREATE TABLE IF NOT EXISTS lan_mutations (mutation_id TEXT PRIMARY KEY, request_hash TEXT NOT NULL, result TEXT NOT NULL)',
  ]) {
    await db.customStatement(sql);
  }
  for (final table in syncTables) {
    final info = await db.customSelect('PRAGMA table_info("$table")').get();
    final columns = info.map((r) => r.read<String>('name')).toList();
    final keys = info.where((r) => r.read<int>('pk') > 0).toList()
      ..sort((a, b) => a.read<int>('pk').compareTo(b.read<int>('pk')));
    final primary = keys.map((r) => r.read<String>('name')).toList();
    String key(String prefix) =>
        'json_array(${primary.map((c) => '$prefix."$c"').join(',')})';
    final fields = columns
        .where((c) => !deviceOnlyColumns.contains(c))
        .toList();
    String payload(String prefix) =>
        'json_object(${fields.map((c) => "'$c',$prefix.\"$c\"").join(',')})';
    final uuid =
        "lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))),2) || '-a' || substr(lower(hex(randomblob(2))),2) || '-' || lower(hex(randomblob(6)))";
    final deletedNew = columns.contains('deleted_at')
        ? 'NEW.deleted_at'
        : 'NULL';
    final deletedSeed = columns.contains('deleted_at')
        ? 's.deleted_at'
        : 'NULL';
    final allowedNew = table == 'app_settings'
        ? "AND NEW.key IN (${syncSettingKeys.map((k) => "'$k'").join(',')})"
        : '';
    final allowedOld = allowedNew.replaceAll('NEW.', 'OLD.');
    final deletedOp = columns.contains('deleted_at')
        ? "CASE WHEN NEW.deleted_at IS NOT NULL THEN 'delete' WHEN OLD.deleted_at IS NOT NULL THEN 'restore' ELSE 'upsert' END"
        : "'upsert'";
    final changed = fields
        .where((c) => !primary.contains(c))
        .map((c) => "SELECT '$c' AS field WHERE NEW.\"$c\" IS NOT OLD.\"$c\"")
        .join(' UNION ALL ');
    final meaningful = fields
        .where(
          (c) => !primary.contains(c) && !{'updated_at', 'version'}.contains(c),
        )
        .map((c) => 'NEW."$c" IS NOT OLD."$c"')
        .join(' OR ');
    for (final event in ['insert', 'update', 'delete']) {
      final prefix = event == 'delete' ? 'OLD' : 'NEW';
      final allowed = event == 'delete' ? allowedOld : allowedNew;
      final op = event == 'delete'
          ? "'delete'"
          : event == 'insert'
          ? (columns.contains('deleted_at')
                ? "CASE WHEN NEW.deleted_at IS NOT NULL THEN 'delete' WHEN EXISTS(SELECT 1 FROM sync_metadata WHERE entity_type='$table' AND record_key=${key('NEW')} AND deleted_at IS NOT NULL) THEN 'restore' ELSE 'upsert' END"
                : "CASE WHEN EXISTS(SELECT 1 FROM sync_metadata WHERE entity_type='$table' AND record_key=${key('NEW')} AND deleted_at IS NOT NULL) THEN 'restore' ELSE 'upsert' END")
          : deletedOp;
      final deleted = event == 'delete'
          ? "CAST(strftime('%s','now') AS INTEGER)"
          : deletedNew;
      final changes = event == 'update'
          ? (changed.isEmpty
                ? "'[]'"
                : '(SELECT json_group_array(field) FROM ($changed))')
          : "'${jsonEncode(fields)}'";
      final condition = event == 'update' && meaningful.isNotEmpty
          ? 'AND ($meaningful)'
          : '';
      await db.customStatement(
        '''CREATE TRIGGER IF NOT EXISTS sync_${table}_$event
        AFTER ${event.toUpperCase()} ON "$table"
        WHEN (SELECT applying FROM sync_control WHERE id=1)=0 $allowed $condition
        BEGIN
          INSERT INTO sync_outbox(mutation_id,entity_type,record_key,base_version,changed_fields,payload,operation,created_at)
          VALUES($uuid,'$table',${key(prefix)},
            COALESCE((SELECT sync_version FROM sync_metadata WHERE entity_type='$table' AND record_key=${key(prefix)}),0),
            $changes,${payload(prefix)},$op,
            CAST(strftime('%s','now') AS INTEGER)*1000+CAST(substr(strftime('%f','now'),4,3) AS INTEGER));
          INSERT INTO sync_metadata(entity_type,record_key,local_updated_at,deleted_at,payload)
          VALUES('$table',${key(prefix)},CAST(strftime('%s','now') AS INTEGER),$deleted,${payload(prefix)})
          ON CONFLICT(entity_type,record_key) DO UPDATE SET
            local_updated_at=excluded.local_updated_at,deleted_at=excluded.deleted_at,
            sync_status='dirty',payload=excluded.payload;
        END''',
      );
    }
    final filter = table == 'app_settings'
        ? "WHERE s.key IN (${syncSettingKeys.map((k) => "'$k'").join(',')})"
        : '';
    await db.customStatement(
      '''INSERT OR IGNORE INTO sync_metadata(entity_type,record_key,local_updated_at,deleted_at,payload)
      SELECT '$table',${key('s')},CAST(strftime('%s','now') AS INTEGER),$deletedSeed,${payload('s')}
      FROM "$table" s $filter''',
    );
  }
}

Future<List<String>> syncPrimaryKeys(AppDatabase db, String table) async {
  if (!syncTables.contains(table)) throw ArgumentError('Unknown sync entity');
  final rows = await db.customSelect('PRAGMA table_info("$table")').get();
  final keys = rows.where((r) => r.read<int>('pk') > 0).toList()
    ..sort((a, b) => a.read<int>('pk').compareTo(b.read<int>('pk')));
  return keys.map((r) => r.read<String>('name')).toList();
}

List<Variable> sqlVariables(Iterable<Object?> values) => values
    .map(
      (v) => v is int
          ? Variable<int>(v)
          : v is double
          ? Variable<double>(v)
          : Variable<String>(v as String?),
    )
    .toList();
