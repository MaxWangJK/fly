import 'package:drift/native.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/domain/customer.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/orders/domain/order.dart';
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

  test('tag_gc_test removes ordinary zero-reference tags only', () async {
    final customer = await customers.createCustomer(name: 'Jack');
    final order = await orders.createOrder(
      customerId: customer.id,
      orderNumber: 'SO-TAG-GC',
    );

    final ordinary = await customers.findOrCreateTag('重点');
    await customers.setCustomerTags(customer.id, [ordinary.id]);
    await customers.setCustomerTags(customer.id, const []);
    expect(
      (await database.select(database.tags).get()).where(
        (tag) => tag.id == ordinary.id,
      ),
      isEmpty,
    );

    final shared = await customers.findOrCreateTag('菲律宾共享');
    final orderTag = await orders.findOrCreateTag('菲律宾共享');
    expect(orderTag.id, isNot(shared.id));
    await customers.setCustomerTags(customer.id, [shared.id]);
    await orders.setOrderTags(order.id, [orderTag.id]);
    await customers.setCustomerTags(customer.id, const []);
    expect(
      (await database.select(database.tags).get()).where(
        (tag) => tag.id == shared.id,
      ),
      isEmpty,
    );
    expect(await orders.watchOrderTags(order.id).first, hasLength(1));
    await orders.setOrderTags(order.id, const []);
    expect(
      (await database.select(database.tags).get()).where(
        (tag) => tag.id == orderTag.id,
      ),
      isEmpty,
    );

    final category = (await customers.watchCategories().first).first;
    await customers.setCustomerTags(customer.id, [category.tagId!]);
    await customers.setCustomerTags(customer.id, const []);
    expect(
      (await database.select(database.tags).get()).where(
        (tag) => tag.id == category.tagId,
      ),
      isNotEmpty,
    );

    final deleteCandidate = await customers.findOrCreateTag('删除客户后清理');
    await customers.setCustomerTags(customer.id, [deleteCandidate.id]);
    await customers.softDeleteCustomer(customer.id);
    expect(
      (await database.select(database.tags).get()).where(
        (tag) => tag.id == deleteCandidate.id,
      ),
      isEmpty,
    );
  });

  test(
    'custom_field_test shares definitions and confirms value impact',
    () async {
      final a = await customers.createCustomer(name: 'A');
      final b = await customers.createCustomer(name: 'B');
      final definition = await customers.createCustomFieldDefinition(
        '年采购量',
        type: CustomerCustomFieldType.text,
      );
      await customers.setCustomFieldValue(
        a.id,
        definition.id,
        '100 containers/year',
      );
      await customers.setCustomFieldValue(
        b.id,
        definition.id,
        '50 containers/year',
      );

      expect(
        (await customers.watchCustomFieldDefinitions().first).single.id,
        definition.id,
      );
      expect(
        (await customers.watchCustomFieldValues(a.id).first).single.value,
        '100 containers/year',
      );
      expect(
        (await customers.watchCustomFieldValues(b.id).first).single.value,
        '50 containers/year',
      );
      expect(await customers.customFieldValueCount(definition.id), 2);

      await customers.deleteCustomFieldDefinition(definition.id);
      expect(await customers.watchCustomFieldDefinitions().first, isEmpty);
      expect(await customers.watchCustomFieldValues(a.id).first, isEmpty);
    },
  );

  test('order_creation_rule_test requires an active customer', () async {
    expect(
      () => orders.createOrder(
        customerId: 'missing-customer',
        orderNumber: 'SO-INVALID',
      ),
      throwsArgumentError,
    );
    final customer = await customers.createCustomer(name: 'Required Customer');
    final order = await orders.createOrder(
      customerId: customer.id,
      orderNumber: 'SO-VALID',
    );
    expect(order.customerId, customer.id);
  });

  test(
    'order_item_validation_test requires factory product and quantity',
    () async {
      final customer = await customers.createCustomer(name: 'Items Customer');
      final order = await orders.createOrder(
        customerId: customer.id,
        orderNumber: 'SO-ITEMS',
      );
      expect(
        () => orders.addProductionItem(
          order.id,
          factoryName: '',
          productName: 'WPC',
        ),
        throwsArgumentError,
      );
      expect(
        () => orders.addProductionItem(
          order.id,
          factoryName: 'Factory',
          productName: '',
        ),
        throwsArgumentError,
      );
      expect(
        () => orders.addProductionItem(
          order.id,
          factoryName: 'Factory',
          productName: 'WPC',
          quantityMilli: 0,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'financial_summary_test requires exchange rates for RMB profit',
    () async {
      final customer = await customers.createCustomer(name: 'Finance Customer');
      final order = await orders.createOrder(
        customerId: customer.id,
        orderNumber: 'SO-FX',
      );
      final financialOrder = order.copyWith(
        currency: 'USD',
        baseProfitCurrency: 'USD',
        exchangeRateMicros: 0,
        salesAmount: 1000000,
        inlandCost: 600000,
        portCharges: 200000,
        otherCost: 200000,
        taxRefund: 500000,
      );
      await orders.saveOrder(financialOrder);
      await orders.addProductionItem(
        order.id,
        factoryName: 'Factory',
        productName: 'Product',
        factoryCost: 400000,
      );
      await orders.addPayment(
        order.id,
        amount: 300000,
        currency: 'USD',
        paymentType: '定金',
        paidAt: DateTime.now(),
      );
      await orders.addPayment(
        order.id,
        amount: 100000,
        currency: 'USD',
        paymentType: '尾款',
        paidAt: DateTime.now(),
      );
      final items = await orders.watchItems(order.id).first;
      final payments = await orders.watchPayments(order.id).first;
      final withoutRate = OrderFinancialSummary(
        order: financialOrder,
        items: items,
        payments: payments,
      );
      expect(withoutRate.salesInProfitCurrency, 1000000);
      expect(withoutRate.profit, isNull);
      expect(withoutRate.receivedAmount, 400000);

      final withRate = OrderFinancialSummary(
        order: financialOrder.copyWith(exchangeRateMicros: 7000000),
        items: items,
        payments: payments,
      );
      expect(withRate.salesInProfitCurrency, 1000000);
      expect(withRate.profit, 100000);
      expect(withRate.profitMargin, closeTo(1 / 70, 0.0001));
    },
  );

  test(
    'order_notes_test is newest-first searchable editable and soft deleted',
    () async {
      final customer = await customers.createCustomer(name: 'Notes Customer');
      final order = await orders.createOrder(
        customerId: customer.id,
        orderNumber: 'SO-NOTES',
      );
      final first = await orders.addNote(order.id, content: '外箱不能有中文');
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final latest = await orders.addNote(order.id, content: '周五确认包装');
      expect((await orders.watchLatestNote(order.id).first)?.id, latest.id);
      expect(
        (await orders.watchNotes(order.id, search: '外箱').first).single.id,
        first.id,
      );
      await orders.saveNote(latest.copyWith(content: '周六确认包装'));
      expect((await orders.watchLatestNote(order.id).first)?.content, '周六确认包装');
      await orders.softDeleteNote(first.id);
      expect((await orders.watchNotes(order.id).first).length, 1);
    },
  );
}
