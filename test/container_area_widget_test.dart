import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/features/tools/container_loading/domain/models/container_loading_models.dart';
import 'package:fly/features/tools/container_loading/presentation/container_loading_providers.dart';
import 'package:fly/features/tools/container_loading/presentation/scene/container_scene_controller.dart';
import 'package:fly/features/tools/container_loading/presentation/scene/container_scene_view.dart';
import 'package:fly/features/tools/container_loading/presentation/scene/section_placement_editor.dart';
import 'package:fly/features/tools/container_loading/presentation/workspace/container_loading_page.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/design_system/app_theme.dart';

import 'container_actual_spaces_test.dart' as f;
import 'container_area_workflow_test.dart' as a;

Widget app(Widget child, {bool dark = false, String locale = 'zh'}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(locale),
      supportedLocales: FlyLocalizations.supportedLocales,
      localizationsDelegates: const [
        FlyLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: dark ? FlyTheme.dark() : FlyTheme.light(),
      home: Scaffold(body: child),
    );

// Front projection used to click actual cargo/space geometry, not a test-only
// hit target; keep in sync with its public container dimensions and viewport.
Offset frontPoint(WidgetTester tester, int y, int z) {
  final rect = tester.getRect(find.byType(SectionPlacementEditor));
  final scale = math.min((rect.width - 48) / 2200, (rect.height - 44) / 2690);
  return rect.topLeft +
      Offset(
        (rect.width - 2200 * scale) / 2 + y * scale,
        rect.height - 24 - z * scale,
      );
}

Future<void> rightClick(WidgetTester tester, Offset point) async {
  await tester.tapAt(point, buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle();
}

void main() {
  for (final axis in ['X', 'Y', 'Z']) {
    testWidgets(
      'section menu rotates clicked cargo around $axis and Undo restores it',
      (tester) async {
        final group = f
            .block(x: 0, y: 0, z: 0)
            .copyWith(
              quantity: 1,
              rows: 1,
              columns: 1,
              layers: 1,
              boundingDimensions: const Dimensions3(1000, 600, 400),
            );
        final other = group.copyWith(id: 'other', positionYmm: 1300);
        final scene = NativeContainerSceneController(
          initialGroups: [group, other],
        );
        try {
          await tester.pumpWidget(
            app(
              Center(
                child: SizedBox(
                  width: 320,
                  height: 240,
                  child: SectionPlacementEditor(
                    controller: scene,
                    sectionId: 'section',
                    names: const {},
                  ),
                ),
              ),
            ),
          );
          scene.select(other.id);
          await rightClick(tester, frontPoint(tester, 300, 200));
          expect(scene.selectedGroupId, group.id);
          await tester.tap(find.text('绕 $axis 旋转 90°'));
          await tester.pumpAndSettle();
          final rotated = scene.groups.first;
          expect(switch (axis) {
            'X' => rotated.rotationX,
            'Y' => rotated.rotationY,
            _ => rotated.rotationZ,
          }, 90);
          expect(rotated.boundingDimensions, switch (axis) {
            'X' => const Dimensions3(1000, 400, 600),
            'Y' => const Dimensions3(400, 600, 1000),
            _ => const Dimensions3(600, 1000, 400),
          });
          expect(scene.groups.last, same(other));
          scene.undo();
          expect(
            scene.groups.first.boundingDimensions,
            group.boundingDimensions,
          );
          scene.redo();
          expect(
            scene.groups.first.boundingDimensions,
            rotated.boundingDimensions,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          scene.dispose();
        }
      },
    );
  }
  testWidgets(
    'section rejects invalid rotation and blank right click cannot delete a prior selection',
    (tester) async {
      final group = f.block(x: 0);
      final scene = NativeContainerSceneController(initialGroups: [group]);
      try {
        await tester.pumpWidget(
          app(
            Center(
              child: SizedBox(
                width: 320,
                height: 240,
                child: SectionPlacementEditor(
                  controller: scene,
                  sectionId: 'section',
                  names: const {},
                ),
              ),
            ),
          ),
        );
        scene.select(group.id);
        await rightClick(
          tester,
          tester.getTopLeft(find.byType(SectionPlacementEditor)) +
              const Offset(4, 4),
        );
        expect(find.text('移除货物'), findsNothing);
        expect(scene.groups, hasLength(1));
        await rightClick(tester, frontPoint(tester, 1000, 500));
        await tester.tap(find.text('绕 Z 旋转 90°'));
        await tester.pumpAndSettle();
        expect(
          scene.groups.single.boundingDimensions,
          group.boundingDimensions,
        );
        expect(scene.invalidGroupId, group.id);
        expect(find.textContaining('旋转后会重叠'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        scene.dispose();
      }
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'area-only addition, 160+60 scene, right-click removal and Undo dark=$dark',
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
        final boundary = GlobalKey();
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
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('build/cargo-area-$name-${dark ? 'dark' : 'light'}.png')
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
            await repo.saveCargo(a.grille);
            for (final font in {
              'Ahem': 'C:/Windows/Fonts/msyh.ttc',
              'Microsoft YaHei UI': 'C:/Windows/Fonts/msyh.ttc',
              'MaterialIcons': 'D:/ProgramData/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            }.entries) {
              if (await File(font.value).exists()) {
                await (FontLoader(font.key)..addFont(
                      Future.value(
                        ByteData.sublistView(
                          await File(font.value).readAsBytes(),
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
                key: boundary,
                child: app(const ContainerLoadingPage(), dark: dark),
              ),
            ),
          );
          await settle();
          final editor = container.read(loadingEditorProvider);
          final sectionFinder = find.byKey(const ValueKey('section-drop-0'));
          final firstChooser = find.descendant(
            of: sectionFinder,
            matching: find.byTooltip('选择货物'),
          );
          await tester.ensureVisible(firstChooser);
          await tester.tap(firstChooser);
          await settle();
          await tester.tap(find.text('PVC ceiling').last);
          await settle();
          final first = editor.scene.groups.single;
          editor.scene.resizeGroup(first.id, rows: 6, layers: 20);
          await settle();
          expect(find.text('A区'), findsOneWidget);
          expect(find.text('B区'), findsOneWidget);
          await Scrollable.ensureVisible(
            tester.element(find.byType(SectionPlacementEditor)),
            alignment: .12,
          );
          await settle();
          await capture('areas');
          editor.scene.resizeGroup(first.id, rows: 8, layers: 20);
          await settle();
          expect(
            find.descendant(
              of: sectionFinder,
              matching: find.text('+ 选择货物 / 拖放到本节'),
            ),
            findsNothing,
          );
          final target = tester.widget<DragTarget<CargoPackageModel>>(
            sectionFinder,
          );
          expect(
            target.onWillAcceptWithDetails!(
              DragTargetDetails(data: a.grille, offset: Offset.zero),
            ),
            isFalse,
          );
          expect(find.text('A区'), findsOneWidget);
          await tester.ensureVisible(find.byType(SectionPlacementEditor));
          await settle();
          // Click the drawn A region (the same destination as its card).
          await tester.tapAt(frontPoint(tester, 1000, 2345));
          await settle();
          await tester.tap(find.text('WPC 格栅').last);
          await settle();
          final wpc = editor.scene.groups.last;
          editor.scene.resizeGroup(wpc.id, rows: 12, layers: 5);
          await settle();
          expect(editor.packedCount, 220);
          expect(editor.scene.groups.last.positionZmm, 2000);
          expect(
            editor.scene.loadedGroups.any(editor.scene.hasPlacementConflict),
            isFalse,
          );
          expect(
            tester
                .widget<ContainerSceneView>(find.byType(ContainerSceneView))
                .controller,
            same(editor.scene),
          );
          await tester.ensureVisible(find.byType(SectionPlacementEditor));
          editor.scene.select(null);
          await settle();
          await capture('loaded');
          await rightClick(tester, frontPoint(tester, 960, 2300));
          await settle();
          expect(editor.scene.selectedGroupId, wpc.id);
          await capture('menu');
          await tester.tap(find.widgetWithText(PopupMenuItem<String>, '移除货物'));
          await settle();
          expect(editor.packedCount, 160);
          expect(editor.scene.loadedGroups.single.id, first.id);
          expect(find.text('A区'), findsOneWidget);
          editor.scene.undo();
          await settle();
          expect(editor.packedCount, 220);
          editor.scene.redo();
          await settle();
          expect(editor.packedCount, 160);
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
