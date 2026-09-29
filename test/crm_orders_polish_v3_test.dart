import 'package:drift/native.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/domain/customer.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/orders/domain/order.dart';
import 'package:fly/shared/data/tag_garbage_collector.dart';
import 'package:fly/shared/domain/priority.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftCustomerRepository customers;
  late DriftOrderRepository orders;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.ensureBuiltInData();
    customers = DriftCustomerRepository(database);
    orders = DriftOrderRepository(database);
  });

  tearDown(() => database.close());

  test(
    'startup repair removes ordinary orphan and protects category tag',
    () async {
      final orphan = await customers.findOrCreateTag('订单');
      final categories = await customers.watchCategories().first;
      final categoryTagId = categories.first.tagId!;

      expect(await TagCleanupService(database).cleanupOrphanTags(), 1);
      final tags = await customers.watchAllTags().first;
      expect(tags.any((tag) => tag.id == orphan.id), isFalse);
      expect(tags.any((tag) => tag.id == categoryTagId), isTrue);
    },
  );

  test('customer and order tag lifecycles are scoped separately', () async {
    final customer = await customers.createCustomer(name: 'Tag Customer');
    final order = await orders.createOrder(
      customerId: customer.id,
      orderNumber: 'SO-TAG-V3',
    );
    final tag = await customers.findOrCreateTag('重点');
    final orderTag = await orders.findOrCreateTag('重点');
    await customers.setCustomerTags(customer.id, [tag.id]);
    await orders.setOrderTags(order.id, [orderTag.id]);

    await customers.setCustomerTags(customer.id, const []);
    expect(
      (await customers.watchAllTags().first).any((item) => item.id == tag.id),
      isFalse,
    );
    expect(await orders.watchOrderTags(order.id).first, hasLength(1));

    await orders.setOrderTags(order.id, const []);
    expect(
      (await orders.watchAllTags().first).any((item) => item.id == orderTag.id),
      isFalse,
    );
  });

  test('manual referenced tag deletion is transactional', () async {
    final first = await customers.createCustomer(name: 'Customer A');
    final second = await customers.createCustomer(name: 'Customer B');
    final order = await orders.createOrder(
      customerId: first.id,
      orderNumber: 'SO-MANUAL-TAG',
    );
    final tag = await customers.findOrCreateTag('菲律宾');
    final orderTag = await orders.findOrCreateTag('菲律宾');
    await customers.setCustomerTags(first.id, [tag.id]);
    await customers.setCustomerTags(second.id, [tag.id]);
    await orders.setOrderTags(order.id, [orderTag.id]);

    final references = await customers.tagReferences(tag.id);
    expect(references.customerReferences, 2);
    expect(references.orderReferences, 0);

    await customers.deleteTagDefinition(tag.id);
    expect(await customers.watchCustomerTags(first.id).first, isEmpty);
    expect(await customers.watchCustomerTags(second.id).first, isEmpty);
    expect(await orders.watchOrderTags(order.id).first, hasLength(1));
    expect(
      (await customers.watchAllTags().first).any((item) => item.id == tag.id),
      isFalse,
    );
  });

  test(
    'two-month recurrence uses calendar clamp across year and leap year',
    () {
      expect(
        nextCustomerFollowUpDate(
          recurrence: FollowUpRecurrence.every2Months,
          now: DateTime(2026, 1, 1),
          scheduledDate: DateTime(2026, 1, 31),
        ),
        DateTime(2026, 3, 31),
      );
      expect(
        nextCustomerFollowUpDate(
          recurrence: FollowUpRecurrence.every2Months,
          now: DateTime(2026, 1, 1),
          scheduledDate: DateTime(2026, 12, 31),
        ),
        DateTime(2027, 2, 28),
      );
      expect(
        nextCustomerFollowUpDate(
          recurrence: FollowUpRecurrence.every2Months,
          now: DateTime(2027, 1, 1),
          scheduledDate: DateTime(2027, 12, 31),
        ),
        DateTime(2028, 2, 29),
      );
    },
  );

  test('order sidebar source returns at most eight tags by usage', () async {
    final customer = await customers.createCustomer(name: 'Popular Tags');
    final createdTags = <String>[];
    for (var index = 0; index < 12; index++) {
      final tag = await orders.findOrCreateTag('Order Tag $index');
      createdTags.add(tag.id);
      final order = await orders.createOrder(
        customerId: customer.id,
        orderNumber: 'SO-POPULAR-$index',
      );
      await orders.setOrderTags(order.id, [tag.id]);
    }
    final extraOrder = await orders.createOrder(
      customerId: customer.id,
      orderNumber: 'SO-POPULAR-EXTRA',
    );
    await orders.setOrderTags(extraOrder.id, [createdTags.last]);

    final popular = await orders.watchPopularTags().first;
    expect(popular, hasLength(8));
    expect(popular.first.id, createdTags.last);
  });

  test(
    'default order ranking is strict and same-rank is newest first',
    () async {
      final customer = await customers.createCustomer(name: 'Rank Customer');
      Future<void> createRanked(
        String number, {
        PriorityLevel priority = PriorityLevel.low,
        bool important = false,
        bool urgent = false,
      }) async {
        final order = await orders.createOrder(
          customerId: customer.id,
          orderNumber: number,
        );
        await orders.saveOrder(
          order.copyWith(
            priority: priority,
            importance: important,
            urgency: urgent,
          ),
        );
      }

      await createRanked('F');
      await createRanked('E', important: true);
      await createRanked('D', priority: PriorityLevel.medium);
      await createRanked('C-OLD', priority: PriorityLevel.high);
      await createRanked('C-NEW', priority: PriorityLevel.high);
      await createRanked('B', urgent: true);
      await createRanked('A', important: true, urgent: true);

      final result = await orders
          .watchOrders(const OrderQuery(projection: OrderProjection.all))
          .first;
      expect(result.map((order) => order.orderNumber), [
        'A',
        'B',
        'E',
        'C-NEW',
        'C-OLD',
        'D',
        'F',
      ]);
    },
  );
}
