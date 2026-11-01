import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
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
import 'package:fly/features/orders/presentation/order_list_page.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/l10n/crm_copy.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/design_system/app_theme.dart';
import 'package:fly/shared/design_system/workspace_list_columns.dart';

void main() {
  for (final scenario in [
    (const Size(1400, 900), false, false, 1.0, 'zh'),
    (const Size(900, 800), false, true, 1.3, 'en'),
    (const Size(390, 844), true, false, 1.0, 'zh'),
    (const Size(320, 720), true, true, 1.3, 'zh'),
    (const Size(844, 390), true, true, 1.0, 'en'),
  ]) {
    final (size, phone, dark, scale, language) = scenario;
    testWidgets(
      'customer/order field names align and remain usable at $size $language',
      (tester) async {
        debugDefaultTargetPlatformOverride = phone
            ? TargetPlatform.android
            : TargetPlatform.windows;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final db = AppDatabase(NativeDatabase.memory());
        final crm = DriftCustomerRepository(db);
        final orders = DriftOrderRepository(db);
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
              path: '/customers/deleted',
              builder: (_, _) => const CustomerListPage(
                projection: CustomerProjection.deleted,
              ),
            ),
            GoRoute(
              path: '/orders/all',
              builder: (_, _) =>
                  const OrderListPage(projection: OrderProjection.all),
            ),
            GoRoute(
              path: '/orders/deleted',
              builder: (_, _) =>
                  const OrderListPage(projection: OrderProjection.deleted),
            ),
          ],
        );
        Future<void> settle() async {
          for (var i = 0; i < 10; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump(const Duration(milliseconds: 80));
          }
        }

        Future<void> capture(String name) async {
          if (!const bool.fromEnvironment('FLY_CRM_COLUMNS_CAPTURE')) return;
          await tester.runAsync(() async {
            final picture =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            try {
              final bytes = await picture.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'build/crm-columns-$name-${size.width.toInt()}-$language.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              picture.dispose();
            }
          });
        }

        late Customer customer;
        late SalesOrder order;
        String label(String source) =>
            language == 'zh' ? source : crmEnglish[source] ?? source;
        void checkColumns(String kind, String id, List<String> labels) {
          final header = find.byKey(ValueKey('$kind-list-columns'));
          final row = find.byKey(
            ValueKey(phone ? 'phone-$kind-$id' : '$kind-list-row-$id'),
          );
          expect(header, findsOneWidget);
          final heading = tester.widget<WorkspaceListColumns>(
            find.descendant(
              of: header,
              matching: find.byType(WorkspaceListColumns),
            ),
          );
          final record = tester.widget<WorkspaceListColumns>(
            phone
                ? find.descendant(
                    of: row,
                    matching: find.byType(WorkspaceListColumns),
                  )
                : row,
          );
          for (final source in labels) {
            expect(
              find.descendant(of: header, matching: find.text(label(source))),
              findsOneWidget,
            );
          }
          for (final pair in [
            (heading.primary, record.primary),
            (heading.secondary, record.secondary),
            (heading.status, record.status),
            (heading.date, record.date),
          ]) {
            expect(
              tester.getTopLeft(find.byWidget(pair.$1)).dx,
              closeTo(tester.getTopLeft(find.byWidget(pair.$2)).dx, .1),
            );
          }
        }

        try {
          await tester.runAsync(() async {
            await db.ensureBuiltInData();
            customer = await crm.createCustomer(name: 'Northwind Tools');
            await crm.saveCustomer(
              customer.copyWith(
                country: 'Portugal',
                nextActionType: NextActionType.sendQuote,
              ),
            );
            final other = await crm.createCustomer(name: 'Harbour Parts');
            await crm.saveCustomer(
              other.copyWith(
                country: 'UAE',
                nextActionType: NextActionType.paymentFollowUp,
              ),
            );
            order = await orders.createOrder(
              customerId: customer.id,
              orderNumber: 'FLY-001',
            );
            await orders.saveOrder(
              order.copyWith(orderDate: DateTime(2026, 10, 30)),
            );
            if (const bool.fromEnvironment('FLY_CRM_COLUMNS_CAPTURE')) {
              for (final font in {
                'Ahem': 'C:/Windows/Fonts/msyh.ttc',
                'Microsoft YaHei UI': 'C:/Windows/Fonts/msyh.ttc',
                'MaterialIcons': 'D:/ProgramData/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              }.entries) {
                final file = File(font.value);
                if (await file.exists()) {
                  await (FontLoader(font.key)..addFont(
                        Future.value(
                          ByteData.sublistView(await file.readAsBytes()),
                        ),
                      ))
                      .load();
                }
              }
            }
          });
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: RepaintBoundary(
                key: boundary,
                child: MaterialApp.router(
                  debugShowCheckedModeBanner: false,
                  routerConfig: router,
                  theme: dark ? FlyTheme.dark() : FlyTheme.light(),
                  locale: Locale(language),
                  supportedLocales: FlyLocalizations.supportedLocales,
                  localizationsDelegates: const [
                    FlyLocalizationsDelegate(),
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  builder: (context, child) => Scaffold(
                    body: Center(
                      child: SizedBox(
                        width: phone ? double.infinity : 488,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await settle();
          checkColumns('customer', customer.id, ['客户名称', '国家', '客户状态', '最近跟进']);
          if (phone) {
            final row = find.byKey(ValueKey('phone-customer-${customer.id}'));
            expect(
              find.descendant(
                of: row,
                matching: find.byType(WorkspaceListField),
              ),
              findsNothing,
            );
            expect(
              find.descendant(of: row, matching: find.text('Portugal')),
              findsOneWidget,
            );
          }
          await capture('customers');
          router.go('/orders/all');
          await settle();
          checkColumns('order', order.id, ['订单号', '客户名称', '订单状态', '订单日期']);
          await capture('orders');
          // Restore controls use the same leading space as their field headings.
          await tester.runAsync(() => orders.softDeleteOrder(order.id));
          await settle();
          if (!phone) {
            expect(
              find.byKey(const ValueKey('order-list-columns')),
              findsOneWidget,
            );
          }
          router.go('/orders/deleted');
          await settle();
          if (!phone) {
            checkColumns('order', order.id, ['订单号', '客户名称', '订单状态', '订单日期']);
          }
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
