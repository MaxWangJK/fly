import 'dart:io';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';
import '../../features/sync/data/sync_schema.dart';

part 'app_database.g.dart';

const _databaseName = String.fromEnvironment(
  'FLY_DATABASE_NAME',
  defaultValue: 'fly',
);

@DriftDatabase(
  tables: [
    AppSettings,
    DashboardFocuses,
    DashboardFocusHistories,
    DashboardDailyFocuses,
    TaskLists,
    Tasks,
    Tags,
    TaskTags,
    ChecklistItems,
    Reminders,
    CustomerCategories,
    CustomerStatuses,
    CustomerSources,
    Customers,
    CustomerContacts,
    CustomerNotes,
    CustomerCustomFieldDefinitions,
    CustomerCustomFieldValues,
    CustomerFollowUps,
    CustomerTagLinks,
    OrderStatuses,
    Orders,
    OrderNotes,
    Factories,
    Products,
    OrderProductionItems,
    OrderPayments,
    OrderCostEntries,
    OrderTagLinks,
    OrderFiles,
    Attachments,
    NotificationDeliveryLogs,
    ContainerPresets,
    CargoPackages,
    LoadingPlans,
    LoadingPlanGroups,
    ContainerSections,
    SectionCargoEntries,
    FileFolders,
    FileTags,
    FileTagLinks,
    NoteFolders,
    WorkspaceNotes,
    KnowledgeFavorites,
    NoteBlocks,
    NoteTagLinks,
    DailyReviews,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  factory AppDatabase.atDataRoot(String rootPath) => AppDatabase(
    NativeDatabase.createInBackground(File(p.join(rootPath, 'fly.db'))),
  );

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: _databaseName,
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }

  @override
  int get schemaVersion => 19;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createIndexes();
      await createSyncSchema(this);
    },
    onUpgrade: (migrator, from, to) async {
      await customStatement('PRAGMA foreign_keys = OFF');
      await transaction(() async {
        if (from < 2) {
          await migrator.createTable(customerCategories);
          await migrator.createTable(customerStatuses);
          await migrator.createTable(customerSources);
          await migrator.createTable(customers);
          await migrator.createTable(customerContacts);
          await migrator.createTable(customerFollowUps);
          await migrator.createTable(customerTagLinks);
          await migrator.createTable(orderStatuses);
          await migrator.createTable(orders);
          await migrator.createTable(factories);
          await migrator.createTable(products);
          await migrator.createTable(orderProductionItems);
          await migrator.createTable(orderPayments);
          await migrator.createTable(orderTagLinks);
          await migrator.createTable(orderFiles);
        }
        if (from < 3) {
          await migrator.createTable(customerNotes);
          await customStatement(
            "INSERT OR IGNORE INTO customer_notes "
            "(id, customer_id, content, color_value, sort_order, created_at, updated_at, deleted_at, version) "
            "SELECT 'legacy-' || id, id, notes, 4293521403, 0, updated_at, updated_at, NULL, 1 "
            "FROM customers WHERE TRIM(notes) <> ''",
          );
          await customStatement(
            "UPDATE customers SET priority = 'low' "
            "WHERE priority IS NULL OR priority = '' OR priority = 'none'",
          );
          await customStatement(
            "UPDATE orders SET priority = 'low' "
            "WHERE priority IS NULL OR priority = '' OR priority = 'none'",
          );
        }
        if (from < 4) {
          await migrator.createTable(customerCustomFieldDefinitions);
          await migrator.createTable(customerCustomFieldValues);
          await migrator.createTable(orderNotes);
          if (!await _columnExists('orders', 'base_profit_currency')) {
            await migrator.addColumn(orders, orders.baseProfitCurrency);
          }
          if (!await _columnExists('orders', 'exchange_rate_micros')) {
            await migrator.addColumn(orders, orders.exchangeRateMicros);
          }
          await customStatement(
            'UPDATE orders SET base_profit_currency = currency, '
            'exchange_rate_micros = 1000000',
          );
          await customStatement(
            "INSERT OR IGNORE INTO order_notes "
            "(id, order_id, content, color_value, sort_order, created_at, updated_at, deleted_at, version) "
            "SELECT 'legacy-' || id, id, notes, 4293521403, 0, updated_at, updated_at, NULL, 1 "
            "FROM orders WHERE TRIM(notes) <> ''",
          );
        }
        if (from < 5) {
          if (!await _columnExists('tags', 'is_active')) {
            await migrator.addColumn(tags, tags.isActive);
          }
          if (!await _columnExists('order_payments', 'attachment_id')) {
            await migrator.addColumn(orderPayments, orderPayments.attachmentId);
          }
          await migrator.createTable(orderCostEntries);
          for (final entry in const [
            ('inland', 'inland_cost', '内陆费'),
            ('port', 'port_charges', '港杂费'),
            ('other', 'other_cost', '其他费用'),
          ]) {
            await customStatement(
              "INSERT OR IGNORE INTO order_cost_entries "
              "(id, order_id, amount_minor, currency, cost_type, occurred_at, attachment_id, created_at, updated_at, deleted_at) "
              "SELECT 'legacy-${entry.$1}-' || id, id, ${entry.$2}, base_profit_currency, '${entry.$3}', "
              "COALESCE(order_date, created_at), NULL, created_at, updated_at, NULL "
              "FROM orders WHERE ${entry.$2} <> 0",
            );
          }
        }
        if (from < 6) {
          await migrator.createTable(appSettings);
          if (!await _columnExists('customers', 'customs_info')) {
            await migrator.addColumn(customers, customers.customsInfo);
          }
          await customStatement(
            "INSERT OR REPLACE INTO app_settings (`key`, value, updated_at) "
            "VALUES ('demoSeedVersion', '-1', CAST(strftime('%s','now') AS INTEGER))",
          );
          await customStatement(
            'UPDATE orders SET base_profit_currency = currency, '
            'exchange_rate_micros = 1000000',
          );
          await customStatement(
            'UPDATE order_payments SET currency = '
            '(SELECT currency FROM orders WHERE orders.id = order_payments.order_id) '
            'WHERE EXISTS (SELECT 1 FROM orders WHERE orders.id = order_payments.order_id)',
          );
          await customStatement(
            'UPDATE order_cost_entries SET currency = '
            '(SELECT currency FROM orders WHERE orders.id = order_cost_entries.order_id) '
            'WHERE EXISTS (SELECT 1 FROM orders WHERE orders.id = order_cost_entries.order_id)',
          );
        }
        if (from < 7) {
          if (!await _columnExists('orders', 'tax_refund_currency')) {
            await migrator.addColumn(orders, orders.taxRefundCurrency);
          }
          if (!await _columnExists(
            'order_production_items',
            'factory_cost_currency',
          )) {
            await migrator.addColumn(
              orderProductionItems,
              orderProductionItems.factoryCostCurrency,
            );
          }
          // V6 used one order-level currency for every financial value. Preserve
          // that explicit meaning while moving to per-amount currencies.
          await customStatement(
            "UPDATE orders SET tax_refund_currency = "
            "CASE WHEN UPPER(currency) = 'RMB' THEN 'CNY' "
            "WHEN UPPER(currency) IN ('CNY', 'USD') THEN UPPER(currency) "
            "ELSE 'CNY' END",
          );
          await customStatement(
            "UPDATE order_production_items SET factory_cost_currency = "
            "COALESCE((SELECT CASE WHEN UPPER(currency) = 'RMB' THEN 'CNY' "
            "WHEN UPPER(currency) IN ('CNY', 'USD') THEN UPPER(currency) "
            "ELSE 'CNY' END FROM orders "
            "WHERE orders.id = order_production_items.order_id), 'CNY')",
          );
        }
        if (from < 8) {
          if (!await _columnExists('customers', 'next_action_type')) {
            await migrator.addColumn(customers, customers.nextActionType);
          }
          if (!await _columnExists('customer_follow_ups', 'next_action_type')) {
            await migrator.addColumn(
              customerFollowUps,
              customerFollowUps.nextActionType,
            );
          }
          await migrator.createTable(attachments);
          await migrator.createTable(notificationDeliveryLogs);
          // Keep the legacy order_files table as a compatibility source while
          // projecting every existing row into the unified attachment model.
          await customStatement(
            'INSERT OR IGNORE INTO attachments '
            '(id, owner_type, owner_id, file_name, original_name, relative_path, '
            'mime_type, file_size, document_type, created_at, updated_at, deleted_at) '
            "SELECT id, 'order', order_id, file_name, original_name, "
            'local_relative_path, mime_type, file_size, document_type, '
            'created_at, updated_at, deleted_at FROM order_files',
          );
        }
        if (from < 9) {
          await migrator.createTable(containerPresets);
          await migrator.createTable(cargoPackages);
          await migrator.createTable(loadingPlans);
          await migrator.createTable(loadingPlanGroups);
        }
        if (from < 10) {
          if (!await _columnExists(
            'cargo_packages',
            'default_section_quantity',
          )) {
            await migrator.addColumn(
              cargoPackages,
              cargoPackages.defaultSectionQuantity,
            );
          }
          for (final column in [
            loadingPlanGroups.sectionId,
            loadingPlanGroups.entryId,
            loadingPlanGroups.needsReview,
            loadingPlanGroups.allowStack,
          ]) {
            if (!await _columnExists('loading_plan_groups', column.$name)) {
              await migrator.addColumn(loadingPlanGroups, column);
            }
          }
          await migrator.createTable(containerSections);
          await migrator.createTable(sectionCargoEntries);
          await _migrateLoadingSections();
          await customStatement(
            "UPDATE cargo_packages SET default_section_quantity = 286 WHERE id = 'cargo-wpc-grille' AND default_section_quantity IS NULL",
          );
        }
        if (from < 11) {
          for (final table in <TableInfo>[
            fileFolders,
            fileTags,
            fileTagLinks,
            noteFolders,
            workspaceNotes,
            noteBlocks,
          ]) {
            final existing = await customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
              variables: [Variable(table.actualTableName)],
            ).getSingleOrNull();
            if (existing == null) await migrator.createTable(table);
          }
          for (final column in [
            attachments.folderId,
            attachments.displayName,
            attachments.sha256,
            attachments.thumbnailRelativePath,
            attachments.lastOpenedAt,
            attachments.deletionBatch,
          ]) {
            if (!await _columnExists('attachments', column.$name)) {
              await migrator.addColumn(attachments, column);
            }
          }
          await customStatement(
            'UPDATE attachments SET display_name = original_name',
          );
        }
        if (from < 12) {
          await migrator.createTable(noteTagLinks);
        }
        if (from < 13) {
          final existing = await customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='daily_reviews'",
          ).getSingleOrNull();
          if (existing == null) await migrator.createTable(dailyReviews);
        }
        if (from < 14) {
          final columns = await customSelect(
            'PRAGMA table_info(workspace_notes)',
          ).get();
          if (!columns.any(
            (row) => row.read<String>('name') == 'manual_sort_order',
          )) {
            await migrator.addColumn(
              workspaceNotes,
              workspaceNotes.manualSortOrder,
            );
          }
        }
        if (from < 15) {
          for (final column in [
            customerFollowUps.origin,
            customerFollowUps.quickActionDate,
            customerFollowUps.quickSnapshot,
          ]) {
            if (!await _columnExists('customer_follow_ups', column.$name)) {
              await migrator.addColumn(customerFollowUps, column);
            }
          }
          final hasScope = await _columnExists('tags', 'scope');
          await migrator.alterTable(
            TableMigration(tags, newColumns: hasScope ? [] : [tags.scope]),
          );
          // Preserve original customer IDs; clone definitions for each other domain.
          // This also isolates historic Task and Note links without losing names.
          for (final entry in const [
            ('order', 'order_tag_links'),
            ('note', 'note_tag_links'),
            ('task', 'task_tags'),
          ]) {
            await customStatement(
              'INSERT INTO tags (id,scope,name,color_value,is_active,created_at,updated_at,deleted_at,version) '
              "SELECT 'v11-${entry.$1}-' || t.id, '${entry.$1}', t.name,t.color_value,t.is_active,t.created_at,t.updated_at,t.deleted_at,t.version "
              'FROM tags t WHERE t.scope = ? AND EXISTS (SELECT 1 FROM ${entry.$2} l WHERE l.tag_id=t.id)',
              ['customer'],
            );
            await customStatement(
              "UPDATE ${entry.$2} SET tag_id='v11-${entry.$1}-' || tag_id",
            );
          }
          // Unused original definitions owned only by another domain must not leak
          // into the customer selector. Retain the row for historical references.
          await customStatement(
            "UPDATE tags SET scope='legacy' WHERE scope='customer' "
            'AND NOT EXISTS (SELECT 1 FROM customer_tag_links l WHERE l.tag_id=tags.id) '
            'AND NOT EXISTS (SELECT 1 FROM customer_categories c WHERE c.tag_id=tags.id) '
            "AND EXISTS (SELECT 1 FROM tags clone WHERE clone.id IN ('v11-order-' || tags.id, 'v11-note-' || tags.id, 'v11-task-' || tags.id))",
          );
        }
        if (from < 16) {
          await migrator.createTable(dashboardFocuses);
          await migrator.createTable(dashboardFocusHistories);
          await migrator.createTable(dashboardDailyFocuses);
        }
        if (from < 17) {
          if (!await _columnExists(
            'workspace_notes',
            'linked_knowledge_article_id',
          )) {
            await migrator.addColumn(
              workspaceNotes,
              workspaceNotes.linkedKnowledgeArticleId,
            );
          }
          await migrator.createTable(knowledgeFavorites);
        }
        if (from < 19 && !await _columnExists('task_lists', 'parent_id')) {
          await migrator.addColumn(taskLists, taskLists.parentId);
          for (final event in ['insert', 'update', 'delete']) {
            await customStatement(
              'DROP TRIGGER IF EXISTS sync_task_lists_$event',
            );
          }
        }
        if (from < 19) await createSyncSchema(this);
        await _createIndexes();
        final violations = await customSelect('PRAGMA foreign_key_check').get();
        if (violations.isNotEmpty) {
          throw StateError(
            'Database migration found invalid references. Changes were rolled back.',
          );
        }
      });
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
    },
  );

  Future<void> _migrateLoadingSections() async {
    final plans = await customSelect(
      'SELECT p.id, c.inner_length_mm FROM loading_plans p JOIN container_presets c ON c.id = p.container_preset_id',
    ).get();
    for (final plan in plans) {
      final id = plan.read<String>('id');
      final length = plan.read<int>('inner_length_mm');
      final count = length < 2900 ? 1 : length ~/ 2900;
      final sectionLength = length < 2900 ? length : 2900;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      for (var i = 0; i < count; i++) {
        await customStatement(
          'INSERT INTO container_sections (id,plan_id,section_index,name,start_xmm,length_mm,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)',
          [
            '$id-section-$i',
            id,
            i,
            '第${i + 1}节',
            i * sectionLength,
            sectionLength,
            now,
            now,
          ],
        );
      }
      final groups = await customSelect(
        'SELECT g.*, c.name AS cargo_name, c.type AS cargo_type, c.length_mm AS cargo_l, c.width_mm AS cargo_w, c.height_mm AS cargo_h, c.weight_grams AS cargo_weight, c.stackable AS cargo_stack FROM loading_plan_groups g JOIN cargo_packages c ON c.id = g.cargo_package_id WHERE g.plan_id = ?',
        variables: [Variable(id)],
      ).get();
      for (final group in groups) {
        final x = group.read<int>('position_xmm');
        final index = x ~/ sectionLength;
        final valid =
            x >= 0 &&
            index < count &&
            x + group.read<int>('bounding_length_mm') <=
                (index + 1) * sectionLength;
        final sectionId = '$id-section-${valid ? index : 0}';
        final groupId = group.read<String>('id');
        final entryId = 'legacy-entry-$groupId';
        final snapshot = jsonEncode({
          'id': group.read<String>('cargo_package_id'),
          'name': group.read<String>('cargo_name'),
          'type': group.read<String>('cargo_type'),
          'l': group.read<int>('cargo_l'),
          'w': group.read<int>('cargo_w'),
          'h': group.read<int>('cargo_h'),
          'weight': group.read<int>('cargo_weight'),
          'color': group.read<int>('color_value'),
        });
        await customStatement(
          'INSERT INTO section_cargo_entries (id,section_id,cargo_package_id,cargo_snapshot,quantity,allow_stack,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)',
          [
            entryId,
            sectionId,
            group.read<String>('cargo_package_id'),
            snapshot,
            group.read<int>('quantity'),
            group.read<int>('cargo_stack'),
            now,
            now,
          ],
        );
        await customStatement(
          'UPDATE loading_plan_groups SET section_id=?,entry_id=?,needs_review=?,allow_stack=? WHERE id=?',
          [
            sectionId,
            entryId,
            valid ? 0 : 1,
            group.read<int>('cargo_stack'),
            groupId,
          ],
        );
      }
    }
  }

  Future<void> _createIndexes() async {
    const statements = [
      'CREATE INDEX IF NOT EXISTS idx_dashboard_focus_history_date ON dashboard_focus_histories(effective_date DESC, created_at DESC)',
      'CREATE INDEX IF NOT EXISTS idx_dashboard_daily_focus_day ON dashboard_daily_focuses(day_key DESC)',
      'CREATE INDEX IF NOT EXISTS idx_file_folders_parent ON file_folders(parent_id, deleted_at, sort_order)',
      'CREATE INDEX IF NOT EXISTS idx_files_folder ON attachments(folder_id, deleted_at, updated_at)',
      'CREATE INDEX IF NOT EXISTS idx_files_hash ON attachments(sha256, folder_id)',
      'CREATE INDEX IF NOT EXISTS idx_file_tags ON file_tag_links(tag_id, file_id)',
      'CREATE INDEX IF NOT EXISTS idx_note_folders_parent ON note_folders(parent_id, deleted_at, sort_order)',
      'CREATE INDEX IF NOT EXISTS idx_notes_folder ON workspace_notes(folder_id, deleted_at, updated_at)',
      'CREATE INDEX IF NOT EXISTS idx_note_blocks_note ON note_blocks(note_id, sort_order)',
      'CREATE INDEX IF NOT EXISTS idx_tasks_due_active '
          'ON tasks(due_date, deleted_at, status)',
      'CREATE INDEX IF NOT EXISTS idx_tasks_list_sort_active '
          'ON tasks(list_id, deleted_at, status, sort_order)',
      'CREATE INDEX IF NOT EXISTS idx_tasks_matrix_active '
          'ON tasks(importance, urgency, deleted_at, status)',
      'CREATE INDEX IF NOT EXISTS idx_checklist_task_sort '
          'ON checklist_items(task_id, deleted_at, sort_order)',
      'CREATE INDEX IF NOT EXISTS idx_reminders_task_active '
          'ON reminders(task_id, deleted_at, remind_at)',
      'CREATE INDEX IF NOT EXISTS idx_customers_due_active '
          'ON customers(next_follow_up_date, deleted_at, priority)',
      'CREATE INDEX IF NOT EXISTS idx_customers_category_sort '
          'ON customers(category_id, deleted_at, sort_order)',
      'CREATE INDEX IF NOT EXISTS idx_customers_email_normalized '
          'ON customers(email_normalized, deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_customers_whatsapp_normalized '
          'ON customers(whatsapp_normalized, deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_customers_phone_normalized '
          'ON customers(phone_normalized, deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_customer_followups_customer_date '
          'ON customer_follow_ups(customer_id, followed_up_at, deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_customer_notes_customer_date '
          'ON customer_notes(customer_id, created_at, deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_customer_custom_values_customer '
          'ON customer_custom_field_values(customer_id, definition_id, deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_customer_tag_links_tag '
          'ON customer_tag_links(tag_id, customer_id)',
      'CREATE INDEX IF NOT EXISTS idx_orders_created_active '
          'ON orders(created_at, deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_orders_customer_created '
          'ON orders(customer_id, created_at, deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_orders_status_created '
          'ON orders(status_id, created_at, deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_order_notes_order_date '
          'ON order_notes(order_id, created_at, deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_order_items_order_factory_status '
          'ON order_production_items(order_id, factory_order_status, deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_order_payments_order_date '
          'ON order_payments(order_id, paid_at, deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_order_cost_entries_order_date '
          'ON order_cost_entries(order_id, occurred_at, deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_order_tag_links_tag '
          'ON order_tag_links(tag_id, order_id)',
      'CREATE INDEX IF NOT EXISTS idx_order_files_order_type '
          'ON order_files(order_id, document_type, deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_attachments_owner_type '
          'ON attachments(owner_type, owner_id, document_type, deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_notification_delivery_lookup '
          'ON notification_delivery_logs(entity_type, entity_id, scheduled_time)',
      'CREATE INDEX IF NOT EXISTS idx_cargo_packages_name_active '
          'ON cargo_packages(name, deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_loading_plans_updated_active '
          'ON loading_plans(updated_at, deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_loading_plan_groups_plan_sort '
          'ON loading_plan_groups(plan_id, sort_order)',
    ];
    for (final statement in statements) {
      await customStatement(statement);
    }
  }

  Future<bool> _columnExists(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.any((row) => row.data['name'] == column);
  }

  Future<void> ensureBuiltInData() async {
    final now = DateTime.now();
    await transaction(() async {
      await into(taskLists).insertOnConflictUpdate(
        TaskListsCompanion.insert(
          id: 'inbox',
          name: 'Inbox',
          createdAt: now,
          updatedAt: now,
          sortOrder: 1024,
        ),
      );
      await _ensureCrmDefaults(now);
      await _ensureOrderDefaults(now);
      await _ensureContainerLoadingDefaults(now);
      const renameKey = 'flyTaskListNamesV11Build21';
      final renamed = await (select(
        appSettings,
      )..where((row) => row.key.equals(renameKey))).getSingleOrNull();
      if (renamed == null) {
        for (final item in const [
          ('work', '工作任务', '事务推进'),
          ('personal', '个人备忘', '生活随记'),
          ('shopping', '购物清单', '采购备办'),
          ('study', '学习安排', '成长积累'),
          ('fitness', '锻炼计划', '活力习惯'),
          ('wish', '心愿清单', '未来愿景'),
        ]) {
          await (update(taskLists)..where(
                (row) =>
                    row.id.equals(item.$1) &
                    row.name.equals(item.$2) &
                    row.deletedAt.isNull(),
              ))
              .write(
                TaskListsCompanion(name: Value(item.$3), updatedAt: Value(now)),
              );
        }
        await into(appSettings).insert(
          AppSettingsCompanion.insert(
            key: renameKey,
            value: '1',
            updatedAt: now,
          ),
        );
      }
    });
  }

  Future<void> _ensureContainerLoadingDefaults(DateTime now) async {
    const presets = [
      ('container-40hq', '40HQ', 11900, 2200, 2690, 28000000, 0xFF718096),
      ('container-20gp', '20GP', 5800, 2200, 2320, 28000000, 0xFF718096),
    ];
    for (final value in presets) {
      await into(containerPresets).insert(
        ContainerPresetsCompanion.insert(
          id: value.$1,
          name: value.$2,
          innerLengthMm: value.$3,
          innerWidthMm: value.$4,
          innerHeightMm: value.$5,
          maxPayloadGrams: value.$6,
          colorValue: Value(value.$7),
          isBuiltIn: const Value(true),
          createdAt: now,
          updatedAt: now,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }

    const cargo = [
      (
        'cargo-wpc-grille',
        'WPC 格栅',
        'package',
        2900,
        160,
        120,
        18000,
        0xFF79A88C,
        false,
      ),
      (
        'cargo-standard-pallet',
        '标准托盘',
        'pallet',
        1200,
        1000,
        1200,
        800000,
        0xFF7FA7C9,
        true,
      ),
    ];
    for (final value in cargo) {
      await into(cargoPackages).insert(
        CargoPackagesCompanion.insert(
          id: value.$1,
          name: value.$2,
          type: Value(value.$3),
          lengthMm: value.$4,
          widthMm: value.$5,
          heightMm: value.$6,
          weightGrams: value.$7,
          colorValue: Value(value.$8),
          allowRotateX: Value(value.$9),
          allowRotateY: Value(value.$9),
          allowRotateZ: Value(value.$9),
          stackable: Value(value.$3 != 'pallet'),
          defaultSectionQuantity: Value(
            value.$1 == 'cargo-wpc-grille' ? 286 : null,
          ),
          createdAt: now,
          updatedAt: now,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

  Future<void> _ensureCrmDefaults(DateTime now) async {
    const categories = [
      ('category-a', 'A级', 0xFFE9EFFB),
      ('category-b', 'B级', 0xFFEAF4EF),
      ('category-c', 'C级', 0xFFF8F1E4),
      ('category-d', 'D级', 0xFFF0ECF8),
    ];
    for (var index = 0; index < categories.length; index++) {
      final value = categories[index];
      final tagId = await _ensureTag(
        preferredId: '${value.$1}-tag',
        name: value.$2,
        colorValue: value.$3,
        now: now,
      );
      await into(customerCategories).insert(
        CustomerCategoriesCompanion.insert(
          id: value.$1,
          name: value.$2,
          tagId: Value(tagId),
          colorValue: Value(value.$3),
          sortOrder: (index + 1) * 1024,
          createdAt: now,
          updatedAt: now,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }

    const statuses = [
      ('customer-new', '新客户', 0xFF6B7A90),
      ('customer-inquiry', '询盘客户', 0xFF5E7BB8),
      ('customer-developing', '开发中', 0xFF4D6BD8),
      ('customer-followup', '待跟进', 0xFFC6903E),
      ('customer-quoted', '报价客户', 0xFF9A72B5),
      ('customer-sample', '样品客户', 0xFF3A86D8),
      ('customer-intent', '意向客户', 0xFF5F8D78),
      ('customer-won', '成交客户', 0xFF3D8A69),
      ('customer-repeat', '复购客户', 0xFF397A61),
    ];
    for (var index = 0; index < statuses.length; index++) {
      final value = statuses[index];
      await into(customerStatuses).insert(
        CustomerStatusesCompanion.insert(
          id: value.$1,
          name: value.$2,
          colorValue: Value(value.$3),
          sortOrder: (index + 1) * 1024,
          createdAt: now,
          updatedAt: now,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }

    const sources = [
      ('source-facebook', 'Facebook'),
      ('source-alibaba', 'Alibaba'),
      ('source-google', 'Google'),
      ('source-website', 'Website'),
      ('source-exhibition', 'Exhibition'),
      ('source-referral', 'Referral'),
      ('source-whatsapp', 'WhatsApp'),
      ('source-linkedin', 'LinkedIn'),
      ('source-existing', 'Existing Customer'),
      ('source-other', 'Other'),
    ];
    for (var index = 0; index < sources.length; index++) {
      final value = sources[index];
      await into(customerSources).insert(
        CustomerSourcesCompanion.insert(
          id: value.$1,
          name: value.$2,
          sortOrder: (index + 1) * 1024,
          createdAt: now,
          updatedAt: now,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

  Future<void> _ensureOrderDefaults(DateTime now) async {
    const statuses = [
      ('order-inquiry', '询价', 0xFF6B7A90),
      ('order-confirming', '待确认', 0xFFC6903E),
      ('order-placed', '已下单', 0xFF5E7BB8),
      ('order-awaiting-deposit', '待收定金', 0xFFD1904A),
      ('order-production', '生产中', 0xFF4D6BD8),
      ('order-awaiting-balance', '待收尾款', 0xFF9A72B5),
      ('order-balance-received', '已收尾款', 0xFF7C6AA6),
      ('order-awaiting-shipment', '待发货', 0xFF3C8D87),
      ('order-shipped', '已发货', 0xFF4A889E),
      ('order-completed', '已完成', 0xFF5F8D78),
      ('order-cancelled', '已取消', 0xFF9A6A6A),
    ];
    for (var index = 0; index < statuses.length; index++) {
      final value = statuses[index];
      await into(orderStatuses).insert(
        OrderStatusesCompanion.insert(
          id: value.$1,
          name: value.$2,
          colorValue: Value(value.$3),
          sortOrder: (index + 1) * 1024,
          createdAt: now,
          updatedAt: now,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

  Future<String> _ensureTag({
    required String preferredId,
    required String name,
    required int colorValue,
    required DateTime now,
  }) async {
    final existing =
        await (select(tags)
              ..where((row) => row.name.equals(name) & row.deletedAt.isNull()))
            .getSingleOrNull();
    if (existing != null) return existing.id;
    await into(tags).insert(
      TagsCompanion.insert(
        id: preferredId,
        name: name,
        colorValue: Value(colorValue),
        createdAt: now,
        updatedAt: now,
      ),
      mode: InsertMode.insertOrIgnore,
    );
    return preferredId;
  }
}
