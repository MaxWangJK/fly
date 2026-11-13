import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/domain/customer.dart';
import 'package:fly/features/customers/presentation/customer_create_dialog.dart';
import 'package:fly/features/customers/presentation/customer_detail_panel.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';

import 'input_continuity_widget_test.dart' as ui;

void main() {
  for (final scenario in [
    (const Size(1264, 681), false),
    (const Size(390, 844), true),
    (const Size(844, 390), true),
  ]) {
    testWidgets(
      'customer status add edit delete retains draft and history at $scenario',
      (tester) async {
        final (size, phone) = scenario;
        ui.viewport(tester, phone);
        tester.view.physicalSize = size;
        final db = AppDatabase(NativeDatabase.memory());
        final container = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)],
        );
        final repo = DriftCustomerRepository(db);
        final capture = GlobalKey();
        Customer? created;
        Finder key(String value) => find.byKey(ValueKey(value));
        Future<void> tap(String value) async {
          await ui.reveal(tester, key(value));
          await tester.tap(key(value));
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
                  phone: phone,
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
          await tap('customer-create-category-category-a');
          await tap('customer-create-status-customer-repeat');
          final repeat = key('customer-create-status-customer-repeat');
          await tester.tap(repeat);
          await tester.pump(const Duration(milliseconds: 70));
          await tester.tap(repeat);
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
              'customer-status-${size.width.toInt()}',
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
