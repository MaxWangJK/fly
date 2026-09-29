import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/domain/customer_name.dart';

void main() {
  test('V10 category create and normalized names are transactional', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await db.ensureBuiltInData();
      final repo = DriftCustomerRepository(db);
      final category = (await repo.watchCategories().first).firstWhere(
        (c) => c.name == 'D级',
      );
      final jack = await repo.createCustomer(
        name: 'Jack',
        categoryId: category.id,
      );
      expect(jack.categoryId, category.id);
      expect(
        (await repo.watchCustomerTags(jack.id).first).map((t) => t.name),
        contains('D级'),
      );
      await expectLater(
        repo.createCustomer(name: ' jack '),
        throwsA(isA<DuplicateCustomerName>()),
      );
      await repo.createCustomer(name: 'Jack Purchasing');
      await expectLater(
        repo.createCustomer(name: ' JACK   Purchasing '),
        throwsA(isA<DuplicateCustomerName>()),
      );
      final other = await repo.createCustomer(name: 'Jack (2)');
      expect(other.categoryId, isNull);
      await expectLater(
        repo.saveCustomer(other.copyWith(name: 'JACK')),
        throwsA(isA<DuplicateCustomerName>()),
      );
      expect((await repo.watchCustomer(other.id).first)!.name, 'Jack (2)');
      expect((await db.select(db.customers).get()).length, 3);
    } finally {
      await db.close();
    }
  });

  test(
    'V10 free-text sources preserve legacy relationships and can clear',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await db.ensureBuiltInData();
        final repo = DriftCustomerRepository(db);
        final customer = await repo.createCustomer(name: 'Source example');
        final originalSources = await repo.watchSources().first;
        final facebook = originalSources.firstWhere(
          (s) => s.name == 'Facebook',
        );
        await repo.setCustomerSourceText(customer.id, 'facebook');
        expect(
          (await repo.watchCustomer(customer.id).first)!.sourceId,
          facebook.id,
        );
        await repo.setCustomerSourceText(customer.id, '客户转介绍 / 深圳展会');
        final updated = (await repo.watchCustomer(customer.id).first)!;
        expect(
          (await repo.watchSources().first)
              .firstWhere((s) => s.id == updated.sourceId)
              .name,
          '客户转介绍 / 深圳展会',
        );
        await repo.setCustomerSourceText(customer.id, ' ');
        expect((await repo.watchCustomer(customer.id).first)!.sourceId, isNull);
        expect(
          (await repo.watchSources().first).any((s) => s.id == facebook.id),
          true,
        );
      } finally {
        await db.close();
      }
    },
  );
}
