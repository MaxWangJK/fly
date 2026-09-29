import 'package:drift/native.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/domain/customer.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/shared/dev/first_run_demo_seeder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftCustomerRepository customers;
  late DriftOrderRepository orders;
  late DriftTaskRepository tasks;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.ensureBuiltInData();
    customers = DriftCustomerRepository(database);
    orders = DriftOrderRepository(database);
    tasks = DriftTaskRepository(database);
  });

  tearDown(() => database.close());

  test('follow-up edit and soft delete restore previous next action', () async {
    final customer = await customers.createCustomer(name: 'Follow-up V5');
    final earlier = await customers.addFollowUp(
      customer.id,
      channel: 'Email',
      content: '客户收到样品',
      nextAction: '发测试说明',
      followedUpAt: DateTime(2026, 9, 1),
    );
    final latest = await customers.addFollowUp(
      customer.id,
      channel: 'WhatsApp',
      content: '',
      nextAction: '周五联系',
      followedUpAt: DateTime(2026, 9, 3),
    );

    await customers.saveFollowUp(
      latest.copyWith(content: '客户开始测试', nextAction: '下周一联系'),
    );
    expect(
      (await customers.watchLatestNextAction(customer.id).first)?.nextAction,
      '下周一联系',
    );
    await customers.softDeleteFollowUp(latest.id);

    expect(
      (await customers.watchLatestNextAction(customer.id).first)?.id,
      earlier.id,
    );
    expect(
      (await customers.watchFollowUps(customer.id).first).map(
        (item) => item.id,
      ),
      isNot(contains(latest.id)),
    );
    expect(
      (await customers.watchCustomer(customer.id).first)?.nextAction,
      '发测试说明',
    );
  });

  test(
    'removing a level tag clears category and never hides all customers',
    () async {
      final categories = await customers.watchCategories().first;
      final b = categories.firstWhere((item) => item.name == 'B级');
      final a = categories.firstWhere((item) => item.name == 'A级');
      var customer = await customers.createCustomer(name: 'Mira');
      customer = customer.copyWith(categoryId: b.id);
      await customers.saveCustomer(customer);
      await customers.setCustomerTags(customer.id, [b.tagId!, a.tagId!]);

      await customers.setCustomerTags(customer.id, [a.tagId!]);
      expect(
        (await customers.watchCustomer(customer.id).first)?.categoryId,
        isNull,
      );
      expect(
        (await customers.watchCustomerTags(customer.id).first).map(
          (tag) => tag.id,
        ),
        [a.tagId],
      );

      await customers.setCustomerTags(customer.id, const []);
      expect(await customers.watchCustomerTags(customer.id).first, isEmpty);
      expect(
        (await customers
                .watchCustomers(
                  const CustomerQuery(projection: CustomerProjection.all),
                )
                .first)
            .map((item) => item.id),
        contains(customer.id),
      );
      expect(
        await customers
            .watchCustomers(
              CustomerQuery(
                projection: CustomerProjection.category,
                categoryId: b.id,
                categoryTagId: b.tagId,
              ),
            )
            .first,
        isEmpty,
      );
    },
  );

  test(
    'sales currency changes without rewriting payment and cost currency',
    () async {
      final customer = await customers.createCustomer(
        name: 'Currency Customer',
      );
      final created = await orders.createOrder(
        customerId: customer.id,
        orderNumber: 'SO-V5-CURRENCY',
      );
      await orders.saveOrder(created.copyWith(salesAmount: 1000000));
      await orders.addPayment(
        created.id,
        amount: 300000,
        currency: 'USD',
        paymentType: '定金',
        paidAt: DateTime(2026, 9, 3),
      );
      await orders.addCostEntry(
        created.id,
        amountMinor: 200000,
        currency: 'USD',
        costType: '工厂成本',
        occurredAt: DateTime(2026, 9, 3),
      );

      await orders.setFinancialCurrency(created.id, 'RMB');
      final order = (await orders.watchOrder(created.id).first)!;
      final payments = await orders.watchPayments(created.id).first;
      final costs = await orders.watchCostEntries(created.id).first;
      expect(order.currency, 'CNY');
      expect(order.baseProfitCurrency, 'CNY');
      expect(order.salesAmount, 1000000);
      expect(payments.single.currency, 'USD');
      expect(payments.single.amount, 300000);
      expect(costs.single.currency, 'USD');
      expect(costs.single.amountMinor, 200000);
    },
  );

  test('fresh seed is dynamic, complete, and runs once', () async {
    final today = DateTime(2026, 10, 10);
    final seeder = FirstRunDemoSeeder(
      database: database,
      tasks: tasks,
      customers: customers,
      orders: orders,
    );
    expect(await seeder.seedIfEligible(now: today), DemoSeedResult.seeded);

    final customerRows = await database.select(database.customers).get();
    final orderRows = await database.select(database.orders).get();
    final taskRows = await database.select(database.tasks).get();
    expect(customerRows.length, inInclusiveRange(8, 12));
    expect(orderRows.length, inInclusiveRange(5, 8));
    expect(taskRows.length, inInclusiveRange(8, 12));
    expect(
      customerRows.where((row) => row.nextFollowUpDate == today).length,
      greaterThanOrEqualTo(2),
    );
    expect(
      taskRows.where((row) => row.dueDate == today).length,
      greaterThanOrEqualTo(3),
    );
    for (final important in [false, true]) {
      for (final urgent in [false, true]) {
        expect(
          taskRows.any(
            (row) => row.importance == important && row.urgency == urgent,
          ),
          isTrue,
        );
      }
    }
    expect(
      await seeder.seedIfEligible(now: DateTime(2027, 1, 1)),
      DemoSeedResult.alreadyInitialized,
    );
    expect(
      (await database.select(database.customers).get()).length,
      customerRows.length,
    );
  });

  test(
    'existing user data prevents every demo entity from being seeded',
    () async {
      await customers.createCustomer(name: 'Real Customer');
      final result = await FirstRunDemoSeeder(
        database: database,
        tasks: tasks,
        customers: customers,
        orders: orders,
      ).seedIfEligible(now: DateTime(2026, 9, 3));

      expect(result, DemoSeedResult.existingData);
      expect((await database.select(database.customers).get()).length, 1);
      expect(await database.select(database.orders).get(), isEmpty);
      expect(await database.select(database.tasks).get(), isEmpty);
    },
  );
}
