import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide Column, isNull;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/domain/customer.dart';
import 'package:fly/features/customers/presentation/customer_detail_panel.dart';
import 'package:fly/features/customers/presentation/customer_providers.dart';
import 'package:fly/features/notes/domain/note_block.dart';
import 'package:fly/features/notes/presentation/note_block_editor.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/orders/presentation/order_detail_panel.dart';
import 'package:fly/features/orders/presentation/order_providers.dart';
import 'package:fly/features/reviews/presentation/daily_review_page.dart';
import 'package:fly/features/reviews/presentation/review_providers.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/features/tasks/presentation/task_detail_panel.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/features/tools/container_loading/presentation/container_loading_providers.dart';
import 'package:fly/features/tools/container_loading/presentation/workspace/container_loading_page.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/design_system/app_theme.dart';

import 'container_actual_spaces_test.dart' as cargo;
import 'text_input_state_test.dart' as input;

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 12)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
  } else {
    await tester.ensureVisible(finder);
  }
  await settle(tester);
}

Widget app(Widget child, {bool phone = false}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  supportedLocales: FlyLocalizations.supportedLocales,
  localizationsDelegates: const [
    FlyLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: phone ? FlyTheme.dark() : FlyTheme.light(),
  home: Scaffold(body: child),
);

void viewport(WidgetTester tester, bool phone) {
  tester.view.physicalSize = phone
      ? const Size(430, 932)
      : const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = phone ? 1.2 : 1;
  debugDefaultTargetPlatformOverride = phone
      ? TargetPlatform.android
      : TargetPlatform.windows;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async =>
    tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/input-continuity-$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });

