import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/dashboard/data/dashboard_focus_repository.dart';
import 'package:fly/features/dashboard/domain/dashboard_focus.dart';
import 'package:fly/features/dashboard/presentation/dashboard_focus_board.dart';
import 'package:fly/features/dashboard/presentation/dashboard_page.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/design_system/app_theme.dart';
import 'package:fly/shared/design_system/fly_color_scheme.dart';
import 'package:path/path.dart' as p;

void main() {
  final oct6 = DateTime(2026, 10, 6);
  final oct7 = DateTime(2026, 10, 7);

  test('dashboard_focus_create_test: placeholders are not persisted', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final repository = DashboardFocusRepository(db);
      final empty = await repository.read(oct6);
      expect(empty.mainMission, isEmpty);
      expect(empty.weeklyFocus, isEmpty);
      expect(empty.todayFocus, isEmpty);
      expect(await repository.history(), isEmpty);
      expect(
        await repository.save(
          type: DashboardFocusType.mainMission,
          content: 'Build a stable customer base',
          day: oct6,
        ),
        true,
      );
      expect(
        (await repository.read(oct6)).mainMission,
        'Build a stable customer base',
      );
      expect(await repository.history(), isEmpty);
    } finally {
      await db.close();
    }
  });

  test(
    'dashboard_focus_edit_test: only a changed committed value saves',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final repository = DashboardFocusRepository(db);
        await repository.save(
          type: DashboardFocusType.mainMission,
          content: 'A',
          day: oct6,
        );
        expect(
          await repository.save(
            type: DashboardFocusType.mainMission,
            content: 'B',
            day: oct6,
          ),
          true,
        );
        expect(
          await repository.save(
            type: DashboardFocusType.mainMission,
            content: ' B ',
            day: oct6,
          ),
          false,
        );
        expect((await repository.read(oct6)).mainMission, 'B');
        final history = await repository.history();
        expect(history, hasLength(1));
        expect(history.single.type, DashboardFocusType.mainMission);
        expect(history.single.content, 'A');
      } finally {
        await db.close();
      }
    },
  );

  test(
    'dashboard_focus_history_test: old weekly value enters history once',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final repository = DashboardFocusRepository(db);
        await repository.save(
          type: DashboardFocusType.weeklyFocus,
          content: 'Find Philippine distributors',
          day: oct6,
        );
        await repository.save(
          type: DashboardFocusType.weeklyFocus,
          content: 'Prepare new quotations',
          day: oct6,
        );
        expect(
          (await repository.read(oct7)).weeklyFocus,
          'Prepare new quotations',
        );
        expect(
          (await repository.history()).single.content,
          'Find Philippine distributors',
        );
      } finally {
        await db.close();
      }
    },
  );

  test(
    'dashboard_daily_focus_test: different days remain independent',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final repository = DashboardFocusRepository(db);
        await repository.save(
          type: DashboardFocusType.todayFocus,
          content: '开发15个客户',
          day: oct6,
        );
        await repository.save(
          type: DashboardFocusType.todayFocus,
          content: '完成客户报价',
          day: oct7,
        );
        expect((await repository.read(oct6)).todayFocus, '开发15个客户');
        expect((await repository.read(oct7)).todayFocus, '完成客户报价');
        expect(
          (await repository.history())
              .where((item) => item.type == DashboardFocusType.todayFocus)
              .map((item) => item.content),
          ['完成客户报价', '开发15个客户'],
        );
        await repository.save(
          type: DashboardFocusType.todayFocus,
          content: '完成两份客户报价',
          day: oct7,
        );
        expect(
          (await repository.history()).where(
            (item) => item.content == '完成客户报价',
          ),
          hasLength(1),
        );
      } finally {
        await db.close();
      }
    },
  );

  testWidgets(
    'dashboard_focus_theme_test: every palette supports light and dark',
    (tester) async {
      tester.view.physicalSize = const Size(900, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      for (final palette in FlyPaletteId.values) {
        for (final dark in [false, true]) {
          await _pumpBoard(
            tester,
            container,
            day: oct6,
            palette: palette,
            dark: dark,
          );
          expect(find.text('My Focus'), findsOneWidget);
          expect(find.text('Main Mission'), findsOneWidget);
          expect(find.text('Weekly Focus'), findsOneWidget);
          expect(find.text("Today's Focus"), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );

  testWidgets(
    'dashboard_focus_localization_test: inline edit, cancel and history',
    (tester) async {
      tester.view.physicalSize = const Size(900, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      await _pumpBoard(
        tester,
        container,
        day: oct6,
        palette: FlyPaletteId.flyDefault,
        locale: const Locale('zh', 'CN'),
      );
      expect(find.text('我的聚焦'), findsOneWidget);
      expect(find.text('点击这里写下你当前最重要的长期目标'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('focus-content-mainMission')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('focus-editor-mainMission')),
        '建立稳定客户池',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        (await DashboardFocusRepository(db).read(oct6)).mainMission,
        '建立稳定客户池',
      );
      await tester.tap(find.byKey(const ValueKey('focus-content-weeklyFocus')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('focus-editor-weeklyFocus')),
        '点击外部保存',
      );
      await tester.tap(find.byKey(const ValueKey('dashboard-focus-history')));
      await tester.pumpAndSettle();
      expect(
        (await DashboardFocusRepository(db).read(oct6)).weeklyFocus,
        '点击外部保存',
      );
      await tester.tap(find.byKey(const ValueKey('focus-content-weeklyFocus')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('focus-editor-weeklyFocus')),
        '不保存',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        (await DashboardFocusRepository(db).read(oct6)).weeklyFocus,
        '点击外部保存',
      );
      await tester.tap(find.byKey(const ValueKey('focus-content-todayFocus')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('focus-editor-todayFocus')),
        '今日行动',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        (await DashboardFocusRepository(db).read(oct6)).todayFocus,
        '今日行动',
      );
      await _pumpBoard(
        tester,
        container,
        day: oct6,
        palette: FlyPaletteId.flyDefault,
      );
      expect(find.text('My Focus'), findsOneWidget);
      expect(find.text('建立稳定客户池'), findsOneWidget);
      expect(
        find.text('Write your most important long-term goal'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );

  testWidgets('Dashboard history opens on the right without navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureBuiltInData();
    final repository = DashboardFocusRepository(db);
    await repository.save(
      type: DashboardFocusType.mainMission,
      content: 'Old mission',
      day: oct6,
    );
    await repository.save(
      type: DashboardFocusType.mainMission,
      content: 'New mission',
      day: oct6,
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localTodayProvider.overrideWith((ref) => oct6),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: FlyTheme.light(FlyPaletteId.mintCloud),
          locale: const Locale('en'),
          supportedLocales: FlyLocalizations.supportedLocales,
          localizationsDelegates: const [
            FlyLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const DashboardPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('New mission'), findsOneWidget);
    expect(find.text('Current work overview'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('dashboard-focus-history')));
    await tester.pumpAndSettle();
    expect(find.text('Focus history'), findsOneWidget);
    expect(find.text('Old mission'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    await tester.tap(find.byTooltip('Close history'));
    await tester.pumpAndSettle();
    expect(find.text('Focus history'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    for (var index = 0; index < 12; index++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });

  testWidgets('Focus Board stays readable in a narrow workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    await _pumpBoard(
      tester,
      container,
      day: oct6,
      palette: FlyPaletteId.mintCloud,
      locale: const Locale('zh', 'CN'),
    );
    expect(find.text('人生主线'), findsOneWidget);
    expect(find.text('本周重点'), findsOneWidget);
    expect(find.text('今日提醒'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  test(
    'schema 15 to 16 adds Focus tables without replacing business data',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'fly-focus-migration-',
      );
      final file = File(p.join(root.path, 'fly.db'));
      var db = AppDatabase(NativeDatabase(file));
      try {
        await db.ensureBuiltInData();
        await db.customStatement(
          "INSERT INTO app_settings (`key`, value, updated_at) VALUES ('focus-migration-marker', 'preserved', 1)",
        );
        for (final table in [
          'dashboard_focus_histories',
          'dashboard_daily_focuses',
          'dashboard_focuses',
        ]) {
          await db.customStatement('DROP TABLE $table');
        }
        await db.customStatement('PRAGMA user_version=15');
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        expect(db.schemaVersion, 16);
        expect(
          (await db
                  .customSelect(
                    "SELECT value FROM app_settings WHERE `key`='focus-migration-marker'",
                  )
                  .getSingle())
              .read<String>('value'),
          'preserved',
        );
        final repository = DashboardFocusRepository(db);
        await repository.save(
          type: DashboardFocusType.todayFocus,
          content: 'Ready',
          day: oct6,
        );
        expect((await repository.read(oct6)).todayFocus, 'Ready');
      } finally {
        await db.close();
        await root.delete(recursive: true);
      }
    },
  );
}

Future<void> _pumpBoard(
  WidgetTester tester,
  ProviderContainer container, {
  required DateTime day,
  required FlyPaletteId palette,
  bool dark = false,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: FlyTheme.light(palette),
        darkTheme: FlyTheme.dark(palette),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        locale: locale,
        supportedLocales: FlyLocalizations.supportedLocales,
        localizationsDelegates: const [
          FlyLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: DashboardFocusBoard(day: day, onHistory: () {}),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
