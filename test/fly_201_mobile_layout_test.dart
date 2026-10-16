import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/app/app.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('phone navigation, agenda, quadrants and settings at $size', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      final today = DateTime.now();
      await tester.runAsync(() async {
        await db.ensureBuiltInData();
        await DriftTaskRepository(db)
            .createTask(title: 'Synthetic mobile agenda task', dueDate: today);
        for (final f in {
          'Microsoft YaHei UI': 'C:/Windows/Fonts/msyh.ttc',
          'MaterialIcons': 'D:/ProgramData/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        }.entries) {
          if (await File(f.value).exists()) {
            await (FontLoader(f.key)..addFont(
                  Future.value(
                    ByteData.sublistView(await File(f.value).readAsBytes()),
                  ),
                ))
                .load();
          }
        }
      });
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      final boundary = GlobalKey();
      Future<void> settle() async {
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> capture(String name) async {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('build/fly201-$name-${size.width.toInt()}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }

      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(key: boundary, child: const FlyApp()),
          ),
        );
        await settle();
        container.read(appRouterProvider).go('/tasks/today');
        await settle();
        expect(
          find.byKey(const ValueKey('compact-navigation')),
          findsOneWidget,
        );
        expect(find.byType(NavigationDestination), findsNWidgets(5));
        expect(
          find.byKey(const ValueKey('task-view-calendar')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('task-view-calendar')));
        await settle();
        expect(find.byKey(const ValueKey('phone-calendar')), findsOneWidget);
        expect(find.text('Synthetic mobile agenda task'), findsOneWidget);
        await capture('calendar');
        await tester.ensureVisible(
          find.byKey(const ValueKey('task-view-matrix')),
        );
        await tester.tap(find.byKey(const ValueKey('task-view-matrix')));
        await settle();
        await capture('matrix');
        expect(tester.takeException(), isNull);
        await tester.tap(find.byIcon(Icons.add).first);
        await settle();
        await tester.enterText(
          find.byType(TextField).first,
          'New quadrant task',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await settle();
        expect(find.text('New quadrant task'), findsOneWidget);
        container.read(appRouterProvider).go('/me');
        await settle();
        await tester.tap(find.byKey(const ValueKey('my-settings')));
        await settle();
        expect(
          find.byKey(const ValueKey('settings-category-selector')),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('settings-category-1')));
        await settle();
        expect(find.text('显示模式'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('settings-back')));
        await settle();
        await tester.scrollUntilVisible(
          find.descendant(
            of: find.byKey(const ValueKey('settings-center')),
            matching: find.text('同步'),
          ),
          160,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('settings-center')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('settings-center')),
            matching: find.text('同步'),
          ),
        );
        await settle();
        expect(find.byKey(const ValueKey('sync-mode-cloud')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('sync-mode-lan')));
        await settle();
        expect(find.byKey(const ValueKey('scan-desktop-qr')), findsOneWidget);
        await capture('sync');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await settle();
        await tester.runAsync(db.close);
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
