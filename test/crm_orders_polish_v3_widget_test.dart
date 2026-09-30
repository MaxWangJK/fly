import 'dart:ui';

import 'package:drift/native.dart';
import 'package:fly/app/app.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fresh startup opens customer workspace by default', (
    tester,
  ) async {
    final database = await _database(tester);
    await _pumpApp(tester, database);

    expect(find.text('Dashboard'), findsNothing);
    expect(find.byKey(const ValueKey('primary-customers')), findsOneWidget);
    await _disposeUi(tester);
  });

  testWidgets('calendar mouse wheel changes the visible month', (tester) async {
    final database = await _database(tester);
    await _pumpApp(tester, database);
    await tester.tap(find.byKey(const ValueKey('primary-calendar')));
    await _pumpUi(tester);

    final now = DateTime.now();
    final next = DateTime(now.year, now.month + 1);
    expect(find.text('${now.year}年${now.month}月'), findsOneWidget);
    final surface = find.byKey(const ValueKey('calendar-scroll-surface'));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(surface),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await _pumpUi(tester);

    expect(find.text('${next.year}年${next.month}月'), findsOneWidget);
    await _disposeUi(tester);
  });

  testWidgets('customer right click confirms order impact and soft deletes', (
    tester,
  ) async {
    final database = await _database(tester);
    final customers = DriftCustomerRepository(database);
    final orders = DriftOrderRepository(database);
    final customer = await customers.createCustomer(
      name: 'Right Click Customer',
    );
    final today = DateTime.now();
    await customers.saveCustomer(
      customer.copyWith(
        nextFollowUpDate: DateTime(today.year, today.month, today.day),
      ),
    );
    await orders.createOrder(
      customerId: customer.id,
      orderNumber: 'SO-CUSTOMER-CONTEXT',
    );
    await _pumpApp(tester, database);
    await tester.tap(find.byKey(const ValueKey('primary-customers')));
    await _pumpUi(tester);

    await _rightClick(tester, find.text(customer.name).first);
    expect(find.text('删除客户'), findsOneWidget);
    await tester.tap(find.text('删除客户'));
    await _pumpUi(tester);
    expect(find.textContaining('1 个关联订单'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-destructive-action')));
    await _pumpUi(tester);

    final deleted = await (database.select(
      database.customers,
    )..where((row) => row.id.equals(customer.id))).getSingle();
    expect(deleted.deletedAt, isNotNull);
    await _disposeUi(tester);
  });

  testWidgets('order right click soft deletes', (tester) async {
    final database = await _database(tester);
    final customers = DriftCustomerRepository(database);
    final orders = DriftOrderRepository(database);
    final customer = await customers.createCustomer(name: 'Order Owner');
    final order = await orders.createOrder(
      customerId: customer.id,
      orderNumber: 'SO-ORDER-CONTEXT',
    );
    await _pumpApp(tester, database);
    await tester.tap(find.byKey(const ValueKey('primary-orders')));
    await _pumpUi(tester);

    await _rightClick(tester, find.text(order.orderNumber));
    await tester.tap(find.text('删除订单'));
    await _pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-destructive-action')));
    await _pumpUi(tester);

    final deleted = await (database.select(
      database.orders,
    )..where((row) => row.id.equals(order.id))).getSingle();
    expect(deleted.deletedAt, isNotNull);
    await _disposeUi(tester);
  });

  testWidgets('calendar task right click uses shared soft delete', (
    tester,
  ) async {
    final database = await _database(tester);
    final tasks = DriftTaskRepository(database);
    final task = await tasks.createTask(
      title: 'Calendar Context Task',
      dueDate: DateTime.now(),
    );
    await _pumpApp(tester, database);
    await tester.tap(find.byKey(const ValueKey('primary-calendar')));
    await _pumpUi(tester);

    await _rightClick(tester, find.text(task.title));
    await tester.tap(find.text('删除任务'));
    await _pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-destructive-action')));
    await _pumpUi(tester);

    final deleted = await (database.select(
      database.tasks,
    )..where((row) => row.id.equals(task.id))).getSingle();
    expect(deleted.deletedAt, isNotNull);
    await _disposeUi(tester);
  });

  testWidgets('matrix task right click uses shared soft delete', (
    tester,
  ) async {
    final database = await _database(tester);
    final tasks = DriftTaskRepository(database);
    final task = await tasks.createTask(
      title: 'Matrix Context Task',
      importance: true,
      urgency: true,
    );
    await _pumpApp(tester, database);
    await tester.tap(find.byKey(const ValueKey('primary-matrix')));
    await _pumpUi(tester);

    await _rightClick(tester, find.text(task.title));
    await tester.tap(find.text('删除任务'));
    await _pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-destructive-action')));
    await _pumpUi(tester);

    final deleted = await (database.select(
      database.tasks,
    )..where((row) => row.id.equals(task.id))).getSingle();
    expect(deleted.deletedAt, isNotNull);
    await _disposeUi(tester);
  });
}

Future<void> _rightClick(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(
    tester.getCenter(finder),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<AppDatabase> _database(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1500, 940);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  await database.ensureBuiltInData();
  return database;
}

Future<void> _pumpApp(WidgetTester tester, AppDatabase database) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const FlyApp(),
    ),
  );
  await _pumpUi(tester);
}

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
