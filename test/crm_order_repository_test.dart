import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/domain/customer.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/orders/domain/order.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
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
    'schema v4 keeps Task data and seeds dynamic CRM configuration',
    () async {
      final taskRepository = DriftTaskRepository(database);
      final task = await taskRepository.createTask(title: 'Existing task');

      final categories = await customers.watchCategories().first;
      final statuses = await customers.watchStatuses().first;
      final sources = await customers.watchSources().first;

      expect(categories.map((value) => value.name), ['A级', 'B级', 'C级', 'D级']);
      expect(statuses.map((value) => value.name), [
        '新客户',
        '开发中',
        '意向客户',
        '成交客户',
        '复购客户',
      ]);
      expect(sources.length, 12);
      expect(
        (await taskRepository.watchTask(task.id).first)?.title,
        'Existing task',
      );
    },
  );

  test(
    'category rename synchronizes its tag and configuration stays dynamic',
    () async {
      final category = await customers.createCategory('战略客户');
      await customers.renameCategory(category.id, '优质客户');
      final renamed = (await customers.watchCategories().first).singleWhere(
        (value) => value.id == category.id,
      );
      final tags = await customers.watchAllTags().first;

      expect(renamed.name, '优质客户');
      expect(
        tags.singleWhere((value) => value.id == renamed.tagId).name,
        '优质客户',
      );

      final status = await customers.createStatus('沉睡客户');
      await customers.setStatusActive(status.id, active: false);
      expect(
        (await customers.watchStatuses().first).where(
          (value) => value.id == status.id,
        ),
        isEmpty,
      );
    },
  );

  test('customer create edit duplicate warning search AND tags sort and soft delete', () async {
    final jack = await customers.createCustomer(name: 'Jack');
    await customers.saveCustomer(
      jack.copyWith(
        companyName: 'Jack Trading',
        country: 'Philippines',
        email: ' JACK@EXAMPLE.COM ',
        whatsapp: '+63 900 123 4567',
        priority: PriorityLevel.high,
      ),
    );
    final ahmed = await customers.createCustomer(name: 'Ahmed');
    await customers.saveCustomer(ahmed.copyWith(priority: PriorityLevel.low));

    final duplicates = await customers.findPotentialDuplicates(
      email: 'jack@example.com',
      whatsapp: '639001234567',
      excludingCustomerId: ahmed.id,
    );
    expect(duplicates.single.id, jack.id);

    final a = await customers.findOrCreateTag('A级');
    final market = await customers.findOrCreateTag('菲律宾');
    final product = await customers.findOrCreateTag('WPC');
    await customers.setCustomerTags(jack.id, [a.id, market.id, product.id]);
    await customers.setCustomerTags(ahmed.id, [a.id, product.id]);

    final filtered = await customers
        .watchCustomers(
          CustomerQuery(
            projection: CustomerProjection.all,
            search: 'trading',
            tagIds: {market.id, product.id},
            sort: CustomerSort.priority,
          ),
        )
        .first;
    expect(filtered.single.id, jack.id);

    final sorted = await customers
        .watchCustomers(
          const CustomerQuery(
            projection: CustomerProjection.all,
            sort: CustomerSort.priority,
          ),
        )
        .first;
    expect(sorted.first.id, jack.id);

    await customers.softDeleteCustomer(jack.id);
    expect(await customers.watchCustomer(jack.id).first, isNull);
    expect(
      (await customers
              .watchCustomers(
                const CustomerQuery(projection: CustomerProjection.deleted),
              )
              .first)
          .single
          .id,
      jack.id,
    );
  });

  test('three-day and weekly completion advance schedule without completing customer', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final everyThreeDays = await customers.createCustomer(name: 'Every 3 days');
    await customers.saveCustomer(
      everyThreeDays.copyWith(
        followUpRecurrence: FollowUpRecurrence.every3Days,
        nextFollowUpDate: today,
      ),
    );
    await customers.completeTodayFollowUp(everyThreeDays.id, now: now);
    final savedDaily = await customers.watchCustomer(everyThreeDays.id).first;
    expect(
      savedDaily?.lastFollowUpAt,
      DateTime(now.year, now.month, now.day, now.hour, now.minute, now.second),
    );
    expect(savedDaily?.nextFollowUpDate, today.add(const Duration(days: 3)));

    final weekly = await customers.createCustomer(name: 'Weekly');
    await customers.saveCustomer(
      weekly.copyWith(
        followUpRecurrence: FollowUpRecurrence.weekly,
        nextFollowUpDate: today,
      ),
    );
    await customers.completeTodayFollowUp(weekly.id, now: now);
    expect(
      (await customers.watchCustomer(weekly.id).first)?.nextFollowUpDate,
      today.add(const Duration(days: 7)),
    );
    expect(
      (await customers.watchFollowUps(everyThreeDays.id).first).single.content,
      '完成今日跟进',
    );
  });

  test('recurrence uses scheduled date and clamps calendar month ends', () {
    final now = DateTime(2026, 9, 2, 16, 30);
    expect(
      nextCustomerFollowUpDate(
        recurrence: FollowUpRecurrence.every3Days,
        now: now,
      ),
      DateTime(2026, 9, 5),
    );
    expect(
      nextCustomerFollowUpDate(
        recurrence: FollowUpRecurrence.every3Days,
        now: now,
        scheduledDate: DateTime(2026, 9, 10),
      ),
      DateTime(2026, 9, 13),
    );
    expect(
      nextCustomerFollowUpDate(
        recurrence: FollowUpRecurrence.weekly,
        now: now,
        scheduledDate: DateTime(2026, 9, 10),
      ),
      DateTime(2026, 9, 17),
    );
    expect(
      nextCustomerFollowUpDate(
        recurrence: FollowUpRecurrence.biweekly,
        now: now,
        scheduledDate: DateTime(2026, 9, 10),
      ),
      DateTime(2026, 9, 24),
    );
    expect(
      nextCustomerFollowUpDate(
        recurrence: FollowUpRecurrence.monthly,
        now: now,
        scheduledDate: DateTime(2025, 1, 31),
      ),
      DateTime(2025, 2, 28),
    );
    expect(
      nextCustomerFollowUpDate(
        recurrence: FollowUpRecurrence.monthly,
        now: now,
        scheduledDate: DateTime(2024, 1, 31),
      ),
      DateTime(2024, 2, 29),
    );
  });

  test(
    'customer notes are newest-first searchable editable and soft deleted',
    () async {
      final customer = await customers.createCustomer(name: 'Notes');
      final a = await customers.addNote(customer.id, content: 'Note A');
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await customers.addNote(customer.id, content: '报价 Note B');
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final c = await customers.addNote(customer.id, content: 'Note C');

      final notes = await customers.watchNotes(customer.id).first;
      expect(notes.map((note) => note.content), [
        'Note C',
        '报价 Note B',
        'Note A',
      ]);
      expect((await customers.watchLatestNote(customer.id).first)?.id, c.id);
      expect(
        (await customers.watchNotes(customer.id, search: '报价').first)
            .single
            .content,
        '报价 Note B',
      );

      await customers.saveNote(c.copyWith(content: 'Note C edited'));
      expect(
        (await customers.watchLatestNote(customer.id).first)?.content,
        'Note C edited',
      );
      await customers.softDeleteNote(a.id);
      expect((await customers.watchNotes(customer.id).first).length, 2);
    },
  );

  test(
    'follow-up history next action and multiple contacts are durable',
    () async {
      final customer = await customers.createCustomer(name: 'Jack');
      await customers.addContact(
        customer.id,
        name: 'Jack Lee',
        role: 'Owner',
        email: 'jack@example.com',
        isPrimary: true,
      );
      await customers.addContact(
        customer.id,
        name: 'Amy',
        role: 'Purchasing',
        whatsapp: '+63 900 111 2222',
      );
      await customers.addFollowUp(
        customer.id,
        channel: 'WhatsApp',
        content: '客户确认收到报价',
        nextAction: '周五再次联系',
        nextFollowUpDate: DateTime.now().add(const Duration(days: 3)),
      );

      expect((await customers.watchContacts(customer.id).first).length, 2);
      final followUp =
          (await customers.watchFollowUps(customer.id).first).single;
      expect(followUp.channel, 'WhatsApp');
      expect(followUp.nextAction, '周五再次联系');
      expect(
        (await customers.watchCustomer(customer.id).first)?.nextAction,
        '周五再次联系',
      );
    },
  );

  test(
    'order projections link customer status flags tags and soft deletion',
    () async {
      final customer = await customers.createCustomer(name: 'Jack');
      final order = await orders.createOrder(
        customerId: customer.id,
        orderNumber: 'SO-2026-001',
      );
      await orders.saveOrder(
        order.copyWith(
          statusId: 'order-production',
          importance: true,
          urgency: true,
          priority: PriorityLevel.high,
        ),
      );
      final urgent = await orders.findOrCreateTag('急单');
      await orders.setOrderTags(order.id, [urgent.id]);

      final filtered = await orders
          .watchOrders(
            OrderQuery(
              projection: OrderProjection.tag,
              tagId: urgent.id,
              customerId: customer.id,
            ),
          )
          .first;
      expect(filtered.single.id, order.id);
      expect(filtered.single.importance, isTrue);

      await orders.softDeleteOrder(order.id);
      expect(await orders.watchOrder(order.id).first, isNull);
      expect(
        (await orders
                .watchOrders(
                  const OrderQuery(projection: OrderProjection.deleted),
                )
                .first)
            .single
            .id,
        order.id,
      );
    },
  );

  test('production items reuse factory and product entities', () async {
    final customer = await customers.createCustomer(name: 'Factory Customer');
    final order = await orders.createOrder(
      customerId: customer.id,
      orderNumber: 'SO-2026-002',
    );
    await orders.addProductionItem(
      order.id,
      factoryName: '新材料工厂',
      productName: 'WPC 格栅',
      quantityMilli: 1000,
      factoryCost: 800000,
    );
    await orders.addProductionItem(
      order.id,
      factoryName: 'A墙板工厂',
      productName: 'UV 板',
      quantityMilli: 1000,
      factoryCost: 600000,
    );

    final items = await orders.watchItems(order.id).first;
    final summary = OrderFinancialSummary(
      order: order,
      items: items,
      payments: const [],
    );
    expect(items.length, 2);
    expect((await orders.watchFactories().first).length, 2);
    expect((await orders.watchProducts().first).length, 2);
    expect(summary.factoryCost, 1400000);
  });

  test(
    'profit payment outstanding full payment and file metadata are computed',
    () async {
      final customer = await customers.createCustomer(name: 'Finance Customer');
      final order = await orders.createOrder(
        customerId: customer.id,
        orderNumber: 'SO-2026-003',
      );
      final financialOrder = order.copyWith(
        baseProfitCurrency: 'USD',
        exchangeRateMicros: 1000000,
        salesAmount: 2000000,
        inlandCost: 50000,
        portCharges: 30000,
        otherCost: 20000,
        taxRefund: 150000,
      );
      await orders.saveOrder(financialOrder);
      await orders.addProductionItem(
        order.id,
        factoryName: 'Factory',
        productName: 'Product',
        factoryCost: 1400000,
      );
      for (final amount in [500000, 1000000, 500000]) {
        await orders.addPayment(
          order.id,
          amount: amount,
          currency: 'USD',
          paymentType: amount == 500000 ? '定金' : '进度款',
          paidAt: DateTime.now(),
        );
      }
      final items = await orders.watchItems(order.id).first;
      final payments = await orders.watchPayments(order.id).first;
      final summary = OrderFinancialSummary(
        order: financialOrder,
        items: items,
        payments: payments,
      );
      expect(summary.profit, 650000);
      expect(summary.profitMargin, closeTo(0.325, 0.0001));
      expect(summary.receivedAmount, 2000000);
      expect(summary.outstandingAmount, 0);
      expect(summary.isFullyPaid, isTrue);

      await orders.addFileMetadata(
        orderId: order.id,
        fileName: 'PI-001.pdf',
        originalName: 'PI-001.pdf',
        documentType: OrderDocumentType.pi,
        localRelativePath: 'Orders/${order.id}/PI/PI-001.pdf',
        fileSize: 1024,
        mimeType: 'application/pdf',
      );
      final file = (await orders.watchFiles(order.id).first).single;
      expect(file.documentType, OrderDocumentType.pi);
      expect(file.localRelativePath, contains('/PI/'));
    },
  );

  test('v1 to v4 migration preserves existing task rows', () async {
    final previousWarningSetting =
        driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final directory = await Directory.systemTemp.createTemp('fly-v1-v2-');
    final file = File('${directory.path}${Platform.pathSeparator}fly.sqlite');
    AppDatabase? legacy;
    AppDatabase? migrated;
    try {
      legacy = AppDatabase(NativeDatabase(file));
      await legacy.ensureBuiltInData();
      final taskRepository = DriftTaskRepository(legacy);
      final task = await taskRepository.createTask(title: 'Must survive');

      await legacy.customStatement('PRAGMA foreign_keys = OFF');
      for (final table in const [
        'customer_custom_field_values',
        'customer_custom_field_definitions',
        'order_notes',
        'order_files',
        'order_tag_links',
        'order_payments',
        'order_production_items',
        'products',
        'factories',
        'orders',
        'order_statuses',
        'customer_tag_links',
        'customer_follow_ups',
        'customer_notes',
        'customer_contacts',
        'customers',
        'customer_sources',
        'customer_statuses',
        'customer_categories',
      ]) {
        await legacy.customStatement('DROP TABLE $table');
      }
      await legacy.customStatement('PRAGMA user_version = 1');
      await legacy.close();
      legacy = null;

      migrated = AppDatabase(NativeDatabase(file));
      await migrated.ensureBuiltInData();
      final preserved = await DriftTaskRepository(migrated)
          .watchTask(task.id)
          .first;
      expect(preserved?.title, 'Must survive');
      expect(
        (await DriftCustomerRepository(
          migrated,
        ).watchCategories().first).length,
        4,
      );
      expect(
        (await DriftOrderRepository(migrated).watchStatuses().first).length,
        6,
      );
    } finally {
      await legacy?.close();
      await migrated?.close();
      if (await directory.exists()) await directory.delete(recursive: true);
      driftRuntimeOptions.dontWarnAboutMultipleDatabases =
          previousWarningSetting;
    }
  });

  test('v2 to v4 migration preserves legacy customer notes', () async {
    final previousWarningSetting =
        driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final directory = await Directory.systemTemp.createTemp('fly-v2-v3-');
    final file = File('${directory.path}${Platform.pathSeparator}fly.sqlite');
    AppDatabase? legacy;
    AppDatabase? migrated;
    try {
      legacy = AppDatabase(NativeDatabase(file));
      await legacy.ensureBuiltInData();
      final repository = DriftCustomerRepository(legacy);
      final customer = await repository.createCustomer(name: 'Legacy');
      await repository.saveCustomer(customer.copyWith(notes: '旧版客户备注必须保留'));
      await legacy.customStatement('DROP TABLE customer_custom_field_values');
      await legacy.customStatement(
        'DROP TABLE customer_custom_field_definitions',
      );
      await legacy.customStatement('DROP TABLE order_notes');
      await legacy.customStatement('DROP TABLE customer_notes');
      await legacy.customStatement('PRAGMA user_version = 2');
      await legacy.close();
      legacy = null;

      migrated = AppDatabase(NativeDatabase(file));
      final note = await DriftCustomerRepository(migrated)
          .watchLatestNote(customer.id)
          .first;
      expect(note?.content, '旧版客户备注必须保留');
    } finally {
      await legacy?.close();
      await migrated?.close();
      if (await directory.exists()) await directory.delete(recursive: true);
      driftRuntimeOptions.dontWarnAboutMultipleDatabases =
          previousWarningSetting;
    }
  });
}
