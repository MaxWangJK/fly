import 'support/legacy_database_fixture.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/dashboard/data/dashboard_focus_repository.dart';
import 'package:fly/features/dashboard/domain/dashboard_focus.dart';
import 'package:fly/features/dashboard/presentation/dashboard_focus_board.dart';
import 'package:fly/features/dashboard/presentation/dashboard_page.dart';
import 'package:fly/features/tasks/presentation/task_focus_page.dart';
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
      expect(empty.monthlyFocus, isEmpty);
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
    'monthly focus persists independently and keeps replaced history',
    () async {
      final root = await Directory.systemTemp.createTemp('fly-monthly-focus-');
      final file = File(p.join(root.path, 'fly.db'));
      var db = AppDatabase(NativeDatabase(file));
      try {
        var repository = DashboardFocusRepository(db);
        await repository.save(
          type: DashboardFocusType.mainMission,
          content: '长期方向',
          day: oct6,
        );
        await repository.save(
          type: DashboardFocusType.weeklyFocus,
          content: '本周报价',
          day: oct6,
        );
        await repository.save(
          type: DashboardFocusType.monthlyFocus,
          content: '本月开发客户',
          day: oct6,
        );
        await repository.save(
          type: DashboardFocusType.monthlyFocus,
          content: '本月成交客户',
          day: oct7,
        );
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        repository = DashboardFocusRepository(db);
        final snapshot = await repository.read(oct7);
        expect(snapshot.mainMission, '长期方向');
        expect(snapshot.monthlyFocus, '本月成交客户');
        expect(snapshot.weeklyFocus, '本周报价');
        expect(
          (await repository.history())
              .where((entry) => entry.type == DashboardFocusType.monthlyFocus)
              .map((entry) => entry.content),
          ['本月开发客户'],
        );
      } finally {
        await db.close();
        await root.delete(recursive: true);
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
          expect(find.text('Monthly Focus'), findsOneWidget);
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
      expect(find.text('本月重点'), findsOneWidget);
      expect(find.text('点击这里写下你当前最重要的长期目标'), findsOneWidget);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('focus-section-mainMission')))
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('focus-section-monthlyFocus')),
              )
              .dy,
        ),
      );
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('focus-section-monthlyFocus')),
            )
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('focus-section-weeklyFocus')),
              )
              .dy,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('focus-content-mainMission')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('focus-editor-mainMission')),
        '建立稳定客户池',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('focus-editor-mainMission')),
        findsOneWidget,
      );
      expect((await DashboardFocusRepository(db).read(oct6)).mainMission, '');
      await tester.tap(find.byKey(const ValueKey('dashboard-focus-history')));
      await tester.pumpAndSettle();
      expect(
        (await DashboardFocusRepository(db).read(oct6)).mainMission,
        '建立稳定客户池',
      );
      await tester.tap(
        find.byKey(const ValueKey('focus-content-monthlyFocus')),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('focus-editor-monthlyFocus')),
        '本月新客户目标',
      );
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('focus-editor-monthlyFocus')),
          )
          .focusNode!
          .unfocus();
      await tester.pumpAndSettle();
      expect(
        (await DashboardFocusRepository(db).read(oct6)).monthlyFocus,
        '本月新客户目标',
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
      expect(find.text('Monthly Focus'), findsOneWidget);
      expect(find.text('本月新客户目标'), findsOneWidget);
      expect(
        find.text('Write your most important long-term goal'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );

  testWidgets('Focus fields grow and preserve multiline edits on blur', (
    tester,
  ) async {
    const capture = bool.fromEnvironment('FLY_CAPTURE_FOCUS_MOVE');
    if (capture) await tester.runAsync(_loadCaptureFonts);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    final outsideFocus = FocusNode();
    addTearDown(outsideFocus.dispose);
    for (final width in [900.0, 360.0]) {
      for (final dark in [false, true]) {
        tester.view.physicalSize = Size(width, 900);
        await _pumpBoard(
          tester,
          container,
          day: oct6,
          palette: FlyPaletteId.sageMist,
          dark: dark,
          locale: const Locale('zh', 'CN'),
        );
        for (final type in DashboardFocusType.values) {
          final content = find.byKey(ValueKey('focus-content-${type.name}'));
          await tester.ensureVisible(content);
          await tester.tap(content);
          await tester.pump();
          final editor = find.byKey(ValueKey('focus-editor-${type.name}'));
          await tester.enterText(editor, '短内容');
          await tester.pump();
          final shortHeight = tester.getSize(editor).height;
          final text = List.generate(
            8,
            (index) => '${index + 1}、${type.name}：逐步整理客户资料与本周计划。',
          ).join('\n');
          await tester.enterText(editor, text);
          await tester.pump();
          expect(tester.widget<TextField>(editor).maxLines, isNull);
          expect(tester.getSize(editor).height, greaterThan(shortHeight + 80));
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(editor, findsOneWidget);
          // Restore an exact multiline draft independently of platform key input.
          await tester.enterText(editor, text);
          FocusScope.of(tester.element(editor)).requestFocus(outsideFocus);
          await tester.pumpAndSettle();
          final snapshot = await DashboardFocusRepository(db).read(oct6);
          final saved = switch (type) {
            DashboardFocusType.mainMission => snapshot.mainMission,
            DashboardFocusType.monthlyFocus => snapshot.monthlyFocus,
            DashboardFocusType.weeklyFocus => snapshot.weeklyFocus,
            DashboardFocusType.todayFocus => snapshot.todayFocus,
          };
          expect(saved, text);
          final displayed = tester.widget<Text>(
            find.descendant(of: content, matching: find.byType(Text)),
          );
          expect(displayed.data, text);
          expect(displayed.maxLines, isNull);
          expect(displayed.overflow, isNull);
          expect(tester.takeException(), isNull);
        }
        if (capture) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byType(RepaintBoundary).first,
            );
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            image.dispose();
            final file = File(
              'build/visual/focus-multiline-${width.toInt()}-${dark ? 'dark' : 'light'}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          });
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets(
    'Task Focus keeps editing and history; Dashboard shows priorities',
    (tester) async {
      const capture = bool.fromEnvironment('FLY_CAPTURE_FOCUS_MOVE');
      if (capture) await tester.runAsync(_loadCaptureFonts);
      final focusBoundary = GlobalKey();
      final dashboardBoundary = GlobalKey();
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
      await repository.save(
        type: DashboardFocusType.monthlyFocus,
        content: 'Old monthly focus',
        day: oct6,
      );
      await repository.save(
        type: DashboardFocusType.monthlyFocus,
        content: 'New monthly focus',
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
            home: RepaintBoundary(
              key: focusBoundary,
              child: const TaskFocusPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('New mission'), findsOneWidget);
      expect(find.text('Monthly Focus'), findsOneWidget);
      expect(find.text('New monthly focus'), findsOneWidget);
      expect(find.text('Current work overview'), findsNothing);
      if (capture) {
        await tester.runAsync(
          () => _captureScreen(focusBoundary, 'build/visual/task-focus.png'),
        );
      }
      await tester.tap(find.byKey(const ValueKey('dashboard-focus-history')));
      await tester.pumpAndSettle();
      expect(find.text('Focus history'), findsOneWidget);
      expect(find.text('Old mission'), findsOneWidget);
      expect(find.text('Old monthly focus'), findsOneWidget);
      expect(find.text('New mission'), findsOneWidget);
      await tester.tap(find.byTooltip('Close history'));
      await tester.pumpAndSettle();
      expect(find.text('Focus history'), findsNothing);
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
            home: RepaintBoundary(
              key: dashboardBoundary,
              child: const DashboardPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Current work overview'), findsOneWidget);
      expect(find.text('Important & urgent'), findsOneWidget);
      expect(find.text('My Focus'), findsNothing);
      expect(find.text('New mission'), findsNothing);
      if (capture) {
        await tester.runAsync(
          () => _captureScreen(dashboardBoundary, 'build/visual/dashboard.png'),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      for (var index = 0; index < 12; index++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    },
  );

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
    expect(find.text('本月重点'), findsOneWidget);
    expect(find.text('本周重点'), findsOneWidget);
    expect(find.text('今日提醒'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: FlyTheme.light(FlyPaletteId.mintCloud),
          locale: const Locale('zh', 'CN'),
          supportedLocales: FlyLocalizations.supportedLocales,
          localizationsDelegates: const [
            FlyLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const TaskFocusPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('我的聚焦'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: FlyTheme.light(FlyPaletteId.mintCloud),
          locale: const Locale('zh', 'CN'),
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
    expect(find.text('当前工作分布'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    for (var index = 0; index < 12; index++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });

  test(
    'schema 15 to 17 adds Focus and Knowledge without replacing business data',
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
        await removeSyncSchema(db);
        for (final table in [
          'knowledge_favorites',
          'dashboard_focus_histories',
          'dashboard_daily_focuses',
          'dashboard_focuses',
        ]) {
          await db.customStatement('DROP TABLE $table');
        }
        await db.customStatement(
          'ALTER TABLE workspace_notes DROP COLUMN linked_knowledge_article_id',
        );
        await db.customStatement('PRAGMA user_version=15');
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        expect(db.schemaVersion, 18);
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

Future<void> _captureScreen(GlobalKey key, String path) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) throw StateError('Unable to capture $path');
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
}

Future<void> _loadCaptureFonts() async {
  Future<void> load(String family, String path) async {
    final bytes = await File(path).readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  await load('Microsoft YaHei UI', r'C:\Windows\Fonts\msyh.ttc');
  await load(
    'MaterialIcons',
    r'D:\ProgramData\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
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
