import 'package:drift/native.dart';
import 'package:fly/app/app.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/domain/customer.dart';
import 'package:fly/features/customers/presentation/customer_detail_panel.dart';
import 'package:fly/features/customers/presentation/customer_sidebar.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/orders/presentation/order_detail_panel.dart';
import 'package:fly/features/orders/presentation/order_sidebar.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/shared/design_system/priority.dart';
import 'package:fly/shared/domain/priority.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CRM shows today follow-up and completes only today cycle', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.ensureBuiltInData();
    final repository = DriftCustomerRepository(database);
    final created = await repository.createCustomer(name: 'Jack');
    final today = DateTime.now();
    await repository.saveCustomer(
      created.copyWith(
        country: '菲律宾',
        nextFollowUpDate: DateTime(today.year, today.month, today.day),
        followUpRecurrence: FollowUpRecurrence.every3Days,
        priority: PriorityLevel.high,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const FlyApp(),
      ),
    );
    await _pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('primary-customers')));
    await _pumpUi(tester);

    expect(find.byType(CustomerSidebar), findsOneWidget);
    expect(find.text('Jack'), findsOneWidget);
    await tester.tap(find.text('Jack'));
    await _pumpUi(tester);
    expect(find.byType(CustomerDetailPanel), findsOneWidget);

    await tester.tap(find.byType(Checkbox).first);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await _pumpUi(tester);
    final saved = await (database.select(
      database.customers,
    )..where((row) => row.id.equals(created.id))).getSingle();
    expect(saved.deletedAt, isNull);
    expect(saved.lastFollowUpAt, isNotNull);
    expect(
      saved.nextFollowUpDate,
      DateTime(today.year, today.month, today.day + 3),
    );
    await _disposeUi(tester);
  });

  testWidgets('Customer and Order workspaces keep bidirectional context', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.ensureBuiltInData();
    final crm = DriftCustomerRepository(database);
    final orders = DriftOrderRepository(database);
    final customer = await crm.createCustomer(name: 'Jack');
    final today = DateTime.now();
    await crm.saveCustomer(
      customer.copyWith(
        nextFollowUpDate: DateTime(today.year, today.month, today.day),
      ),
    );
    final order = await orders.createOrder(
      customerId: customer.id,
      orderNumber: 'SO-2026-001',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const FlyApp(),
      ),
    );
    await _pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('primary-customers')));
    await _pumpUi(tester);
    await tester.tap(find.text('Jack'));
    await _pumpUi(tester);

    final customerScrollable = find.descendant(
      of: find.byType(CustomerDetailPanel),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('查看订单'),
      300,
      scrollable: customerScrollable.first,
    );
    await tester.tap(find.text('查看订单'));
    await _pumpUi(tester);

    expect(find.byType(OrderSidebar), findsOneWidget);
    expect(find.byKey(const ValueKey('order-customer-filter')), findsOneWidget);
    expect(find.text('SO-2026-001'), findsOneWidget);
    await tester.tap(find.text('SO-2026-001'));
    await _pumpUi(tester);
    expect(find.byType(OrderDetailPanel), findsOneWidget);
    expect(find.text('Jack ›'), findsOneWidget);

    await tester.tap(find.text('Jack ›'));
    await _pumpUi(tester);
    expect(find.byType(CustomerSidebar), findsOneWidget);
    expect(find.byType(CustomerDetailPanel), findsOneWidget);
    expect(await refOrderExists(database, order.id), isTrue);
    await _disposeUi(tester);
  });

  testWidgets(
    'Order detail uses compact financial and item extension summaries',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 1050);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.ensureBuiltInData();
      final crm = DriftCustomerRepository(database);
      final orders = DriftOrderRepository(database);
      final customer = await crm.createCustomer(name: 'Safety Customer');
      final order = await orders.createOrder(
        customerId: customer.id,
        orderNumber: 'SO-SAFE-001',
      );
      await orders.saveOrder(
        order.copyWith(
          baseProfitCurrency: 'USD',
          exchangeRateMicros: 1000000,
          salesAmount: 2000000,
          taxRefund: 150000,
          inlandCost: 50000,
          portCharges: 30000,
          otherCost: 20000,
        ),
      );
      await orders.addProductionItem(
        order.id,
        factoryName: '工厂A',
        productName: 'WPC',
        quantityMilli: 1000,
        factoryCost: 1400000,
      );
      await orders.addProductionItem(
        order.id,
        factoryName: '工厂B',
        productName: 'UV',
        quantityMilli: 1000,
      );
      await orders.addPayment(
        order.id,
        amount: 2000000,
        currency: 'USD',
        paymentType: '尾款',
        paidAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(database)],
          child: const FlyApp(),
        ),
      );
      await _pumpUi(tester);
      await tester.tap(find.byKey(const ValueKey('primary-orders')));
      await _pumpUi(tester);
      await tester.tap(find.text('SO-SAFE-001'));
      await _pumpUi(tester);

      expect(
        find.byKey(const ValueKey('unplaced-factory-warning')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('order-details-preview')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('order-financial-preview')),
        findsOneWidget,
      );
      expect(find.textContaining('RMB 6500.00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('order-details-preview')));
      await _pumpUi(tester);
      expect(find.byKey(const ValueKey('add-order-item')), findsOneWidget);
      expect(find.text('未下单'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('close-order-extension')));
      await _pumpUi(tester);
      await tester.tap(find.byKey(const ValueKey('order-financial-preview')));
      await _pumpUi(tester);
      expect(find.text('已收合计'), findsOneWidget);
      expect(find.byKey(const ValueKey('order-exchange-rate')), findsOneWidget);
      expect(find.byKey(const ValueKey('add-order-cost')), findsOneWidget);
      await _disposeUi(tester);
    },
  );

  testWidgets(
    'customer creates a selected order without choosing customer again',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.ensureBuiltInData();
      final crm = DriftCustomerRepository(database);
      final customer = await crm.createCustomer(name: 'Jack');
      final today = DateTime.now();
      await crm.saveCustomer(
        customer.copyWith(
          nextFollowUpDate: DateTime(today.year, today.month, today.day),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(database)],
          child: const FlyApp(),
        ),
      );
      await _pumpUi(tester);
      await tester.tap(find.byKey(const ValueKey('primary-customers')));
      await _pumpUi(tester);
      await tester.tap(find.text('Jack'));
      await _pumpUi(tester);

      final detailScrollable = find.descendant(
        of: find.byType(CustomerDetailPanel),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('create-order-for-customer')),
        260,
        scrollable: detailScrollable.first,
      );
      await tester.tap(find.byKey(const ValueKey('create-order-for-customer')));
      await _pumpUi(tester);

      final created = await database.select(database.orders).getSingle();
      expect(created.customerId, customer.id);
      expect(created.orderDate, DateTime(today.year, today.month, today.day));
      expect(find.byType(OrderDetailPanel), findsOneWidget);
      expect(
        find.byKey(const ValueKey('order-customer-filter')),
        findsOneWidget,
      );
      await _disposeUi(tester);
    },
  );

  testWidgets('notes use latest preview and one-input extension panel', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 960);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.ensureBuiltInData();
    final crm = DriftCustomerRepository(database);
    final customer = await crm.createCustomer(name: 'Jack');
    final today = DateTime.now();
    await crm.saveCustomer(
      customer.copyWith(
        nextFollowUpDate: DateTime(today.year, today.month, today.day),
      ),
    );
    await crm.addNote(customer.id, content: 'Note A');
    await crm.addNote(customer.id, content: 'Note B');
    await crm.addNote(customer.id, content: 'Note C');
    await crm.addFollowUp(
      customer.id,
      channel: 'WhatsApp',
      content: '客户确认收到报价',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const FlyApp(),
      ),
    );
    await _pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('primary-customers')));
    await _pumpUi(tester);
    await tester.tap(find.text('Jack'));
    await _pumpUi(tester);

    expect(find.text('Note C'), findsOneWidget);
    expect(find.text('Note A'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('customer-notes-preview')));
    await _pumpUi(tester);
    expect(find.text('客户备注'), findsOneWidget);
    expect(find.text('Note A'), findsOneWidget);
    expect(find.text('Note B'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('new-note-input')));
    await tester.enterText(
      find.byKey(const ValueKey('new-note-input')),
      '客户本周五确认最终数量',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _pumpUi(tester);
    final savedNotes = await (database.select(
      database.customerNotes,
    )..where((row) => row.customerId.equals(customer.id))).get();
    savedNotes.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    expect(savedNotes.first.content, '客户本周五确认最终数量');
    await _disposeUi(tester);
  });

  testWidgets('follow-ups use latest preview and one-input extension panel', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 960);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.ensureBuiltInData();
    final crm = DriftCustomerRepository(database);
    final customer = await crm.createCustomer(name: 'Jack');
    final today = DateTime.now();
    await crm.saveCustomer(
      customer.copyWith(
        nextFollowUpDate: DateTime(today.year, today.month, today.day),
      ),
    );
    await crm.addFollowUp(
      customer.id,
      channel: 'WhatsApp',
      content: '客户确认收到报价',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const FlyApp(),
      ),
    );
    await _pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('primary-customers')));
    await _pumpUi(tester);
    await tester.tap(find.text('Jack'));
    await _pumpUi(tester);
    expect(find.text('客户确认收到报价'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('customer-followup-preview')));
    await _pumpUi(tester);
    expect(find.text('跟进记录'), findsWidgets);
    expect(find.text('客户确认收到报价'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('new-followup-input')),
      '客户要求重新确认包装成本',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _pumpUi(tester);
    final savedFollowUps = await (database.select(
      database.customerFollowUps,
    )..where((row) => row.customerId.equals(customer.id))).get();
    savedFollowUps.sort(
      (left, right) => right.followedUpAt.compareTo(left.followedUpAt),
    );
    expect(savedFollowUps.first.content, '客户要求重新确认包装成本');
    final savedCustomer = await (database.select(
      database.customers,
    )..where((row) => row.id.equals(customer.id))).getSingle();
    expect(savedCustomer.lastFollowUpAt, isNotNull);
    await _disposeUi(tester);
  });

  testWidgets('customer keeps priority while order uses one exclusive level', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.ensureBuiltInData();
    final crm = DriftCustomerRepository(database);
    final orders = DriftOrderRepository(database);
    final customer = await crm.createCustomer(name: 'Jack');
    final today = DateTime.now();
    await crm.saveCustomer(
      customer.copyWith(
        nextFollowUpDate: DateTime(today.year, today.month, today.day),
      ),
    );
    final order = await orders.createOrder(
      customerId: customer.id,
      orderNumber: 'SO-PRIORITY',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const FlyApp(),
      ),
    );
    await _pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('primary-customers')));
    await _pumpUi(tester);
    await tester.tap(find.text('Jack'));
    await _pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('priority-medium')));
    await _pumpUi(tester);
    final mediumCustomer = await (database.select(
      database.customers,
    )..where((row) => row.id.equals(customer.id))).getSingle();
    expect(mediumCustomer.priority, PriorityLevel.medium.name);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Material &&
            widget.color == PriorityColorTokens.mediumSelected,
      ),
      findsWidgets,
    );

    await tester.tap(find.byKey(const ValueKey('primary-orders')));
    await _pumpUi(tester);
    await tester.tap(find.text('SO-PRIORITY'));
    await _pumpUi(tester);
    await tester.tap(find.text('紧急').last);
    await _pumpUi(tester);
    final highOrder = await (database.select(
      database.orders,
    )..where((row) => row.id.equals(order.id))).getSingle();
    expect(highOrder.priority, PriorityLevel.low.name);
    expect(highOrder.importance, isFalse);
    expect(highOrder.urgency, isTrue);
    await _disposeUi(tester);
  });
}

Future<bool> refOrderExists(AppDatabase database, String id) async =>
    (database.select(database.orders)..where((row) => row.id.equals(id)))
        .getSingleOrNull()
        .then((value) => value != null);

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _disposeUi(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(Duration.zero);
}
