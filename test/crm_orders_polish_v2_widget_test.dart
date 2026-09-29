import 'package:drift/native.dart';
import 'package:fly/app/app.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/orders/presentation/order_detail_panel.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/shared/domain/priority.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'customer tag filters wrap to at most two lines and preserve selection',
    (tester) async {
      final database = await _database(tester);
      final crm = DriftCustomerRepository(database);
      final customer = await crm.createCustomer(name: 'Jack');
      final today = DateTime.now();
      await crm.saveCustomer(
        customer.copyWith(
          nextFollowUpDate: DateTime(today.year, today.month, today.day),
        ),
      );
      String? firstTagId;
      for (var index = 1; index <= 18; index++) {
        final tag = await crm.findOrCreateTag(
          'Tag ${index.toString().padLeft(2, '0')}',
        );
        firstTagId ??= tag.id;
      }
      await crm.setCustomerTags(customer.id, [firstTagId!]);

      await _pumpApp(tester, database);
      await tester.tap(find.byKey(const ValueKey('primary-customers')));
      await _pumpUi(tester);

      final layout = find.byKey(
        const ValueKey('customer-tag-filter-two-lines'),
      );
      expect(layout, findsOneWidget);
      expect(tester.getSize(layout).height, lessThanOrEqualTo(60));
      await tester.tap(
        find
            .ancestor(of: find.text('Tag 01'), matching: find.byType(InkWell))
            .first,
      );
      await _pumpUi(tester);
      await tester.tap(
        find
            .ancestor(of: find.text('更多 ›'), matching: find.byType(InkWell))
            .first,
      );
      await tester.pumpAndSettle();
      final selectedItem = tester.widget<CheckedPopupMenuItem<String>>(
        find.widgetWithText(CheckedPopupMenuItem<String>, 'Tag 01'),
      );
      expect(selectedItem.checked, isTrue);
      await tester.tapAt(const Offset(900, 700));
      await _pumpUi(tester);
      expect(find.text('Jack'), findsOneWidget);
      await _disposeUi(tester);
    },
  );

  testWidgets('order list has no create action and shows compact level flags', (
    tester,
  ) async {
    final database = await _database(tester);
    final crm = DriftCustomerRepository(database);
    final repository = DriftOrderRepository(database);
    final customer = await crm.createCustomer(name: 'Jack');
    final low = await repository.createOrder(
      customerId: customer.id,
      orderNumber: 'SO-LOW',
    );
    final medium = await repository.createOrder(
      customerId: customer.id,
      orderNumber: 'SO-MEDIUM',
    );
    final high = await repository.createOrder(
      customerId: customer.id,
      orderNumber: 'SO-HIGH',
    );
    await repository.saveOrder(
      low.copyWith(importance: true, priority: PriorityLevel.low),
    );
    await repository.saveOrder(
      medium.copyWith(urgency: true, priority: PriorityLevel.medium),
    );
    await repository.saveOrder(
      high.copyWith(
        importance: true,
        urgency: true,
        priority: PriorityLevel.high,
      ),
    );

    await _pumpApp(tester, database);
    await tester.tap(find.byKey(const ValueKey('primary-orders')));
    await _pumpUi(tester);
    expect(find.text('添加订单'), findsNothing);
    expect(find.byKey(const ValueKey('order-quick-add-button')), findsNothing);
    expect(find.text('重要'), findsOneWidget);
    expect(find.text('紧急'), findsNWidgets(2));
    expect(find.text('重要 · 紧急'), findsNothing);
    await _disposeUi(tester);
  });

  testWidgets('order item extension validates factory product and quantity', (
    tester,
  ) async {
    final database = await _database(tester);
    final crm = DriftCustomerRepository(database);
    final repository = DriftOrderRepository(database);
    final customer = await crm.createCustomer(name: 'Jack');
    final order = await repository.createOrder(
      customerId: customer.id,
      orderNumber: 'SO-ITEM-UI',
    );

    await _pumpApp(tester, database);
    await tester.tap(find.byKey(const ValueKey('primary-orders')));
    await _pumpUi(tester);
    await tester.tap(find.text(order.orderNumber));
    await _pumpUi(tester);
    expect(find.byType(OrderDetailPanel), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('order-details-preview')));
    await _pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('add-order-item')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('order-item-quantity')),
      '',
    );
    await tester.tap(find.byKey(const ValueKey('save-order-item')));
    await tester.pump();
    expect(find.text('工厂、产品和大于 0 的数量均为必填。'), findsOneWidget);
    expect(await database.select(database.orderProductionItems).get(), isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('order-item-factory')),
      '新材料工厂',
    );
    await tester.enterText(
      find.byKey(const ValueKey('order-item-product')),
      'WPC 格栅',
    );
    await tester.enterText(
      find.byKey(const ValueKey('order-item-quantity')),
      '500',
    );
    await tester.tap(find.byKey(const ValueKey('save-order-item')));
    await _pumpUi(tester);
    final item =
        (await database.select(database.orderProductionItems).get()).single;
    expect(item.quantityMilli, 500000);
    await _disposeUi(tester);
  });

  testWidgets(
    'order notes show latest preview and use shared extension input',
    (tester) async {
      final database = await _database(tester);
      final crm = DriftCustomerRepository(database);
      final repository = DriftOrderRepository(database);
      final customer = await crm.createCustomer(name: 'Jack');
      final order = await repository.createOrder(
        customerId: customer.id,
        orderNumber: 'SO-NOTE-UI',
      );
      await repository.addNote(order.id, content: '旧备注');
      await repository.addNote(order.id, content: '客户要求外箱不能有中文');

      await _pumpApp(tester, database);
      await tester.tap(find.byKey(const ValueKey('primary-orders')));
      await _pumpUi(tester);
      await tester.tap(find.text(order.orderNumber));
      await _pumpUi(tester);
      expect(find.text('客户要求外箱不能有中文'), findsOneWidget);
      expect(find.text('旧备注'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('order-notes-preview')));
      await _pumpUi(tester);
      expect(find.text('订单备注'), findsWidgets);
      expect(find.text('旧备注'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('new-order-note-input')),
        '客户要求周五前确认唛头',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _pumpUi(tester);
      final notes = await (database.select(
        database.orderNotes,
      )..where((row) => row.orderId.equals(order.id))).get();
      expect(notes.map((note) => note.content), contains('客户要求周五前确认唛头'));
      await _disposeUi(tester);
    },
  );
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
