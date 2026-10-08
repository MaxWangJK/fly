import 'dart:ui' show PointerDeviceKind;

import 'package:drift/native.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/app/shell/primary_navigation_rail.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/domain/customer.dart';
import 'package:fly/features/customers/presentation/customer_list_page.dart';
import 'package:fly/features/customers/presentation/customer_providers.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/features/tasks/presentation/task_list_page.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/design_system/app_theme.dart';
import 'package:fly/shared/design_system/fly_color_scheme.dart';
import 'package:fly/shared/domain/priority.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('palette changes instantly from settings and persists', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.ensureBuiltInData();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const _PaletteHarness(),
      ),
    );
    await tester.pumpAndSettle();
    Material rail() => tester.widget<Material>(
      find.byKey(const ValueKey('primary-navigation-rail')),
    );
    expect(
      rail().color,
      FlyColorScheme.resolve(
        FlyPaletteId.flyDefault,
        Brightness.light,
      ).primaryRail,
    );
    await tester.tap(find.byKey(const ValueKey('primary-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-category-1')));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('palette-flyDefault'))).dy,
      tester.getTopLeft(find.byKey(const ValueKey('palette-sageMist'))).dy,
    );
    expect(find.byKey(const ValueKey('palette-graphite')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('palette-sageMist')));
    await tester.pumpAndSettle();
    expect(
      rail().color,
      FlyColorScheme.resolve(
        FlyPaletteId.sageMist,
        Brightness.light,
      ).primaryRail,
    );
    expect(
      (await (database.select(
        database.appSettings,
      )..where((row) => row.key.equals('colorPalette'))).getSingle()).value,
      FlyPaletteId.sageMist.name,
    );
    await tester.tap(find.text('海洋'));
    await tester.pumpAndSettle();
    expect(
      rail().color,
      FlyColorScheme.resolve(FlyPaletteId.ocean, Brightness.light).primaryRail,
    );
    final stored = await (database.select(
      database.appSettings,
    )..where((row) => row.key.equals('colorPalette'))).getSingle();
    expect(stored.value, FlyPaletteId.ocean.name);
    await tester.ensureVisible(find.byKey(const ValueKey('palette-clarity')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('palette-clarity')));
    await tester.pumpAndSettle();
    expect(
      rail().color,
      FlyColorScheme.resolve(
        FlyPaletteId.clarity,
        Brightness.light,
      ).primaryRail,
    );
    final updated = await (database.select(
      database.appSettings,
    )..where((row) => row.key.equals('colorPalette'))).getSingle();
    expect(updated.value, FlyPaletteId.clarity.name);
    await tester.ensureVisible(find.byKey(const ValueKey('palette-mintCloud')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('palette-mintCloud')));
    await tester.pumpAndSettle();
    expect(
      rail().color,
      FlyColorScheme.resolve(
        FlyPaletteId.mintCloud,
        Brightness.light,
      ).primaryRail,
    );
    expect(
      (await (database.select(
        database.appSettings,
      )..where((row) => row.key.equals('colorPalette'))).getSingle()).value,
      FlyPaletteId.mintCloud.name,
    );
    await _dispose(tester);
  });

  testWidgets('task list selects its first item and keeps a minimal menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.ensureBuiltInData();
    final repository = DriftTaskRepository(database);
    final today = DateTime.now();
    final first = await repository.createTask(
      title: 'First visible task',
      dueDate: today,
    );
    await repository.createTask(
      title: 'Overdue visible task',
      dueDate: today.subtract(const Duration(days: 2)),
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        taskRepositoryProvider.overrideWithValue(repository),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(
          child: TaskListPage(collection: TaskCollection.today),
        ),
      ),
    );
    await _pump(tester);
    expect(container.read(selectedTaskIdProvider), first.id);
    Future<void> rightClick(String title) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.text(title)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await rightClick('First visible task');
    expect(find.text('删除任务'), findsOneWidget);
    expect(find.text('顺延到今天'), findsNothing);
    expect(find.text('设置日期'), findsNothing);
    expect(find.text('编辑'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await rightClick('Overdue visible task');
    expect(find.text('删除任务'), findsOneWidget);
    expect(find.text('顺延到今天'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _dispose(tester);
    container.dispose();
    for (var index = 0; index < 12; index++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });

  testWidgets(
    'task quick input is always visible and keeps focus after Enter',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.ensureBuiltInData();
      final repository = DriftTaskRepository(database);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            taskRepositoryProvider.overrideWithValue(repository),
          ],
          child: const _TestApp(
            child: TaskListPage(collection: TaskCollection.upcoming),
          ),
        ),
      );
      await _pump(tester);
      final input = find.byKey(const ValueKey('quick-add-input'));
      expect(input, findsOneWidget);
      expect(find.byKey(const ValueKey('quick-add-button')), findsNothing);
      await tester.tap(input);
      await tester.enterText(input, 'V6 quick task');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _pump(tester);
      final tasks = (await tester.runAsync(
        () => repository.watchAllTasks().first,
      ))!;
      expect(tasks.single.title, 'V6 quick task');
      final due = tasks.single.dueDate!;
      final now = DateTime.now();
      expect(DateUtils.isSameDay(due, now), isTrue);
      expect(tester.widget<TextField>(input).controller?.text, isEmpty);
      expect(tester.widget<TextField>(input).focusNode?.hasFocus, isTrue);
      await tester.enterText(input, 'clear me');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(tester.widget<TextField>(input).controller?.text, isEmpty);
      expect(tester.widget<TextField>(input).focusNode?.hasFocus, isFalse);
      await _dispose(tester);
    },
  );

  testWidgets('selected customer row keeps compact priority capsule', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.ensureBuiltInData();
    final repository = DriftCustomerRepository(database);
    final created = await repository.createCustomer(name: 'Priority Customer');
    await repository.saveCustomer(
      created.copyWith(priority: PriorityLevel.high),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          customerRepositoryProvider.overrideWithValue(repository),
        ],
        child: const _TestApp(
          child: CustomerListPage(projection: CustomerProjection.all),
        ),
      ),
    );
    await _pump(tester);
    final capsule = find.byKey(ValueKey('customer-priority-${created.id}'));
    expect(capsule, findsOneWidget);
    expect(
      find.descendant(of: capsule, matching: find.text('高')),
      findsOneWidget,
    );
    final materials = tester.widgetList<Material>(
      find.ancestor(of: capsule, matching: find.byType(Material)),
    );
    expect(
      materials.any(
        (material) =>
            material.color ==
            FlyTheme.light().colorScheme.surfaceContainerHighest,
      ),
      isTrue,
    );
    await _dispose(tester);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: FlyTheme.light(),
    locale: const Locale('zh', 'CN'),
    supportedLocales: FlyLocalizations.supportedLocales,
    localizationsDelegates: const [
      FlyLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );
}

class _PaletteHarness extends ConsumerWidget {
  const _PaletteHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    theme: FlyTheme.light(ref.watch(flyPaletteProvider)),
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
        width: 52,
        child: PrimaryNavigationRail(
          selectedModule: PrimaryModule.customers,
          onSelected: (_) {},
        ),
      ),
    ),
  );
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _dispose(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(Duration.zero);
}