Future<void> fonts() async {
  for (final font in {
    'Ahem': 'C:/Windows/Fonts/msyh.ttc',
    'Microsoft YaHei UI': 'C:/Windows/Fonts/msyh.ttc',
    'Microsoft YaHei': 'C:/Windows/Fonts/msyh.ttc',
    'Segoe UI': 'C:/Windows/Fonts/segoeui.ttf',
    'Roboto': 'C:/Windows/Fonts/segoeui.ttf',
    'MaterialIcons': 'D:/ProgramData/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  }.entries) {
    if (await File(font.value).exists()) {
      await (FontLoader(font.key)..addFont(
            Future.value(
              ByteData.sublistView(await File(font.value).readAsBytes()),
            ),
          ))
          .load();
    }
  }
}

void main() {
  for (final phone in [false, true]) {
    testWidgets(
      'customer and numeric custom fields survive saves, IME and record switch phone=$phone',
      (tester) async {
        viewport(tester, phone);
        final db = AppDatabase(NativeDatabase.memory());
        final container = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)],
        );
        final page = ValueNotifier<Widget>(const SizedBox());
        final boundary = GlobalKey();
        try {
          final repo = DriftCustomerRepository(db);
          final data = await tester.runAsync(() async {
            await db.ensureBuiltInData();
            await fonts();
            final a = await repo.createCustomer(name: 'Input customer');
            final b = await repo.createCustomer(name: 'Other customer');
            await repo.saveCustomer(b.copyWith(companyName: 'Other company'));
            final d = await repo.createCustomFieldDefinition(
              'Quantity',
              type: CustomerCustomFieldType.number,
            );
            return (a.id, b.id, d.id);
          });
          final (first, second, definition) = data!;
          page.value = CustomerDetailPanel(customerId: first);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: RepaintBoundary(
                key: boundary,
                child: app(
                  ValueListenableBuilder<Widget>(
                    valueListenable: page,
                    builder: (_, value, _) => value,
                  ),
                  phone: phone,
                ),
              ),
            ),
          );
          await settle(tester);
          final field = find.byKey(const ValueKey('customer-text-公司名称'));
          await reveal(tester, field);
          await tester.enterText(field, '');
          final editorState = tester.state(
            find.descendant(of: field, matching: find.byType(EditableText)),
          );
          await input.typeAtCaret(tester, field, '1');
          await settle(tester);
          expect(
            (await tester.runAsync(
              () => (db.select(
                db.customers,
              )..where((t) => t.id.equals(first))).getSingle(),
            ))!.companyName,
            '1',
          );
          expect(
            input.editable(tester, field).controller.selection,
            const TextSelection.collapsed(offset: 1),
          );
          expect(
            tester.state(
              find.descendant(of: field, matching: find.byType(EditableText)),
            ),
            same(editorState),
          );
          container.invalidate(customerProvider(first));
          await tester.pump();
          await settle(tester);
          await input.typeAtCaret(tester, field, '5');
          await settle(tester);
          expect(
            (await tester.runAsync(
              () => (db.select(
                db.customers,
              )..where((t) => t.id.equals(first))).getSingle(),
            ))!.companyName,
            '15',
          );
          await capture(
            tester,
            boundary,
            'customer-${phone ? 'phone' : 'desktop'}',
          );
          // Save an intermediate IME value, then commit Chinese without refocusing.
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: 'ni',
              selection: TextSelection.collapsed(offset: 2),
              composing: TextRange(start: 0, end: 2),
            ),
          );
          await settle(tester);
          expect(
            input.editable(tester, field).controller.value.composing,
            const TextRange(start: 0, end: 2),
          );
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: '你',
              selection: TextSelection.collapsed(offset: 1),
            ),
          );
          await settle(tester);
          await input.typeAtCaret(tester, field, '好');
          await settle(tester);
          expect(
            (await tester.runAsync(
              () => (db.select(
                db.customers,
              )..where((t) => t.id.equals(first))).getSingle(),
            ))!.companyName,
            '你好',
          );
          final custom = find.byKey(
            ValueKey('custom-field-$first-$definition'),
          );
          await reveal(tester, custom);
          await tester.enterText(custom, '');
          await input.typeAtCaret(tester, custom, '1');
          await settle(tester);
          await input.typeAtCaret(tester, custom, '5');
          await settle(tester);
          final row = await tester.runAsync(
            () =>
                (db.select(db.customerCustomFieldValues)..where(
                      (t) =>
                          t.customerId.equals(first) &
                          t.definitionId.equals(definition),
                    ))
                    .getSingle(),
          );
          expect(row!.value, '15');
          page.value = CustomerDetailPanel(customerId: second);
          await settle(tester);
          await reveal(tester, field);
          expect(
            input.editable(tester, field).controller.text,
            'Other company',
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await settle(tester);
          page.dispose();
          container.dispose();
          await settle(tester);
          await tester.runAsync(db.close);
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'order amount and exchange rate retain caret across saves and switch correctly phone=$phone',
      (tester) async {
        viewport(tester, phone);
        final db = AppDatabase(NativeDatabase.memory());
        final container = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)],
        );
        final page = ValueNotifier<Widget>(const SizedBox());
        final boundary = GlobalKey();
        try {
          final repo = DriftOrderRepository(db);
          final ids = await tester.runAsync(() async {
            await db.ensureBuiltInData();
            await fonts();
            final c = await DriftCustomerRepository(db)
                .createCustomer(name: 'Owner');
            final a = await repo.createOrder(
              customerId: c.id,
              orderNumber: 'PI-ONE',
            );
            final b = await repo.createOrder(
              customerId: c.id,
              orderNumber: 'PI-TWO',
            );
            await repo.saveOrder(b.copyWith(salesAmount: 2500));
            return (a.id, b.id);
          });
          Widget order(String id) => OrderExtensionPanel(
            orderId: id,
            type: OrderExtensionType.financial,
            onClose: () {},
          );
          page.value = order(ids!.$1);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: RepaintBoundary(
                key: boundary,
                child: app(
                  ValueListenableBuilder<Widget>(
                    valueListenable: page,
                    builder: (_, value, _) => value,
                  ),
                  phone: phone,
                ),
              ),
            ),
          );
          await settle(tester);
          final amount = find.byKey(const ValueKey('order-sales-amount'));
          await reveal(tester, amount);
          await tester.enterText(amount, '');
          await input.typeAtCaret(tester, amount, '1');
          await settle(tester);
          expect(
            (await tester.runAsync(
              () => (db.select(
                db.orders,
              )..where((t) => t.id.equals(ids.$1))).getSingle(),
            ))!.salesAmount,
            100,
          );
          await input.typeAtCaret(tester, amount, '5');
          await settle(tester);
          expect(input.editable(tester, amount).controller.text, '15');
          await input.typeAtCaret(tester, amount, '.');
          await settle(tester);
          await input.typeAtCaret(tester, amount, '2');
          await settle(tester);
          await input.typeAtCaret(tester, amount, '5');
          await settle(tester);
          expect(
            (await tester.runAsync(
              () => (db.select(
                db.orders,
              )..where((t) => t.id.equals(ids.$1))).getSingle(),
            ))!.salesAmount,
            1525,
          );
          await capture(
            tester,
            boundary,
            'order-${phone ? 'phone' : 'desktop'}',
          );
          final rate = find.byKey(const ValueKey('order-exchange-rate'));
          await reveal(tester, rate);
          await tester.enterText(rate, '');
          await input.typeAtCaret(tester, rate, '1');
          await settle(tester);
          await input.typeAtCaret(tester, rate, '5');
          await settle(tester);
          expect(
            (await tester.runAsync(
              () => (db.select(
                db.orders,
              )..where((t) => t.id.equals(ids.$1))).getSingle(),
            ))!.exchangeRateMicros,
            15000000,
          );
          page.value = order(ids.$2);
          await settle(tester);
          await reveal(tester, amount);
          expect(input.editable(tester, amount).controller.text, '25.00');
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await settle(tester);
          page.dispose();
          container.dispose();
          await settle(tester);
          await tester.runAsync(db.close);
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }

  testWidgets(
    'task keeps text and caret when a newer version changes another field',
    (tester) async {
      viewport(tester, false);
      final db = AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      try {
        final repo = DriftTaskRepository(db);
        final task = await tester.runAsync(() async {
          await db.ensureBuiltInData();
          return repo.createTask(title: 'Task');
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: app(TaskDetailPanel(taskId: task!.id)),
          ),
        );
        await settle(tester);
        final field = find.byType(TextField).first;
        await tester.enterText(field, '');
        await input.typeAtCaret(tester, field, '1');
        await settle(tester);
        final current = container.read(taskProvider(task.id)).value!;
        await tester.runAsync(
          () =>
              repo.saveTask(current.copyWith(description: 'Updated elsewhere')),
        );
        await settle(tester);
        expect(
          input.editable(tester, field).controller.selection,
          const TextSelection.collapsed(offset: 1),
        );
        await input.typeAtCaret(tester, field, '5');
        await settle(tester);
        expect(
          (await tester.runAsync(
            () => (db.select(
              db.tasks,
            )..where((t) => t.id.equals(task.id))).getSingle(),
          ))!.title,
          '15',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await settle(tester);
        container.dispose();
        await settle(tester);
        await tester.runAsync(db.close);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'review stays an editor during saves and becomes a card only on Done',
    (tester) async {
      viewport(tester, false);
      final db = AppDatabase(NativeDatabase.memory());
      final today = DateTime(2026, 11, 6);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          localTodayProvider.overrideWith((ref) => today),
        ],
      );
      try {
        await tester.runAsync(db.ensureBuiltInData);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: app(const DailyReviewPage()),
          ),
        );
        await settle(tester);
        final field = find.byKey(const ValueKey('review-q1'));
        await reveal(tester, field);
        await tester.enterText(field, '');
        await input.typeAtCaret(tester, field, '1');
        await settle(tester);
        await input.typeAtCaret(tester, field, '5');
        await settle(tester);
        expect(input.editable(tester, field).controller.text, '15');
        await tester.runAsync(
          () => container
              .read(reviewSessionProvider('2026-11-06'))
              .value!
              .flush(),
        );
        await tester.tap(find.byKey(const ValueKey('review-done-q1')));
        await settle(tester);
        expect(field, findsNothing);
        expect(find.byKey(const ValueKey('review-answer-q1')), findsOneWidget);
        expect(find.text('15'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await settle(tester);
        container.dispose();
        await settle(tester);
        await tester.runAsync(db.close);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'manual cargo count echoes keep caret after each digit, clear, refill and undo',
    (tester) async {
      viewport(tester, false);
      final db = AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      try {
        await tester.runAsync(db.ensureBuiltInData);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: app(const ContainerLoadingPage()),
          ),
        );
        await settle(tester);
        final e = container.read(loadingEditorProvider);
        final section = e.sections.first.id;
        e.addCargo(section, cargo.pvc);
        final id = e.scene.groups.single.id;
        e.scene.resizeGroup(id, rows: 8, layers: 10);
        await settle(tester);
        final field = find.byKey(ValueKey('manual-layers-$id'));
        await reveal(tester, field);
        await tester.enterText(field, '');
        await settle(tester);
        expect(e.packedCount, 0);
        await input.typeAtCaret(tester, field, '1');
        await settle(tester);
        expect(
          input.editable(tester, field).controller.selection,
          const TextSelection.collapsed(offset: 1),
        );
        await input.typeAtCaret(tester, field, '5');
        await settle(tester);
        expect(e.scene.groups.single.layers, 15);
        expect(e.packedCount, 120);
        e.scene.undo();
        await settle(tester);
        expect(input.editable(tester, field).controller.text, '1');
        e.scene.redo();
        await settle(tester);
        expect(input.editable(tester, field).controller.text, '15');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await settle(tester);
        container.dispose();
        await settle(tester);
        await tester.runAsync(db.close);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'note text and table retain focus through model echoes and display restored cell values',
    (tester) async {
      var blocks = [
        NoteBlock(id: 'p', type: 'paragraph', content: {'text': ''}),
        NoteBlock(
          id: 't',
          type: 'table',
          content: {
            'rows': [
              [''],
            ],
          },
        ),
      ];
      late StateSetter rebuild;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return NoteBlockEditor(
                blocks: blocks,
                onChanged: (next) => setState(() => blocks = next),
                onAddMedia: (_) {},
                mediaBuilder: (_, _) => const SizedBox(),
              );
            },
          ),
        ),
      );
      for (final key in ['block-text-p', 't-0-0']) {
        final field = find.byKey(ValueKey(key));
        await tester.enterText(field, '');
        await input.typeAtCaret(tester, field, '1');
        await input.typeAtCaret(tester, field, '5');
        expect(input.editable(tester, field).controller.text, '15');
      }
      rebuild(
        () => blocks = [
          blocks.first,
          NoteBlock(
            id: 't',
            type: 'table',
            content: {
              'rows': [
                ['restored'],
              ],
            },
          ),
        ],
      );
      await tester.pump();
      expect(
        input
            .editable(tester, find.byKey(const ValueKey('t-0-0')))
            .controller
            .text,
        'restored',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
