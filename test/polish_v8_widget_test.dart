import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:fly/app/app.dart';
import 'package:fly/app/settings/navigation_settings.dart';
import 'package:fly/app/settings/settings_center.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  for (final flags in [
    const NavigationSettings(),
    const NavigationSettings(dashboardVisible: false),
    const NavigationSettings(dashboardVisible: false, crmVisible: false),
    const NavigationSettings(crmVisible: false),
  ]) {
    testWidgets(
      'V8 cold launch ${flags.dashboardVisible}/${flags.crmVisible} and hidden-route guards',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = AppDatabase(NativeDatabase.memory());
        await tester.runAsync(() async {
          await db.ensureBuiltInData();
          final nav = NavigationSettingsController(db);
          await nav.ready;
          await nav.update(flags);
          nav.dispose();
        });
        final container = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const FlyApp(),
          ),
        );
        await settle(tester);
        final router = container.read(appRouterProvider);
        expect(
          router.routeInformationProvider.value.uri.path,
          StartupWorkspaceResolver.resolve(flags),
        );
        expect(
          find.byKey(const ValueKey('primary-dashboard')),
          flags.dashboardVisible ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('primary-customers')),
          flags.crmVisible ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('primary-orders')),
          flags.crmVisible ? findsOneWidget : findsNothing,
        );
        if (!flags.crmVisible) {
          router.go('/orders/all');
          await settle(tester);
          expect(
            router.routeInformationProvider.value.uri.path,
            StartupWorkspaceResolver.resolve(flags),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await tester.pump(Duration.zero);
        addTearDown(db.close);
      },
    );
  }
  testWidgets(
    'V8 settings categories, instant fallback, themes, narrow mode and Matrix time',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const capture = bool.fromEnvironment('FLY_UPDATE_SCREENSHOTS');
      if (capture) {
        await tester.runAsync(() async {
          final loader = FontLoader('Microsoft YaHei UI')
            ..addFont(
              Future.value(
                ByteData.sublistView(
                  await File(r'C:\Windows\Fonts\msyh.ttc').readAsBytes(),
                ),
              ),
            );
          await loader.load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(
              Future.value(
                ByteData.sublistView(
                  await File(
                    r'D:\ProgramData\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
                  ).readAsBytes(),
                ),
              ),
            );
          await icons.load();
        });
      }
      final db = AppDatabase(NativeDatabase.memory());
      await db.ensureBuiltInData();
      final repo = DriftTaskRepository(db);
      final task = await repo.createTask(
        title: '跟进客户报价与样品反馈',
        importance: true,
        urgency: true,
      );
      final today = DateTime.now();
      await repo.saveTask(
        task.copyWith(
          createdAt: DateTime(today.year, today.month, today.day, 14, 30),
        ),
      );
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      final boundary = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(key: boundary, child: const FlyApp()),
        ),
      );
      await settle(tester);
      Future<void> shot(String name) async {
        if (!capture) return;
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final file = File('docs/screenshots/polish_v8/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        });
      }

      await tester.tap(find.byKey(const ValueKey('primary-settings')));
      await settle(tester);
      for (var i = 0; i < 8; i++) {
        await tester.tap(find.byKey(ValueKey('settings-category-$i')));
        await settle(tester);
        expect(find.byKey(ValueKey('settings-content-$i')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byKey(const ValueKey('settings-category-2')));
      await settle(tester);
      await shot('settings_navigation');
      await tester.tap(find.byKey(const ValueKey('dashboard-visible')));
      await settle(tester);
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/customers/today',
      );
      expect(find.byKey(const ValueKey('primary-dashboard')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('crm-visible')));
      await settle(tester);
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/tasks/today',
      );
      expect(find.byType(SettingsCenter), findsOneWidget);
      container.read(themeModeProvider.notifier).state = ThemeMode.dark;
      await settle(tester);
      expect(
        Theme.of(tester.element(find.byType(SettingsCenter))).brightness,
        Brightness.dark,
      );
      await shot('settings_dark');
      tester.view.physicalSize = const Size(600, 800);
      await settle(tester);
      expect(
        find.byKey(const ValueKey('settings-category-selector')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await shot('settings_narrow');
      await tester.tap(find.byTooltip('关闭设置'));
      tester.view.physicalSize = const Size(1400, 900);
      container.read(themeModeProvider.notifier).state = ThemeMode.light;
      container.read(appRouterProvider).go('/matrix');
      await settle(tester);
      expect(find.text('今天 14:30'), findsOneWidget);
      await shot('matrix_created_time');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pump(Duration.zero);
      addTearDown(db.close);
    },
  );
}
