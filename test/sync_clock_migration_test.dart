import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';

void main() {
  test('schema 19 upgrade preserves rows and frozen retries, captures new edits in milliseconds', () async {
    final root = await Directory.systemTemp.createTemp('fly-clock-migration-');
    final file = File('${root.path}/fly.db');
    var db = AppDatabase(NativeDatabase(file));
    try {
      await db.ensureBuiltInData();
      final customer = await DriftCustomerRepository(db)
          .createCustomer(name: 'Preserved customer');
      var queue = SyncOutboxRepository(db);
      await queue.bind('lan:retained');
      final frozen = (await queue.prepare()).firstWhere(
        (m) => m['entityType'] == 'customers',
      );
      await db.customStatement('PRAGMA user_version=19');
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      queue = SyncOutboxRepository(db);
      expect(
        (await queue.prepare()).firstWhere(
          (m) => m['entityType'] == 'customers',
        ),
        frozen,
      );
      await db.customStatement('UPDATE customers SET phone=? WHERE id=?', [
        'updated',
        customer.id,
      ]);
      final timestamp =
          (await db
                  .customSelect(
                    "SELECT created_at FROM sync_outbox WHERE entity_type='customers' ORDER BY ordinal DESC LIMIT 1",
                  )
                  .getSingle())
              .read<int>('created_at');
      expect(timestamp, greaterThan(1000000000000));
      expect(timestamp, closeTo(DateTime.now().millisecondsSinceEpoch, 3000));
      expect(
        (await db.select(db.customers).get()).single.name,
        'Preserved customer',
      );
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        20,
      );
    } finally {
      await db.close();
      await root.delete(recursive: true);
    }
  });
}
