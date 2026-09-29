import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/core/storage/data_root_service.dart';
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

  test(
    'category and linked-tag filters share one AND matching semantics',
    () async {
      final categories = await customers.watchCategories().first;
      final a = categories.firstWhere((item) => item.name == 'A级');
      final b = categories.firstWhere((item) => item.name == 'B级');
      final c = categories.firstWhere((item) => item.name == 'C级');
      final philippines = await customers.findOrCreateTag('菲律宾');
      var mira = await customers.createCustomer(name: 'Mira');
      mira = mira.copyWith(categoryId: b.id);
      await customers.saveCustomer(mira);
      await customers.setCustomerTags(mira.id, [a.tagId!, philippines.id]);

      Future<bool> appears(CustomerQuery query) async =>
          (await customers.watchCustomers(query).first).any(
            (customer) => customer.id == mira.id,
          );

      expect(
        await appears(
          CustomerQuery(
            projection: CustomerProjection.category,
            categoryId: b.id,
            categoryTagId: b.tagId,
          ),
        ),
        isFalse,
      );
      expect(
        await appears(
          CustomerQuery(
            projection: CustomerProjection.category,
            categoryId: a.id,
            categoryTagId: a.tagId,
          ),
        ),
        isTrue,
      );
      expect(
        await appears(
          CustomerQuery(
            projection: CustomerProjection.all,
            tagIds: {a.tagId!, philippines.id},
          ),
        ),
        isTrue,
      );

      await customers.saveCustomer(mira.copyWith(categoryId: c.id));
      expect(
        await appears(
          CustomerQuery(
            projection: CustomerProjection.category,
            categoryId: b.id,
            categoryTagId: b.tagId,
          ),
        ),
        isFalse,
      );
      expect(
        await appears(
          CustomerQuery(
            projection: CustomerProjection.category,
            categoryId: c.id,
            categoryTagId: c.tagId,
          ),
        ),
        isTrue,
      );
    },
  );

  test(
    'overdue customers appear today and never recurrence stays cleared',
    () async {
      final today = DateTime(2026, 9, 3);
      var customer = await customers.createCustomer(name: 'Due Customer');
      customer = customer.copyWith(
        nextFollowUpDate: DateTime(2026, 9, 1),
        followUpRecurrence: FollowUpRecurrence.never,
      );
      await customers.saveCustomer(customer);
      expect(
        (await customers
                .watchCustomers(
                  CustomerQuery(
                    projection: CustomerProjection.today,
                    today: today,
                  ),
                )
                .first)
            .map((item) => item.id),
        contains(customer.id),
      );

      await customers.completeTodayFollowUp(customer.id, now: today);
      expect(
        (await customers.watchCustomer(customer.id).first)?.nextFollowUpDate,
        isNull,
      );
      expect(
        (await customers
                .watchCustomers(
                  CustomerQuery(
                    projection: CustomerProjection.today,
                    today: today.add(const Duration(days: 1)),
                  ),
                )
                .first)
            .map((item) => item.id),
        isNot(contains(customer.id)),
      );
    },
  );

  test(
    'latest non-empty follow-up next action survives an empty newer record',
    () async {
      final customer = await customers.createCustomer(name: 'Next Action');
      await customers.addFollowUp(
        customer.id,
        channel: 'WhatsApp',
        content: '客户收到样品',
        nextAction: '周五询问测试结果',
        followedUpAt: DateTime(2026, 9, 2),
      );
      await customers.addFollowUp(
        customer.id,
        channel: 'Email',
        content: '补发资料',
        followedUpAt: DateTime(2026, 9, 3),
      );
      final action = await customers.watchLatestNextAction(customer.id).first;
      expect(action?.nextAction, '周五询问测试结果');
    },
  );

  test(
    'disabled order tag keeps links but disappears from active choices',
    () async {
      final customer = await customers.createCustomer(name: 'Tag Customer');
      final order = await orders.createOrder(
        customerId: customer.id,
        orderNumber: 'SO-V4-TAG',
      );
      final tag = await orders.findOrCreateTag('展会订单');
      await orders.setOrderTags(order.id, [tag.id]);
      await orders.setTagActive(tag.id, active: false);

      expect(
        (await orders.watchOrderTags(order.id).first).map((item) => item.id),
        contains(tag.id),
      );
      expect(
        (await orders.watchAllTags().first).map((item) => item.id),
        isNot(contains(tag.id)),
      );
      final inactive = (await orders.watchAllTags(includeInactive: true).first)
          .firstWhere((item) => item.id == tag.id);
      expect(inactive.isActive, isFalse);
    },
  );

  test(
    'free payment type and dynamic costs never add different currencies',
    () async {
      final customer = await customers.createCustomer(name: 'Finance');
      final created = await orders.createOrder(
        customerId: customer.id,
        orderNumber: 'SO-V4-FINANCE',
      );
      final order = created.copyWith(
        currency: 'USD',
        baseProfitCurrency: 'USD',
        exchangeRateMicros: 1000000,
        salesAmount: 2000000,
      );
      await orders.saveOrder(order);
      await orders.addPayment(
        order.id,
        amount: 500000,
        currency: 'USD',
        paymentType: '第三笔款',
        paidAt: DateTime(2026, 9, 3),
      );
      await orders.addPayment(
        order.id,
        amount: 700000,
        currency: 'CNY',
        paymentType: '样品费',
        paidAt: DateTime(2026, 9, 3),
      );
      await orders.addCostEntry(
        order.id,
        amountMinor: 120000,
        currency: 'USD',
        costType: '拖车费',
        occurredAt: DateTime(2026, 9, 3),
      );
      await orders.addCostEntry(
        order.id,
        amountMinor: 880000,
        currency: 'CNY',
        costType: '木架费',
        occurredAt: DateTime(2026, 9, 3),
      );
      final payments = await orders.watchPayments(order.id).first;
      final costs = await orders.watchCostEntries(order.id).first;
      final usd = OrderFinancialSummary(
        order: order,
        items: const [],
        payments: payments,
        costEntries: costs,
        accountingCurrency: 'USD',
      );
      expect(
        payments.firstWhere((item) => item.currency == 'USD').paymentType,
        '第三笔款',
      );
      expect(usd.receivedAmount, 1200000);
      expect(usd.dynamicCost, 1000000);
      expect(usd.outstandingAmount, 800000);
      expect(usd.receivedByCurrency, {'USD': 500000, 'CNY': 700000});
    },
  );

  test('schema v5 migrates fixed order costs into dynamic entries', () async {
    final previous = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final directory = await Directory.systemTemp.createTemp('fly-v4-v5-');
    final file = File('${directory.path}${Platform.pathSeparator}fly.db');
    AppDatabase? legacy;
    AppDatabase? migrated;
    try {
      legacy = AppDatabase(NativeDatabase(file));
      await legacy.ensureBuiltInData();
      final legacyCustomers = DriftCustomerRepository(legacy);
      final legacyOrders = DriftOrderRepository(legacy);
      final customer = await legacyCustomers.createCustomer(
        name: 'Legacy Cost',
      );
      final created = await legacyOrders.createOrder(
        customerId: customer.id,
        orderNumber: 'SO-V4-MIGRATION',
      );
      await legacyOrders.saveOrder(
        created.copyWith(
          baseProfitCurrency: 'USD',
          inlandCost: 50000,
          portCharges: 30000,
          otherCost: 20000,
        ),
      );
      await legacy.customStatement('DROP TABLE order_cost_entries');
      await legacy.customStatement('DROP TABLE app_settings');
      await legacy.customStatement('PRAGMA user_version = 4');
      await legacy.close();
      legacy = null;

      migrated = AppDatabase(NativeDatabase(file));
      final entries = await DriftOrderRepository(migrated)
          .watchCostEntries(created.id)
          .first;
      expect(entries.map((entry) => entry.costType).toSet(), {
        '内陆费',
        '港杂费',
        '其他费用',
      });
      expect(entries.fold(0, (sum, entry) => sum + entry.amountMinor), 100000);
    } finally {
      await legacy?.close();
      await migrated?.close();
      if (await directory.exists()) await directory.delete(recursive: true);
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous;
    }
  });

  test(
    'data root settings migrate legacy database and preserve old copy',
    () async {
      final temp = await Directory.systemTemp.createTemp('fly-data-root-');
      final support = Directory('${temp.path}${Platform.pathSeparator}support');
      final documents = Directory('${temp.path}${Platform.pathSeparator}docs');
      await support.create(recursive: true);
      await documents.create(recursive: true);
      final legacy = File('${support.path}${Platform.pathSeparator}fly.sqlite');
      await legacy.writeAsBytes([1, 2, 3, 4]);
      final service = FlyDataRootService(
        supportDirectory: support,
        documentsDirectory: documents,
      );
      final root = await service.recommendedDataRoot();
      await service.prepareFirstRun(
        root,
        useExistingDatabase: false,
        migrateLegacyDatabase: true,
      );
      expect(await legacy.exists(), isTrue);
      expect(await File('$root${Platform.pathSeparator}fly.db').readAsBytes(), [
        1,
        2,
        3,
        4,
      ]);
      expect(await service.loadDataRoot(), root);
      for (final folder in const [
        'attachments',
        'orders',
        'customers',
        'backups',
        'logs',
      ]) {
        expect(
          await Directory('$root${Platform.pathSeparator}$folder').exists(),
          isTrue,
        );
      }
      await temp.delete(recursive: true);
    },
  );
}
