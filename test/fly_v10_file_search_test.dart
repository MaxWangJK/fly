import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/files/data/file_browser_query.dart';
import 'package:fly/shared/search/global_search_service.dart';

void main() {
  test('order, payment and cost files resolve order and customer without duplicate rows', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await db.ensureBuiltInData();
      final crm = DriftCustomerRepository(db);
      final customer = await crm.createCustomer(name: 'Search customer');
      await crm.saveCustomer(customer.copyWith(companyName: 'Atlas Building'));
      final order = await DriftOrderRepository(db)
          .createOrder(customerId: customer.id, orderNumber: 'SO-ATTACH-01');
      final now = DateTime.now();
      await db
          .into(db.orderPayments)
          .insert(
            OrderPaymentsCompanion.insert(
              id: 'pay',
              orderId: order.id,
              amount: 100,
              paidAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.orderCostEntries)
          .insert(
            OrderCostEntriesCompanion.insert(
              id: 'cost',
              orderId: order.id,
              amountMinor: 20,
              occurredAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      for (final owner in {
        'order': order.id,
        'payment': 'pay',
        'cost': 'cost',
        'library': 'library',
      }.entries) {
        await db
            .into(db.attachments)
            .insert(
              AttachmentsCompanion.insert(
                id: 'file-${owner.key}',
                ownerType: owner.key,
                ownerId: owner.value,
                fileName: '${owner.key}-stored.pdf',
                originalName: '${owner.key}-receipt.pdf',
                relativePath: 'test/${owner.key}.pdf',
                fileSize: 10,
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      final search = GlobalSearchService(db);
      for (final term in [
        'SO-ATTACH-01',
        'Search customer',
        'Atlas Building',
      ]) {
        final files = (await search.search(term))
            .where((r) => r.type == SearchResultType.file)
            .toList();
        expect(
          files.map((r) => r.entityId),
          unorderedEquals(['file-order', 'file-payment', 'file-cost']),
        );
        expect(files.every((r) => r.subtitle.contains('SO-ATTACH-01')), true);
      }
      final query = FileBrowserQuery(db);
      expect(
        await query
            .watch(
              collection: FileCollection.recent,
              search: 'SO-ATTACH-01',
              crmVisible: false,
            )
            .first,
        isEmpty,
      );
      expect(
        (await search.search('order-stored'))
            .any((r) => r.entityId == 'file-order'),
        true,
      );
      await (db.update(db.orderPayments)..where((r) => r.id.equals('pay')))
          .write(OrderPaymentsCompanion(deletedAt: Value(now)));
      expect(
        (await search.search('SO-ATTACH-01'))
            .where((r) => r.type == SearchResultType.file)
            .map((r) => r.entityId),
        unorderedEquals(['file-order', 'file-cost']),
      );
      await (db.update(db.orders)..where((r) => r.id.equals(order.id))).write(
        OrdersCompanion(deletedAt: Value(now)),
      );
      expect(
        (await search.search('SO-ATTACH-01'))
            .where((r) => r.type == SearchResultType.file),
        isEmpty,
      );
      // Business deletion does not delete the canonical file or its metadata.
      expect(await db.select(db.attachments).get(), hasLength(4));
      expect(
        (await search.search('order-receipt'))
            .any((r) => r.entityId == 'file-order'),
        true,
      );
    } finally {
      await db.close();
    }
  });
}
