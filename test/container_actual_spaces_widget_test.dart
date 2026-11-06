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
import 'package:fly/features/tools/container_loading/presentation/scene/section_placement_editor.dart';
import 'package:fly/features/tools/container_loading/domain/models/section_models.dart';
import 'package:fly/features/tools/container_loading/presentation/workspace/container_loading_page.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/design_system/app_theme.dart';

import 'container_actual_spaces_test.dart' as f;

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'manual PVC spaces stay visible and target selection fills the actual box dark=$dark',
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
            await File(
              'build/container-spaces-$name-${dark ? 'dark' : 'light'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
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
          final g = editor.scene.groups.single;
          editor.scene.resizeGroup(g.id, rows: 8, layers: 10);
          editor.focusSection(id);
          await settle();
          final top = editor
              .spacesFor(id)
              .singleWhere((s) => s.bounds.z == 1000);
          expect(
            find.byKey(ValueKey('loading-space-${top.id}')),
            findsOneWidget,
          );
          expect(find.text('2900 × 2000 × 1690 mm'), findsOneWidget);
          expect(find.textContaining('200 × 2690 mm'), findsOneWidget);
          expect(
            tester
                .widget<SectionPlacementEditor>(
                  find.byType(SectionPlacementEditor),
                )
                .spaces
                .map((s) => s.id),
            contains(top.id),
          );
          editor.scene.select(null);
          await settle();
          await capture('80-overhead');
          final manual = find.byKey(ValueKey('manual-${g.id}'));
          final rows = find
              .descendant(of: manual, matching: find.byType(TextField))
              .first;
          await tester.ensureVisible(rows);
          await settle();
          await tester.enterText(rows, '6');
          FocusManager.instance.primaryFocus?.unfocus();
          await settle();
          expect(editor.scene.groups.single.quantity, 60);
          final side = editor.spacesFor(id).singleWhere((s) => s.bounds.z == 0);
          expect(side.bounds.dimensions.widthMm, 700);
          expect(
            find.byKey(ValueKey('loading-space-${side.id}')),
            findsOneWidget,
          );
          await tester.ensureVisible(find.byType(SectionPlacementEditor));
          editor.scene.select(null);
          await settle();
          await capture('60-two-spaces');
          final currentTop = editor
              .spacesFor(id)
              .singleWhere((s) => s.bounds.z == 1000);
          final shownTop = LoadingSpace.suggested(
            editor.spacesFor(id),
            [],
          ).singleWhere((s) => s.id == currentTop.id);
          final chooser = find.byTooltip('为${shownTop.name}选择货物');
          await tester.ensureVisible(chooser);
          await settle();
          await tester.tap(chooser);
          await settle();
          await tester.tap(find.text('WPC').last);
          await settle();
          expect(
            editor.scene.groups
                .singleWhere((b) => b.cargoPackageId == f.small.id)
                .positionZmm,
            1000,
          );
          expect(
            editor.scene.groups.singleWhere((b) => b.id == g.id).quantity,
            60,
          );
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
