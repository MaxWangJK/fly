import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/domain/customer.dart';
import 'package:fly/features/customers/presentation/customer_list_page.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/orders/domain/order.dart';
import 'package:fly/features/orders/domain/order_lifecycle.dart';
import 'package:fly/features/orders/presentation/order_list_page.dart';
import 'package:fly/features/orders/presentation/order_providers.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/design_system/app_theme.dart';

void main() {
  test('PI number and stage are atomic, duplicates and deleted customers do not create orders', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await db.ensureBuiltInData();
      final customers = DriftCustomerRepository(db),
          orders = DriftOrderRepository(db);
      final c = await customers.createCustomer(name: 'PI customer');
      final created = await orders.createOrder(
        customerId: c.id,
        orderNumber: '  PI-A  ',
        statusId: 'order-production',
      );
      expect(created.orderNumber, 'PI-A');
      expect(created.statusId, 'order-production');
      await expectLater(
        orders.createOrder(customerId: c.id, orderNumber: 'pi-a'),
        throwsStateError,
      );
      expect(
        (await orders
                .watchOrders(const OrderQuery(projection: OrderProjection.all))
                .first)
            .length,
        1,
      );
      expect(
        (await orders.createOrder(
          customerId: c.id,
          orderNumber: 'PI-B',
        )).statusId,
        OrderLifecycle.pending,
      );
      await customers.softDeleteCustomer(c.id);
      await expectLater(
        orders.createOrder(customerId: c.id, orderNumber: 'PI-C'),
        throwsArgumentError,
      );
    } finally {
      await db.close();
    }
  });
  test(
    'six stages survive old configuration while legacy rows stay intact',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await db.ensureBuiltInData();
        final orders = DriftOrderRepository(db);
        final c = await DriftCustomerRepository(db)
            .createCustomer(name: 'Legacy PI');
        final old = await orders.createStatus('Legacy received balance');
        final o = await orders.createOrder(
          customerId: c.id,
          orderNumber: 'OLD-PI',
        );
        await db.customStatement('UPDATE orders SET status_id=? WHERE id=?', [
          old.id,
          o.id,
        ]);
        await db.customStatement(
          "UPDATE order_statuses SET deleted_at=1,is_active=0,sort_order=99 WHERE id='order-shipped'",
        );
        expect(
          (await orders.watchStatuses().first).map((s) => s.name).toList(),
          OrderLifecycle.stages.map((s) => s.$2).toList(),
        );
        expect(
          (await orders.watchOrder(o.id).first)!.statusId,
          OrderLifecycle.pending,
        );
        expect(
          (await (db.select(
            db.orders,
          )..where((r) => r.id.equals(o.id))).getSingle()).statusId,
          old.id,
        );
        expect(
          OrderLifecycle.normalize('order-balance-received'),
          'order-awaiting-shipment',
        );
        expect(
          OrderLifecycle.normalize('order-awaiting-balance'),
          OrderLifecycle.pending,
        );
      } finally {
        await db.close();
      }
    },
  );
  for (final width in [1200.0, 840.0]) {
    testWidgets(
      'customer context PI dialog validates, cancels and creates linked order at $width',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = width == 840
            ? 1.3
            : 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final db = AppDatabase(NativeDatabase.memory());
        final container = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)],
        );
        final boundary = GlobalKey();
        final router = GoRouter(
          initialLocation: '/customers/all',
          routes: [
            GoRoute(
              path: '/customers/all',
              builder: (_, _) =>
                  const CustomerListPage(projection: CustomerProjection.all),
            ),
            GoRoute(
              path: '/orders/all',
              builder: (_, _) =>
                  const OrderListPage(projection: OrderProjection.all),
            ),
          ],
        );
        Future<void> settle() async {
          for (var i = 0; i < 8; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 15)),
            );
            await tester.pump(const Duration(milliseconds: 80));
          }
        }

        try {
          final customer = await tester.runAsync(() async {
            await db.ensureBuiltInData();
            final r = DriftCustomerRepository(db);
            await r.createCustomer(name: 'Alpha customer');
            final target = await r.createCustomer(name: 'Target PI customer');
            await DriftOrderRepository(db)
                .createOrder(customerId: target.id, orderNumber: 'PI-EXISTS');
            for (final font in {
              'Ahem': 'C:/Windows/Fonts/msyh.ttc',
              'Microsoft YaHei UI': 'C:/Windows/Fonts/msyh.ttc',
              'MaterialIcons': 'D:/ProgramData/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            }.entries) {
              await (FontLoader(font.key)..addFont(
                    File(font.value).readAsBytes().then(ByteData.sublistView),
                  ))
                  .load();
            }
            return target;
          });
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: RepaintBoundary(
                key: boundary,
                child: MaterialApp.router(
                  routerConfig: router,
                  debugShowCheckedModeBanner: false,
                  locale: const Locale('zh'),
                  supportedLocales: FlyLocalizations.supportedLocales,
                  localizationsDelegates: const [
                    FlyLocalizationsDelegate(),
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  theme: width == 840 ? FlyTheme.dark() : FlyTheme.light(),
                  builder: (_, child) => Scaffold(body: child),
                ),
              ),
            ),
          );
          await settle();
          Future<void> open() async {
            final row = find.byKey(
              ValueKey('customer-list-row-${customer!.id}'),
            );
            await tester.tapAt(
              tester.getCenter(row),
              kind: PointerDeviceKind.mouse,
              buttons: kSecondaryMouseButton,
            );
            await settle();
            expect(
              tester
                  .getTopLeft(
                    find.byKey(const ValueKey('customer-context-new-order')),
                  )
                  .dy,
              lessThan(tester.getTopLeft(find.text('删除客户')).dy),
            );
            await tester.tap(
              find.byKey(const ValueKey('customer-context-new-order')),
            );
            await settle();
          }

          await open();
          expect(
            tester
                .widget<ChoiceChip>(
                  find.byKey(
                    ValueKey('create-order-status-${OrderLifecycle.pending}'),
                  ),
                )
                .selected,
            isTrue,
          );
          await tester.tap(find.text('取消'));
          await settle();
          expect(
            (await tester.runAsync(() => db.select(db.orders).get()))!.length,
            1,
          );
          await open();
          await tester.tap(find.byKey(const ValueKey('create-order-submit')));
          await settle();
          expect(find.text('请填写PI发票号'), findsOneWidget);
          await tester.enterText(
            find.byKey(const ValueKey('create-order-number')),
            'PI-EXISTS',
          );
          await tester.tap(find.byKey(const ValueKey('create-order-submit')));
          await settle();
          expect(find.text('订单号已存在，请使用其他PI发票号'), findsOneWidget);
          await tester.enterText(
            find.byKey(const ValueKey('create-order-number')),
            'PI-2026-NEW',
          );
          await tester.tap(
            find.byKey(const ValueKey('create-order-status-order-production')),
          );
          await settle();
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('build/build45-order-dialog-${width.toInt()}.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
          await tester.tap(find.byKey(const ValueKey('create-order-submit')));
          await settle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(router.routeInformationProvider.value.uri.path, '/orders/all');
          final id = container.read(selectedOrderIdProvider)!;
          final created = await tester.runAsync(
            () => DriftOrderRepository(db).watchOrder(id).first,
          );
          expect(created!.customerId, customer!.id);
          expect(created.orderNumber, 'PI-2026-NEW');
          expect(created.statusId, 'order-production');
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
          router.dispose();
          await settle();
          await tester.runAsync(db.close);
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
