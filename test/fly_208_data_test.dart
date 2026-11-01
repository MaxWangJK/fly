import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/account/data/local_profile.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/domain/customer_lifecycle.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('new customer profile and custom source commit together and retain category links', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await db.ensureBuiltInData();
      final repo = DriftCustomerRepository(db);
      final name = 'Profile ${const Uuid().v4()}';
      final customer = await repo.createCustomer(
        name: name,
        country: ' Portugal ',
        categoryId: 'category-a',
        statusId: 'customer-intent',
        source: 'Partner event',
      );
      expect(customer.country, 'Portugal');
      expect(customer.categoryId, 'category-a');
      expect(customer.statusId, 'customer-intent');
      expect(
        (await repo.watchCustomerTags(customer.id).first).any(
          (t) => t.name == 'A级',
        ),
        isTrue,
      );
      final source = (await repo.watchSources().first).firstWhere(
        (s) => s.id == customer.sourceId,
      );
      expect(source.name, 'Partner event');
      final changes = await SyncOutboxRepository(db).prepare();
      final mutation = changes.singleWhere(
        (r) =>
            r['entityType'] == 'customers' && r['payload']['id'] == customer.id,
      );
      expect(mutation['payload']['country'], 'Portugal');
      expect(mutation['payload']['source_id'], source.id);
      await expectLater(
        repo.createCustomer(name: name, source: 'Should not be created'),
        throwsA(isA<Exception>()),
      );
      expect(
        (await repo.watchSources().first).any(
          (s) => s.name == 'Should not be created',
        ),
        isFalse,
      );
    } finally {
      await db.close();
    }
  });

  test('only five visible stages while legacy customer status remains recoverable in storage', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await db.ensureBuiltInData();
      final repo = DriftCustomerRepository(db);
      final old = await repo.createStatus('旧报价状态');
      final customer = await repo.createCustomer(
        name: 'Legacy ${const Uuid().v4()}',
      );
      await db.customStatement('UPDATE customers SET status_id=? WHERE id=?', [
        old.id,
        customer.id,
      ]);
      await db.customStatement(
        "UPDATE customer_statuses SET is_active=0, sort_order=99, deleted_at=1 WHERE id='customer-won'",
      );
      expect(
        (await repo.watchStatuses().first).map((s) => s.id).toList(),
        CustomerLifecycle.stages.map((s) => s.$1).toList(),
      );
      expect(
        (await repo.watchCustomer(customer.id).first)!.statusId,
        'customer-developing',
      );
      final stored = await (db.select(
        db.customers,
      )..where((r) => r.id.equals(customer.id))).getSingle();
      expect(stored.statusId, old.id);
    } finally {
      await db.close();
    }
  });

  test(
    'name and avatar persist locally and never enter the cloud mutation queue',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await db.ensureBuiltInData();
        final queue = SyncOutboxRepository(db);
        final profile = LocalProfileRepository(db);
        await profile.save('  Sam  ', Uint8List.fromList([1, 2, 3]));
        final saved = await profile.watch().first;
        expect(saved.name, 'Sam');
        expect(saved.avatar, [1, 2, 3]);
        final mutations = await queue.prepare();
        expect(
          mutations
              .where((r) => r['entityType'] == 'app_settings')
              .any((r) => '${r['payload']}'.contains('profile.')),
          isFalse,
        );
        await profile.save('Sam updated', null);
        expect((await profile.watch().first).avatar, isNull);
      } finally {
        await db.close();
      }
    },
  );
}
