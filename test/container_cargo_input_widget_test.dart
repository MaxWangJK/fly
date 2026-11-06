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
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/features/tools/container_loading/presentation/container_loading_providers.dart';
import 'package:fly/features/tools/container_loading/presentation/workspace/container_loading_page.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/design_system/app_theme.dart';

import 'container_actual_spaces_test.dart' as f;

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'cleared input and visible remove buttons update only their cargo group dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = dark ? 1.3 : 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final db = AppDatabase(NativeDatabase.memory());
        final container = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)],
        );
        final key = GlobalKey();
        Future<void> settle() async {
          for (var i = 0; i < 6; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 15)),
            );
            await tester.pump(const Duration(milliseconds: 60));
          }
        }

        Future<void> capture(String name) async => tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('build/cargo-input-$name-${dark ? 'dark' : 'light'}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
        try {
          await tester.runAsync(() async {
            await db.ensureBuiltInData();
            final repo = container.read(containerLoadingRepositoryProvider);
            await repo.saveCargo(f.pvc);
            await repo.saveCargo(f.small);
            for (final item in {
              'Ahem': 'C:/Windows/Fonts/msyh.ttc',
              'Microsoft YaHei UI': 'C:/Windows/Fonts/msyh.ttc',
              'MaterialIcons': 'D:/ProgramData/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            }.entries) {
              if (await File(item.value).exists()) {
                await (FontLoader(item.key)..addFont(
                      Future.value(
                        ByteData.sublistView(
                          await File(item.value).readAsBytes(),
                        ),
                      ),
                    ))
                    .load();
              }
            }
          });
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: RepaintBoundary(
                key: key,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: const Locale('zh'),
                  supportedLocales: FlyLocalizations.supportedLocales,
                  localizationsDelegates: const [
                    FlyLocalizationsDelegate(),
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  theme: dark ? FlyTheme.dark() : FlyTheme.light(),
                  home: const Scaffold(body: ContainerLoadingPage()),
                ),
              ),
            ),
          );
          await settle();
          final editor = container.read(loadingEditorProvider);
          final id = editor.sections.first.id;
          editor.addCargo(id, f.pvc);
          final first = editor.scene.groups.single;
          editor.scene.resizeGroup(first.id, rows: 8, layers: 10);
          final top = editor
              .spacesFor(id)
              .firstWhere((s) => s.bounds.z == 1000);
          final secondEntry = editor.addCargo(id, f.pvc, spaceId: top.id);
          final second = editor.scene.groups.last;
          editor.scene.resizeGroup(second.id, rows: 8, layers: 2);
          editor.focusSection(id);
          await settle();
          final rows = find.byKey(ValueKey('manual-rows-${second.id}'));
          final layers = find.byKey(ValueKey('manual-layers-${second.id}'));
          await tester.ensureVisible(rows);
          await settle();
          await tester.enterText(rows, '');
          await settle();
          expect((editor.packedCount, editor.requestedCount), (80, 80));
          expect(editor.scene.loadedGroups.map((g) => g.id), [first.id]);
          expect(
            editor.entries.singleWhere((e) => e.id == secondEntry).quantity,
            0,
          );
          expect(rows, findsOneWidget);
          expect(tester.widget<TextField>(rows).controller!.text, '');
          await tester.enterText(layers, '');
          FocusManager.instance.primaryFocus?.unfocus();
          await settle();
          expect(find.textContaining('当前按0件计算'), findsOneWidget);
          editor.scene.select(null);
          await tester.ensureVisible(
            find.byKey(ValueKey('manual-${first.id}')),
          );
          await settle();
          await capture('cleared');
          await tester.ensureVisible(rows);
          await settle();
          await tester.enterText(rows, '4');
          await settle();
          expect(editor.packedCount, 80);
          await tester.enterText(layers, '1');
          FocusManager.instance.primaryFocus?.unfocus();
          await settle();
          expect(editor.packedCount, 84);
          expect(
            editor.scene.groups.firstWhere((g) => g.id == first.id).quantity,
            80,
          );
          final remove = find.byKey(ValueKey('remove-manual-${second.id}'));
          await tester.ensureVisible(remove);
          await settle();
          await tester.tap(remove);
          await settle();
          expect(editor.scene.groups.map((g) => g.id), [first.id]);
          expect(find.byKey(ValueKey('manual-${second.id}')), findsNothing);
          expect(editor.packedCount, 80);
          editor.scene.undo();
          await settle();
          expect(tester.widget<TextField>(rows).controller!.text, '4');
          expect(tester.widget<TextField>(layers).controller!.text, '1');
          expect(editor.packedCount, 84);
          editor.scene.redo();
          await settle();
          editor.scene.select(null);
          await tester.ensureVisible(
            find.byKey(ValueKey('manual-${first.id}')),
          );
          await settle();
          await capture('removed');
          final removeFirst = find.byKey(ValueKey('remove-manual-${first.id}'));
          await tester.ensureVisible(removeFirst);
          await settle();
          await tester.tap(removeFirst);
          await settle();
          expect((editor.packedCount, editor.requestedCount), (0, 0));
          await tester.runAsync(() => editor.save('Both removed'));
          final presets = (await tester.runAsync(
            () => container
                .read(containerLoadingRepositoryProvider)
                .watchPresets()
                .first,
          ))!;
          await tester.runAsync(() => editor.open(editor.plan!.id, presets));
          await settle();
          expect(editor.scene.loadedGroups, isEmpty);
          expect(editor.requestedCount, 0);
          expect(
            container
                .read(cargoLibraryProvider)
                .requireValue
                .any((c) => c.id == f.pvc.id),
            isTrue,
          );
          editor.choosePreset(editor.preset);
          final section = editor.sections.first.id;
          final automatic = editor.addCargo(section, f.pvc);
          await settle();
          final autoRows = find.byKey(ValueKey('per-row-$automatic'));
          await tester.ensureVisible(autoRows);
          await settle();
          await tester.enterText(autoRows, '');
          await settle();
          expect(editor.packedCount, 0);
          expect(editor.entries.single.quantity, 0);
          final autoLayers = find.byKey(ValueKey('row-count-$automatic'));
          await tester.enterText(autoRows, '4');
          await tester.enterText(autoLayers, '1');
          FocusManager.instance.primaryFocus?.unfocus();
          await settle();
          expect(editor.packedCount, 4);
          final autoRemove = find.byKey(ValueKey('remove-entry-$automatic'));
          await tester.ensureVisible(autoRemove);
          await settle();
          await tester.tap(autoRemove);
          await settle();
          expect(editor.entries, isEmpty);
          expect(editor.scene.loadedGroups, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
          await settle();
          await tester.runAsync(db.close);
        }
      },
    );
  }
}
