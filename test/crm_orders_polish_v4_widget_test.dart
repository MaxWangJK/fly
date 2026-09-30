import 'package:drift/native.dart';
import 'package:fly/app/app.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/presentation/customer_providers.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('customer category sidebar synchronizes its linked tag filter', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftCustomerRepository(database);
    final setup = await tester.runAsync(() async {
      await database.ensureBuiltInData();
      final categories = await repository.watchCategories().first;
      final a = categories.firstWhere((item) => item.name == 'A级');
      final b = categories.firstWhere((item) => item.name == 'B级');
      final philippines = await repository.findOrCreateTag('菲律宾');
      var mira = await repository.createCustomer(name: 'Mira');
      mira = mira.copyWith(categoryId: b.id);
      await repository.saveCustomer(mira);
      await repository.setCustomerTags(mira.id, [a.tagId!, philippines.id]);
      return (customerId: mira.id, aTagId: a.tagId!);
    });
    final aTagId = setup!.aTagId;

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const FlyApp()),
    );
    await _pumpUi(tester);

    final sidebar = find.byKey(const ValueKey('customer-secondary-sidebar'));
    await tester.tap(find.byKey(const ValueKey('primary-customers')));
    await _pumpUi(tester);
    await tester.tap(find.descendant(of: sidebar, matching: find.text('A级')));
    await _pumpUi(tester);
    expect(container.read(customerTagFilterProvider), {aTagId});
    expect(find.text('Mira'), findsWidgets);

    await tester.tap(find.descendant(of: sidebar, matching: find.text('全部客户')));
    await _pumpUi(tester);
    expect(container.read(customerTagFilterProvider), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('follow-up editor saves optional next action and keeps focus', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftCustomerRepository(database);
    final customerId = await tester.runAsync(() async {
      await database.ensureBuiltInData();
      return (await repository.createCustomer(name: 'Mira')).id;
    });

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        selectedCustomerIdProvider.overrideWith((ref) => customerId),
        customerDetailExtensionProvider.overrideWith(
          (ref) => DetailExtensionType.followUps,
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const FlyApp()),
    );
    await _pumpUi(tester);

    final content = find.byKey(const ValueKey('new-followup-input'));
    await tester.tap(find.byKey(const ValueKey('primary-customers')));
    await _pumpUi(tester);
    final nextAction = find.byKey(const ValueKey('new-followup-next-action'));
    await tester.enterText(content, '客户确认样品已收到');
    await tester.enterText(nextAction, '周五问客户测试结果');
    await tester.tap(content);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _pumpUi(tester);

    final saved = await tester.runAsync(
      () => repository.watchLatestNextAction(customerId!).first,
    );
    expect(saved?.nextAction, '周五问客户测试结果');
    expect(tester.widget<TextField>(content).focusNode?.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Future<void> _pumpUi(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}
