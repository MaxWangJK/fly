import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/app/app.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/presentation/customer_detail_panel.dart';
import 'package:fly/features/customers/presentation/customer_providers.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/orders/presentation/order_detail_panel.dart';
import 'package:fly/features/orders/presentation/order_providers.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/features/tasks/presentation/task_detail_panel.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/shared/design_system/tag_container.dart';

import 'input_continuity_widget_test.dart' as ui;

void main() {
  testWidgets(
    'new empty category and empty order results clear detail and extension',
    (tester) async {
      ui.viewport(tester, false);
      tester.view.physicalSize = const Size(1500, 900);
      final db = AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      final repo = DriftCustomerRepository(db);
      final orderRepo = DriftOrderRepository(db);
      final setup = (await tester.runAsync(() async {
        await db.ensureBuiltInData();
        await ui.fonts();
        final categories = await repo.watchCategories().first;
        final a = categories.firstWhere((c) => c.name == 'A级');
        final b = categories.firstWhere((c) => c.name == 'B级');
        final alex = await repo.createCustomer(
          name: 'Only A customer',
          categoryId: a.id,
        );
        await repo.createCustomer(name: 'Only B customer', categoryId: b.id);
        final order = await orderRepo.createOrder(
          customerId: alex.id,
          orderNumber: 'ONLY-PI',
        );
        final tag = await orderRepo.findOrCreateTag('Historical order tag');
        await orderRepo.setOrderTags(order.id, [tag.id]);
        return (a: a, b: b, alex: alex, order: order, tag: tag);
      }))!;
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const FlyApp(),
          ),
        );
        await ui.settle(tester);
        await tester.tap(find.byKey(const ValueKey('primary-customers')));
        await ui.settle(tester);
        final sidebar = find.byKey(
          const ValueKey('customer-secondary-sidebar'),
        );
        await tester.tap(
          find.descendant(of: sidebar, matching: find.text('A级')),
        );
        await ui.settle(tester);
        // Even an old in-memory multi-tag selection cannot hide the category.
        container.read(customerTagFilterProvider.notifier).state = {
          setup.a.tagId!,
          setup.b.tagId!,
        };
        await ui.settle(tester);
        expect(find.text('Only A customer'), findsWidgets);
        expect(find.text('Only B customer'), findsNothing);
        expect(container.read(selectedCustomerIdProvider), setup.alex.id);
        expect(find.byType(FlyTagContainer), findsNothing);
        expect(
          find.byKey(const ValueKey('customer-tag-filter-two-lines')),
          findsNothing,
        );
        container.read(customerDetailExtensionProvider.notifier).state =
            DetailExtensionType.notes;
        await ui.settle(tester);
        await tester.tap(find.byKey(const ValueKey('add-customer-category')));
        await ui.settle(tester);
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          'New empty category',
        );
        await tester.tap(find.widgetWithText(FilledButton, '保存'));
        await ui.settle(tester);
        expect(container.read(selectedCustomerIdProvider), isNull);
        expect(
          container.read(customerDetailExtensionProvider),
          DetailExtensionType.none,
        );
        expect(find.byType(CustomerDetailPanel), findsNothing);
        expect(find.text('Only A customer'), findsNothing);
        await tester.tap(
          find.descendant(of: sidebar, matching: find.text('B级')),
        );
        await ui.settle(tester);
        expect(find.text('Only B customer'), findsWidgets);
        expect(find.text('Only A customer'), findsNothing);

        container.read(customerSearchProvider.notifier).state =
            'No matching customer';
        await ui.settle(tester);
        expect(container.read(selectedCustomerIdProvider), isNull);
        expect(find.byType(CustomerDetailPanel), findsNothing);
        container.read(customerSearchProvider.notifier).state = '';
        await ui.settle(tester);
        expect(find.text('Only B customer'), findsWidgets);

        await tester.tap(find.byKey(const ValueKey('primary-orders')));
        await ui.settle(tester);
        expect(container.read(selectedOrderIdProvider), setup.order.id);
        expect(find.byType(OrderDetailPanel), findsOneWidget);
        expect(find.byType(FlyTagContainer), findsNothing);
        expect(find.text('Historical order tag'), findsNothing);
        expect(find.byKey(const ValueKey('manage-order-tags')), findsNothing);
        container.read(orderExtensionProvider.notifier).state =
            OrderExtensionType.financial;
        container.read(orderSearchProvider.notifier).state =
            'No matching order';
        await ui.settle(tester);
        expect(container.read(selectedOrderIdProvider), isNull);
        expect(container.read(orderExtensionProvider), OrderExtensionType.none);
        expect(find.byType(OrderDetailPanel), findsNothing);
        container.read(orderSearchProvider.notifier).state = '';
        await ui.settle(tester);
        expect(container.read(selectedOrderIdProvider), setup.order.id);
        expect(
          (await tester.runAsync(
            () => orderRepo.watchOrderTags(setup.order.id).first,
          ))!.single.id,
          setup.tag.id,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await ui.settle(tester);
        await tester.runAsync(db.close);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  for (final phone in [false, true]) {
    testWidgets(
      'compact task notes retain continuous input and save phone=$phone',
      (tester) async {
        ui.viewport(tester, phone);
        final db = AppDatabase(NativeDatabase.memory());
        final container = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)],
        );
        final repo = DriftTaskRepository(db);
        final task = (await tester.runAsync(() async {
          await db.ensureBuiltInData();
          await ui.fonts();
          return repo.createTask(title: 'Notes height test');
        }))!;
        final capture = GlobalKey();
        try {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: RepaintBoundary(
                key: capture,
                child: ui.app(TaskDetailPanel(taskId: task.id), phone: phone),
              ),
            ),
          );
          await ui.settle(tester);
          final notes = find.byKey(const ValueKey('task-description-input'));
          await ui.reveal(tester, notes);
          expect(tester.getSize(notes).height, lessThan(130));
          await tester.enterText(
            notes,
            'Notes https://example.com\nSecond line',
          );
          await tester.pump(const Duration(milliseconds: 900));
          await ui.settle(tester);
          expect(
            (await tester.runAsync(() => repo.watchTask(task.id).first))!
                .description,
            'Notes https://example.com\nSecond line',
          );
          expect(
            tester.widget<TextField>(notes).controller!.selection.isCollapsed,
            isTrue,
          );
          if (const bool.fromEnvironment('FLY_SIMPLIFY_CAPTURE')) {
            await ui.capture(
              tester,
              capture,
              'compact-task-${phone ? 'phone' : 'desktop'}',
            );
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
          await ui.settle(tester);
          await tester.runAsync(db.close);
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'customer and order details hide tag editors preserving stored links phone=$phone',
      (tester) async {
        ui.viewport(tester, phone);
        final db = AppDatabase(NativeDatabase.memory());
        final container = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)],
        );
        final repo = DriftCustomerRepository(db);
        final orders = DriftOrderRepository(db);
        final setup = (await tester.runAsync(() async {
          await db.ensureBuiltInData();
          final customer = await repo.createCustomer(name: 'Tag preservation');
          final customerTag = await repo.findOrCreateTag(
            'Stored customer label',
          );
          await repo.setCustomerTags(customer.id, [customerTag.id]);
          final order = await orders.createOrder(
            customerId: customer.id,
            orderNumber: 'TAG-PI',
          );
          final orderTag = await orders.findOrCreateTag('Stored order label');
          await orders.setOrderTags(order.id, [orderTag.id]);
          return (
            customer: customer,
            order: order,
            customerTag: customerTag,
            orderTag: orderTag,
          );
        }))!;
        try {
          for (final child in [
            CustomerDetailPanel(customerId: setup.customer.id),
            OrderDetailPanel(orderId: setup.order.id),
          ]) {
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: container,
                child: ui.app(child, phone: phone),
              ),
            );
            await ui.settle(tester);
            expect(find.byType(FlyTagContainer), findsNothing);
            expect(find.text('Stored customer label'), findsNothing);
            expect(find.text('Stored order label'), findsNothing);
          }
          expect(
            (await tester.runAsync(
              () => repo.watchCustomerTags(setup.customer.id).first,
            ))!.single.id,
            setup.customerTag.id,
          );
          expect(
            (await tester.runAsync(
              () => orders.watchOrderTags(setup.order.id).first,
            ))!.single.id,
            setup.orderTag.id,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
          await ui.settle(tester);
          await tester.runAsync(db.close);
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
