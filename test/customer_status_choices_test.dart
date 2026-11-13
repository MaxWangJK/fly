import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/domain/customer.dart';
import 'package:fly/features/customers/presentation/customer_create_dialog.dart';
import 'package:fly/features/customers/presentation/customer_detail_panel.dart';
import 'package:fly/features/customers/presentation/customer_providers.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';

import 'input_continuity_widget_test.dart' as ui;

void main() {
  for (final scenario in [
    (const Size(1264, 681), false, false, TargetPlatform.windows),
    (const Size(900, 700), false, true, TargetPlatform.windows),
    (const Size(390, 844), true, true, TargetPlatform.android),
    (const Size(844, 390), true, true, TargetPlatform.android),
    (const Size(430, 932), true, false, TargetPlatform.iOS),
  ]) {
    testWidgets(
      'customer status platform actions retain selection draft and history at $scenario',
      (tester) async {
        final (size, phone, dark, platform) = scenario;
        ui.viewport(tester, phone);
        tester.view.physicalSize = size;
        debugDefaultTargetPlatformOverride = platform;
        if (!phone && dark) {
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        }
        final db = AppDatabase(NativeDatabase.memory());
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            // Keep exported UI evidence on neutral synthetic source labels.
            customerSourcesProvider.overrideWith(
              (ref) => Stream.value([
                for (final (index, label) in [
                  'Website',
                  'Exhibition',
                  'Referral',
                  'Trade directory',
                  'Newsletter',
                  'Other',
                ].indexed)
                  CustomerSource(
                    id: 'source-$index',
                    name: label,
                    colorValue: 0xff7e9f64,
                    isActive: true,
                    sortOrder: index,
                  ),
              ]),
            ),
          ],
        );
        final repo = DriftCustomerRepository(db);
        final capture = GlobalKey();
        Customer? created;
        String? mobileStatus;
        Finder key(String value) => find.byKey(ValueKey(value));
        Future<void> tap(String value) async {
          await ui.reveal(tester, key(value));
          await tester.tap(key(value));
          await ui.settle(tester);
        }

        Future<void> chooseWithoutDelay(Finder chip) async {
          await ui.reveal(tester, chip);
          await tester.tap(
            chip,
            kind: phone ? PointerDeviceKind.touch : PointerDeviceKind.mouse,
          );
          await tester.pump();
          expect(
            tester.widget<ChoiceChip>(chip).selected,
            isTrue,
            reason: 'Selection must update on the first frame after release, without waiting for a double-click timeout',
          );
          await ui.settle(tester);
        }

        Future<String> add(String name) async {
          await tap('customer-create-status-add');
          if (phone && size.height > 600) {
            tester.view.viewInsets = const FakeViewPadding(bottom: 300);
            await ui.settle(tester);
          }
          await tester.enterText(key('customer-status-name'), name);
          await tap('customer-status-save');
          tester.view.resetViewInsets();
          await ui.settle(tester);
          return (await tester.runAsync(() => repo.watchStatuses().first))!
              .singleWhere((s) => s.name == name)
              .id;
        }

        try {
          final historical = (await tester.runAsync(() async {
            await db.ensureBuiltInData();
            await ui.fonts();
            if (phone) {
              mobileStatus = (await repo.createStatus('Partner review')).id;
            }
            return repo.createCustomer(
              name: 'Historical buyer',
              statusId: 'customer-repeat',
            );
          }))!;
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: RepaintBoundary(
                key: capture,
                child: ui.app(
                  Builder(
                    builder: (context) => TextButton(
                      child: const Text('Open'),
                      onPressed: () async {
                        created = await showDialog<Customer>(
                          context: context,
                          builder: (_) => const CustomerCreateDialog(),
                        );
                      },
                    ),
                  ),
                  phone: dark,
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await ui.settle(tester);
          await tester.enterText(
            key('customer-quick-add-input'),
            'New partner',
          );
          await tester.enterText(key('customer-create-country'), 'Canada');
          await chooseWithoutDelay(key('customer-create-category-category-a'));
          await chooseWithoutDelay(find.widgetWithText(ChoiceChip, '网站'));
          await chooseWithoutDelay(
            key('customer-create-status-customer-repeat'),
          );
          if (phone) {
            expect(key('customer-create-status-add'), findsNothing);
            for (final item in (await tester.runAsync(
              () => repo.watchStatuses().first,
            ))!) {
              expect(key('customer-status-delete-${item.id}'), findsNothing);
            }
            final repeat = key('customer-create-status-customer-repeat');
            await tester.longPress(repeat);
            await ui.settle(tester);
            await tester.tap(repeat);
            await tester.pump(const Duration(milliseconds: 70));
            await tester.tap(repeat);
            await ui.settle(tester);
            expect(key('customer-status-name'), findsNothing);
            expect(key('customer-status-confirm-delete'), findsNothing);
            await tap('customer-create-status-$mobileStatus');
            expect(
              tester
                  .widget<ChoiceChip>(
                    key('customer-create-status-$mobileStatus'),
                  )
                  .selected,
              isTrue,
            );
            if (const bool.fromEnvironment('FLY_STATUS_CAPTURE')) {
              await ui.capture(
                tester,
                capture,
                'customer-status-refined-${size.width.toInt()}',
              );
            }
            // A desktop/sync update remains visible without exposing management.
            await tester.runAsync(
              () => repo.renameStatus(mobileStatus!, 'Partner approved'),
            );
            await ui.settle(tester);
            expect(find.text('Partner approved'), findsOneWidget);
            expect(
              tester
                  .widget<ChoiceChip>(
                    key('customer-create-status-$mobileStatus'),
                  )
                  .selected,
              isTrue,
            );
            expect(
              tester
                  .widget<TextFormField>(key('customer-quick-add-input'))
                  .controller!
                  .text,
              'New partner',
            );
            await tap('phone-create-customer');
            expect(created?.name, 'New partner');
            expect(created?.statusId, mobileStatus);
            expect(created?.country, 'Canada');
            expect(tester.takeException(), isNull);
            return;
          }
          final repeat = key('customer-create-status-customer-repeat');
          Future<void> mouseClick() async {
            await tester.tap(repeat, kind: PointerDeviceKind.mouse);
            await tester.pump();
          }

          await mouseClick();
          await tester.tap(
            repeat,
            buttons: kSecondaryButton,
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();
          await mouseClick();
          expect(key('customer-status-name'), findsNothing);
          await ui.settle(tester);
          for (final cancel in [false, true]) {
            await mouseClick();
            final gesture = await tester.startGesture(
              tester.getCenter(repeat),
              kind: PointerDeviceKind.mouse,
            );
            if (cancel) {
              await gesture.cancel();
            } else {
              await gesture.moveBy(const Offset(30, 0));
              await gesture.up();
            }
            await mouseClick();
            expect(key('customer-status-name'), findsNothing);
            await ui.settle(tester);
          }
          final badge = key('customer-status-delete-customer-repeat');
          final badgeRect = tester.getRect(badge);
          final chipRect = tester.getRect(repeat);
          expect(badgeRect.size, const Size.square(20));
          expect(badgeRect.center.dx, closeTo(chipRect.right - 2, .1));
          expect(badgeRect.center.dy, closeTo(chipRect.top + 2, .1));
          final labelRect = tester.getRect(
            find.descendant(of: repeat, matching: find.text('复购客户')),
          );
          expect(badgeRect.overlaps(labelRect), isFalse);
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.moveTo(labelRect.center);
          await tester.pump(const Duration(milliseconds: 120));
          expect(key('customer-status-confirm-delete'), findsNothing);
          if (const bool.fromEnvironment('FLY_STATUS_CAPTURE')) {
            await ui.capture(
              tester,
              capture,
              'customer-status-refined-${size.width.toInt()}',
            );
            await mouse.moveTo(badgeRect.center);
            await tester.pump(const Duration(milliseconds: 120));
            await ui.capture(
              tester,
              capture,
              'customer-status-refined-hover-${size.width.toInt()}',
            );
          }
          await tester.tap(repeat, kind: PointerDeviceKind.mouse);
          await tester.pump(const Duration(milliseconds: 70));
          await tester.tap(repeat, kind: PointerDeviceKind.mouse);
          await ui.settle(tester);
          expect(key('customer-status-name'), findsOneWidget);
          await tester.enterText(
            key('customer-status-name'),
            'Returning buyer',
          );
          await tap('customer-status-save');
          expect(find.text('Returning buyer'), findsOneWidget);
          final custom = await add('Partner review');
          final label = find.descendant(
            of: key('customer-create-status-$custom'),
            matching: find.text('Partner review'),
          );
          expect(
            tester
                .getRect(key('customer-status-delete-$custom'))
                .overlaps(tester.getRect(label)),
            isFalse,
          );
          expect(
            tester
                .widget<ChoiceChip>(key('customer-create-status-$custom'))
                .selected,
            isTrue,
          );
          if (const bool.fromEnvironment('FLY_STATUS_CAPTURE')) {
            await ui.reveal(tester, key('customer-create-status-$custom'));
            await ui.capture(
              tester,
              capture,
              'customer-status-refined-custom-${size.width.toInt()}',
            );
          }
          await tap('customer-create-status-add');
          await tester.enterText(key('customer-status-name'), 'PARTNER REVIEW');
          await tap('customer-status-save');
          expect(find.textContaining('客户状态名称已存在'), findsOneWidget);
          await tester.tap(find.text('取消').last);
          await ui.settle(tester);
          await tap('customer-status-delete-$custom');
          await tester.tap(find.text('取消').last);
          await ui.settle(tester);
          expect(
            tester
                .widget<ChoiceChip>(key('customer-create-status-$custom'))
                .selected,
            isTrue,
          );
          await tap('customer-status-delete-$custom');
          await tap('customer-status-confirm-delete');
          expect(key('customer-create-status-$custom'), findsNothing);
          await tap('customer-status-delete-customer-repeat');
          await tap('customer-status-confirm-delete');
          expect(key('customer-create-status-customer-repeat'), findsNothing);
          expect(
            (await tester.runAsync(
              () => repo.watchCustomer(historical.id).first,
            ))!.statusId,
            'customer-repeat',
          );
          final last = await add('Negotiation');
          expect(
            tester
                .widget<TextFormField>(key('customer-quick-add-input'))
                .controller!
                .text,
            'New partner',
          );
          await tap('phone-create-customer');
          expect(created?.name, 'New partner');
          expect(created?.statusId, last);
          expect(created?.country, 'Canada');
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: ui.app(
                CustomerDetailPanel(customerId: created!.id),
                phone: phone,
              ),
            ),
          );
          await ui.settle(tester);
          expect(find.text('Negotiation'), findsOneWidget);
          await tester.runAsync(
            () => repo.setStatusActive(last, active: false),
          );
          await ui.settle(tester);
          expect(find.text('Negotiation'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          tester.view.resetViewInsets();
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
