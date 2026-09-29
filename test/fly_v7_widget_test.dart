import 'package:drift/native.dart';
import 'package:fly/app/app.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/domain/customer.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Ctrl+K opens global search and a result opens its detail', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.ensureBuiltInData();
    final customer = await DriftCustomerRepository(database)
        .createCustomer(name: 'Global Jack');
    await _pumpFly(tester, database);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('global-search-input'));
    expect(input, findsOneWidget);
    await tester.enterText(input, 'Global Jack');
    await tester.pump(const Duration(milliseconds: 260));
    await _pumpUi(tester);
    final result = find.byKey(ValueKey('search-customer-${customer.id}'));
    expect(result, findsOneWidget);
    await tester.tap(result);
    await _pumpUi(tester);
    expect(find.text('Global Jack'), findsWidgets);
    expect(find.text('基本信息'), findsOneWidget);
    await _disposeUi(tester);
  });

  testWidgets('dashboard contains only the five V7 focus cards', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.ensureBuiltInData();
    await DriftCustomerRepository(database)
        .createCustomer(name: 'Dashboard sample');
    await _pumpFly(tester, database);

    await tester.tap(find.byKey(const ValueKey('primary-dashboard')));
    await _pumpUi(tester);
    for (final title in const ['今天需跟进客户', '今天任务', '待收款订单', '紧急订单', '本月利润']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
    await _disposeUi(tester);
  });

  testWidgets('customer list shows the compact Next Action type', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.ensureBuiltInData();
    final repository = DriftCustomerRepository(database);
    final created = await repository.createCustomer(name: 'Payment Customer');
    final today = DateTime.now();
    await repository.saveCustomer(
      created.copyWith(
        nextFollowUpDate: DateTime(today.year, today.month, today.day),
        nextActionType: NextActionType.paymentFollowUp,
        nextAction: '周五再次提醒',
      ),
    );
    await _pumpFly(tester, database);

    final capsule = find.byKey(ValueKey('customer-next-action-${created.id}'));
    await tester.tap(find.byKey(const ValueKey('primary-customers')));
    await _pumpUi(tester);
    expect(capsule, findsOneWidget);
    expect(
      find.descendant(of: capsule, matching: find.text('催付款')),
      findsOneWidget,
    );
    await _disposeUi(tester);
  });

  testWidgets('financial summaries keep original currencies only', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.ensureBuiltInData();
    final customers = DriftCustomerRepository(database);
    final orders = DriftOrderRepository(database);
    final customer = await customers.createCustomer(name: 'Finance Customer');
    final created = await orders.createOrder(
      customerId: customer.id,
      orderNumber: 'SO-V7-FINANCE',
    );
    await orders.saveOrder(
      created.copyWith(
        currency: 'USD',
        baseProfitCurrency: 'CNY',
        exchangeRateMicros: 7130000,
        salesAmount: 500000,
      ),
    );
    await orders.addPayment(
      created.id,
      amount: 100000,
      currency: 'USD',
      paymentType: '定金',
      paidAt: DateTime.now(),
    );
    await orders.addCostEntry(
      created.id,
      amountMinor: 5000000,
      currency: 'CNY',
      costType: '工厂成本',
      occurredAt: DateTime.now(),
    );
    await _pumpFly(tester, database);
    await tester.tap(find.byKey(const ValueKey('primary-orders')));
    await _pumpUi(tester);
    await tester.tap(find.text('SO-V7-FINANCE'));
    await _pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('order-financial-preview')));
    await _pumpUi(tester);

    final received = find.byKey(const ValueKey('received-summary'));
    final cost = find.byKey(const ValueKey('cost-summary'));
    expect(
      find.descendant(of: received, matching: find.text('USD 1000.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: received, matching: find.text('USD 4000.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cost, matching: find.text('RMB 50000.00')),
      findsOneWidget,
    );
    expect(find.textContaining('折合'), findsNothing);
    expect(find.textContaining('≈'), findsNothing);
    final rate = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('order-exchange-rate')),
        matching: find.byType(TextField),
      ),
    );
    expect(rate.controller?.text, '7.13');
    await _disposeUi(tester);
  });
}

Future<void> _pumpFly(WidgetTester tester, AppDatabase database) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1500, 950);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const FlyApp(),
    ),
  );
  await _pumpUi(tester);
}

Future<void> _pumpUi(WidgetTester tester) async {
  for (var index = 0; index < 14; index++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _disposeUi(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(Duration.zero);
}
