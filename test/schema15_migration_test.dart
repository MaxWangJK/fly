import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';

void main() {
  test('schema 14 to 17 preserves rows and separates shared tag links', () async {
    final root = await Directory.systemTemp.createTemp('fly-schema15-');
    final file = File(p.join(root.path, 'fly.db'));
    var db = AppDatabase(NativeDatabase(file));
    try {
      await db.ensureBuiltInData();
      final customers = DriftCustomerRepository(db);
      final orders = DriftOrderRepository(db);
      final customer = await customers.createCustomer(name: 'Preserved Jack');
      final order = await orders.createOrder(
        customerId: customer.id,
        orderNumber: 'SO-PRESERVED',
      );
      final tag = await customers.findOrCreateTag('WPC');
      await customers.setCustomerTags(customer.id, [tag.id]);
      // Before V11 the same tag definition could be linked by both domains.
      await db.customStatement(
        'INSERT INTO order_tag_links (order_id, tag_id) VALUES (?, ?)',
        [order.id, tag.id],
      );

      // Build a genuine pre-sync fixture before altering its business columns.
      final syncTriggers = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'sync_%'",
          )
          .get();
      for (final trigger in syncTriggers) {
        await db.customStatement(
          'DROP TRIGGER "${trigger.read<String>('name')}"',
        );
      }
      final syncTables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND (name LIKE 'sync_%' OR name LIKE 'lan_%')",
          )
          .get();
      for (final table in syncTables) {
        await db.customStatement('DROP TABLE "${table.read<String>('name')}"');
      }
      await db.customStatement('PRAGMA foreign_keys=OFF');
      await db.customStatement('''
        CREATE TABLE tags_v14 (
          id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL,
          color_value INTEGER NOT NULL, is_active INTEGER NOT NULL,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
          deleted_at INTEGER, version INTEGER NOT NULL
        )
      ''');
      await db.customStatement('''
        INSERT INTO tags_v14
        SELECT id, name, color_value, is_active, created_at, updated_at,
          deleted_at, version FROM tags
      ''');
      await db.customStatement('DROP TABLE tags');
      await db.customStatement('ALTER TABLE tags_v14 RENAME TO tags');
      for (final column in ['origin', 'quick_action_date', 'quick_snapshot']) {
        await db.customStatement(
          'ALTER TABLE customer_follow_ups DROP COLUMN $column',
        );
      }
      // Recreate a genuine v14 schema before exercising the full upgrade.
      for (final table in [
        'knowledge_favorites',
        'dashboard_focus_histories',
        'dashboard_daily_focuses',
        'dashboard_focuses',
      ]) {
        await db.customStatement('DROP TABLE $table');
      }
      await db.customStatement(
        'ALTER TABLE workspace_notes DROP COLUMN linked_knowledge_article_id',
      );
      await db.customStatement('PRAGMA user_version=14');
      await db.close();

      db = AppDatabase(NativeDatabase(file));
      expect(db.schemaVersion, 20);
      expect(
        (await customersFor(db).watchCustomer(customer.id).first)?.name,
        'Preserved Jack',
      );
      expect(
        (await ordersFor(db).watchOrder(order.id).first)?.orderNumber,
        'SO-PRESERVED',
      );
      final customerTags = await customersFor(db)
          .watchCustomerTags(customer.id)
          .first;
      final orderTags = await ordersFor(db).watchOrderTags(order.id).first;
      expect(customerTags.single.id, tag.id);
      expect(orderTags.single.name, 'WPC');
      expect(orderTags.single.id, isNot(tag.id));
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    } finally {
      await db.close();
      await root.delete(recursive: true);
    }
  });
}

DriftCustomerRepository customersFor(AppDatabase db) =>
    DriftCustomerRepository(db);
DriftOrderRepository ordersFor(AppDatabase db) => DriftOrderRepository(db);
