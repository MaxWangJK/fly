import 'package:drift/native.dart';
import 'package:fly/app/app.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/presentation/customer_extension_panel.dart';
import 'package:fly/features/customers/presentation/customer_providers.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/design_system/app_theme.dart';

void main() {
  testWidgets(
    'either follow-up field saves on Enter and empty input does not',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.ensureBuiltInData();
      final repository = DriftCustomerRepository(database);
      final customer = await repository.createCustomer(
        name: 'Follow-up Widget',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            theme: FlyTheme.light(),
            locale: const Locale('zh', 'CN'),
            supportedLocales: FlyLocalizations.supportedLocales,
            localizationsDelegates: const [
              FlyLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: SizedBox(
                width: 520,
                child: CustomerExtensionPanel(
                  customerId: customer.id,
                  type: DetailExtensionType.followUps,
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await _pumpUi(tester);
      final content = find.byKey(const ValueKey('new-followup-input'));
      final next = find.byKey(const ValueKey('new-followup-next-action'));

      await tester.tap(next);
      await tester.enterText(next, '周五联系');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _pumpUi(tester);
      var rows = (await tester.runAsync(
        () => repository.watchFollowUps(customer.id).first,
      ))!;
      expect(rows.single.content, isEmpty);
      expect(rows.single.nextAction, '周五联系');
      expect(tester.widget<TextField>(content).focusNode?.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _pumpUi(tester);
      rows = (await tester.runAsync(
        () => repository.watchFollowUps(customer.id).first,
      ))!;
      expect(rows, hasLength(1));

      await tester.enterText(content, '客户收到样品');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _pumpUi(tester);
      rows = (await tester.runAsync(
        () => repository.watchFollowUps(customer.id).first,
      ))!;
      expect(rows, hasLength(2));
      expect(rows.first.content, '客户收到样品');
      await _disposeUi(tester);
    },
  );

  testWidgets('follow-up context menu edits and soft deletes', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.ensureBuiltInData();
    final repository = DriftCustomerRepository(database);
    final customer = await repository.createCustomer(name: 'History Menu');
    final followUp = await repository.addFollowUp(
      customer.id,
      channel: 'Email',
      content: '旧内容',
      nextAction: '旧下一步',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: FlyTheme.light(),
          locale: const Locale('zh', 'CN'),
          supportedLocales: FlyLocalizations.supportedLocales,
          localizationsDelegates: const [
            FlyLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: SizedBox(
              width: 520,
              child: CustomerExtensionPanel(
                customerId: customer.id,
                type: DetailExtensionType.followUps,
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUi(tester);
    final block = find.byKey(ValueKey('followup-${followUp.id}'));
    await tester.tapAt(tester.getCenter(block), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('new-followup-next-action')),
          )
          .controller
          ?.text,
      '旧下一步',
    );
    await tester.enterText(
      find.byKey(const ValueKey('new-followup-input')),
      '新内容',
    );
    await tester.enterText(
      find.byKey(const ValueKey('new-followup-next-action')),
      '新下一步',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _pumpUi(tester);
    final edited = (await tester.runAsync(
      () => repository.watchFollowUps(customer.id).first,
    ))!;
    expect(edited.single.content, '新内容');

    await tester.tapAt(
      tester.getCenter(find.byKey(ValueKey('followup-${followUp.id}'))),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('确定删除这条跟进记录？'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await _pumpUi(tester);
    expect(
      await tester.runAsync(() => repository.watchFollowUps(customer.id).first),
      isEmpty,
    );
    await _disposeUi(tester);
  });

  testWidgets('financial dialogs use inherited currency and empty type hints', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.ensureBuiltInData();
    final customers = DriftCustomerRepository(database);
    final orders = DriftOrderRepository(database);
    final customer = await customers.createCustomer(name: 'Financial Dialog');
    final order = await orders.createOrder(
      customerId: customer.id,
      orderNumber: 'SO-V5-DIALOG',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const FlyApp(),
      ),
    );
    await _pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('primary-orders')));
    await _pumpUi(tester);
    await tester.tap(find.text(order.orderNumber).first);
    await _pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('order-financial-preview')));
    await _pumpUi(tester);

    expect(find.byKey(const ValueKey('quick-financial-定金')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-financial-尾款')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-financial-工厂成本')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-financial-内陆费')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-financial-港杂费')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-order-payment')));
    await tester.pumpAndSettle();
    var type = tester.widget<TextField>(
      find.byKey(const ValueKey('financial-entry-type')),
    );
    var amount = tester.widget<TextField>(
      find.byKey(const ValueKey('financial-entry-amount')),
    );
    expect(type.controller?.text, isEmpty);
    expect(type.decoration?.hintText, '定金 / 尾款 / 补款 / 样品费…');
    expect(amount.decoration?.prefixText, isNull);
    expect(
      tester
          .widget<SegmentedButton<String>>(
            find.byKey(const ValueKey('financial-entry-currency')),
          )
          .selected,
      {'USD'},
    );
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-order-cost')));
    await tester.pumpAndSettle();
    type = tester.widget<TextField>(
      find.byKey(const ValueKey('financial-entry-type')),
    );
    expect(type.controller?.text, isEmpty);
    expect(type.decoration?.hintText, contains('工厂成本'));
    expect(
      tester
          .widget<SegmentedButton<String>>(
            find.byKey(const ValueKey('financial-entry-currency')),
          )
          .selected,
      {'CNY'},
    );
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    await _disposeUi(tester);
  });

  testWidgets('customer customs information uses a multiline editor', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.ensureBuiltInData();
    final repository = DriftCustomerRepository(database);
    var customer = await repository.createCustomer(name: 'Customs Customer');
    final now = DateTime.now();
    customer = customer.copyWith(
      nextFollowUpDate: DateTime(now.year, now.month, now.day),
    );
    await repository.saveCustomer(customer);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const FlyApp(),
      ),
    );
    await _pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('primary-customers')));
    await _pumpUi(tester);
    await tester.tap(find.text(customer.name).first);
    await _pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('customer-customs-info')));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('customer-customs-info-input'));
    expect(tester.widget<TextField>(input).maxLines, 14);
    await tester.enterText(
      input,
      'Consignee: Fly Trading\nAddress: Shanghai\nTel: 123\nEmail: fly@example.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await _pumpUi(tester);
    final saved = await tester.runAsync(
      () => repository.watchCustomer(customer.id).first,
    );
    expect(saved?.customsInfo, contains('Address: Shanghai'));
    expect(find.text('Consignee: Fly Trading'), findsOneWidget);
    // V10 makes basic information expanded by default.
    expect(find.text('客户来源'), findsOneWidget);
    await tester.tap(find.text('基本信息'));
    await _pumpUi(tester);
    expect(find.text('客户来源'), findsNothing);
    await tester.tap(find.text('基本信息'));
    await _pumpUi(tester);
    expect(find.text('客户来源'), findsOneWidget);
    await _disposeUi(tester);
  });
}

Future<void> _pumpUi(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _disposeUi(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(Duration.zero);
}
