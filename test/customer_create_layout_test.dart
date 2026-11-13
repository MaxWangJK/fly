import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/presentation/customer_create_dialog.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';

import 'input_continuity_widget_test.dart' as ui;

void main() {
  for (final scenario in [
    (const Size(1264, 681), false, 1.0),
    (const Size(900, 600), false, 1.3),
    (const Size(390, 844), true, 1.3),
  ]) {
    testWidgets('customer name and fixed actions stay visible at $scenario', (
      tester,
    ) async {
      final (size, phone, scale) = scenario;
      ui.viewport(tester, phone);
      tester.view.physicalSize = size;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetViewInsets);
      final db = AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      final capture = GlobalKey();
      try {
        await tester.runAsync(() async {
          await db.ensureBuiltInData();
          final customers = DriftCustomerRepository(db);
          await customers.createCategory('E级客户');
          await customers.createCategory('F级客户');
          await ui.fonts();
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(
              key: capture,
              child: ui.app(
                Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const CustomerCreateDialog(),
                    ),
                    child: const Text('Open customer'),
                  ),
                ),
                phone: phone,
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open customer'));
        await ui.settle(tester);
        await tester.enterText(
          find.byKey(const ValueKey('customer-quick-add-input')),
          'Alex',
        );
        await ui.settle(tester);
        if (const bool.fromEnvironment('FLY_CUSTOMER_LAYOUT_CAPTURE')) {
          await tester.runAsync(
            () => Directory('build').create(recursive: true),
          );
          await ui.capture(
            tester,
            capture,
            'customer-layout-${size.width.toInt()}',
          );
        }
        final viewport = tester.getRect(
          find.byType(SingleChildScrollView).first,
        );
        final label = tester.getRect(find.text('客户姓名 *'));
        expect(
          label.top,
          greaterThanOrEqualTo(viewport.top),
          reason: 'Floating name label must not be clipped by the viewport',
        );
        for (final key in [
          if (!phone) 'customer-batch-import',
          if (!phone) 'customer-import-template',
          'phone-create-customer',
        ]) {
          final button = find.byKey(ValueKey(key));
          expect(
            button.hitTestable(),
            findsOneWidget,
            reason: '$key must be accessible without scrolling the form',
          );
          final rect = tester.getRect(button);
          expect(
            rect.bottom,
            lessThanOrEqualTo(
              tester.getTopLeft(find.byType(AlertDialog)).dy +
                  tester.getSize(find.byType(AlertDialog)).height,
            ),
          );
        }
        final source = find.byKey(const ValueKey('customer-create-source'));
        await ui.reveal(tester, source);
        await tester.enterText(source, 'Long custom source');
        await ui.settle(tester);
        final create = find.byKey(const ValueKey('phone-create-customer'));
        expect(create.hitTestable(), findsOneWidget);
        if (phone) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await ui.settle(tester);
          expect(create.hitTestable(), findsOneWidget);
          expect(
            find.byKey(const ValueKey('customer-import-template')),
            findsNothing,
          );
          tester.view.resetViewInsets();
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await ui.settle(tester);
        await tester.runAsync(db.close);
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
