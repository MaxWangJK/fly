import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:fly/app/app.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/features/tools/container_loading/domain/models/container_loading_models.dart';
import 'package:fly/features/tools/container_loading/domain/models/section_models.dart';
import 'package:fly/features/tools/container_loading/presentation/container_loading_providers.dart';
import 'package:fly/features/tools/container_loading/presentation/scene/cargo_box_geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'container_loading_v6_test.dart' as v6;

void main() {
  test('cargo_box_all_faces_visible across orbit above and below', () {
    expect(cargoBoxFaces, hasLength(6));
    expect(cargoBoxFaces.fold(0, (n, f) => n + f.length - 2), 12);
    final faces = <String>{};
    for (final yaw in [-math.pi, -math.pi / 2, 0.0, math.pi / 2]) {
      for (final pitch in [-.4, .4]) {
        faces.addAll(visibleCargoBoxFaces(yaw, pitch).map((f) => f.join(',')));
      }
    }
    expect(faces, hasLength(6));
  });
  testWidgets(
    'V2 pallet autopack, section boundaries and labels render acceptance scenes',
    (tester) async {
      const capture = bool.fromEnvironment('FLY_UPDATE_SCREENSHOTS');
      if (capture) await tester.runAsync(_loadFonts);
      tester.view.physicalSize = const Size(1700, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      await db.ensureBuiltInData();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(key: key, child: const FlyApp()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('primary-tools')));
      await tester.pumpAndSettle();
      final editor = container.read(loadingEditorProvider);
      final cargo = container.read(cargoLibraryProvider).requireValue;
      final wpc = cargo.firstWhere((c) => c.id == 'cargo-wpc-grille');
      Future<void> shot(String name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (capture) {
          await tester.runAsync(
            () => _capture(
              key,
              'docs/screenshots/container_loading_v6/$name.png',
            ),
          );
        }
      }

      await shot('40hq_sections');
      editor.addCargo(editor.sections.first.id, wpc);
      editor.pack(editor.sections.first.id);
      await shot('wpc_286');
      editor.updateEntry(editor.entries.single.copyWith(quantity: 100));
      editor.pack(editor.sections.first.id);
      await shot('wpc_100_actual_height');
      editor.updateEntry(editor.entries.single.copyWith(quantity: 180));
      editor.pack(editor.sections.first.id);
      expect(editor.packedCount, 180);
      await shot('rows_180_first_section');
      editor.updateEntry(editor.entries.single.copyWith(quantity: 300));
      editor.pack(editor.sections.first.id);
      expect(editor.packedCount, 286);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('review-unpacked')));
      await shot('overflow_review');
      await tester.tap(find.text('确认保留未装数量'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await shot('overflow_confirmed');
      editor.updateEntry(editor.entries.single.copyWith(quantity: 286));
      editor.pack(editor.sections.first.id);
      for (final s in editor.sections.skip(1)) {
        editor.addCargo(s.id, wpc);
        editor.pack(s.id);
      }
      editor.scene.focusSection(null);
      await shot('wpc_1144');
      editor.choosePreset(editor.preset);
      const pallet = CargoPackageModel(
        id: 'v2-pallet',
        name: 'Bamboo Panel 托盘',
        type: CargoPackageType.pallet,
        dimensions: Dimensions3(2800, 1200, 1000),
        weightGrams: 800000,
        colorValue: 0xFF7FA7C9,
      );
      const shortWpc = CargoPackageModel(
        id: 'v2-wpc',
        name: 'WPC02 · 280cm',
        dimensions: Dimensions3(2800, 160, 120),
        weightGrams: 18000,
        colorValue: 0xFF79A88C,
      );
      editor.addCargo(editor.sections.first.id, pallet);
      editor.updateEntry(
        editor.entries.single.copyWith(
          quantity: 2,
          allowStack: true,
          horizontalPlacement: HorizontalPlacement.center,
        ),
      );
      editor.addCargo(
        editor.sections.first.id,
        shortWpc,
        spaceId: editor.spacesFor(editor.sections.first.id).first.id,
      );
      editor.updateEntry(editor.entries.last.copyWith(quantity: 150));
      editor.pack(editor.sections.first.id);
      await shot('pallet_center_stack_mixed');
      editor.updateEntry(
        editor.entries.first.copyWith(
          quantity: 1,
          horizontalPlacement: HorizontalPlacement.left,
        ),
      );
      editor.pack(editor.sections.first.id);
      await shot('pallet_left_mixed');
      editor.scene.select(editor.scene.groups.first.id);
      await shot('manual_adjustment');
      const pvc = CargoPackageModel(
        id: 'v3-pvc',
        name: 'PVC ceiling',
        dimensions: Dimensions3(2900, 160, 160),
        weightGrams: 2000,
        colorValue: 0xFF79A88C,
      );
      for (final alignment in [
        HorizontalPlacement.left,
        HorizontalPlacement.center,
        HorizontalPlacement.right,
      ]) {
        editor.choosePreset(editor.preset);
        final third = editor.sections[2];
        for (final s in editor.sections.where((s) => s.id != third.id)) {
          editor.addCargo(s.id, wpc);
          editor.pack(s.id);
        }
        editor.addCargo(third.id, pallet);
        editor.updateEntry(
          editor.entries.last.copyWith(
            quantity: 2,
            allowStack: true,
            horizontalPlacement: alignment,
          ),
        );
        for (final space in editor.spacesFor(third.id)) {
          editor.addCargo(third.id, pvc, spaceId: space.id);
        }
        editor.pack(third.id);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('section-drop-2')),
        );
        await shot('v3_third_section_${alignment.name}');
      }
      editor.choosePreset(editor.preset);
      final partialSection = editor.sections.first.id;
      editor.addCargo(partialSection, pallet);
      editor.updateEntry(
        editor.entries.single.copyWith(
          quantity: 1,
          horizontalPlacement: HorizontalPlacement.left,
        ),
      );
      final initialSpaces = editor.spacesFor(partialSection);
      editor.addCargo(partialSection, wpc, spaceId: initialSpaces[0].id);
      editor.updateEntry(
        editor.entries.last.copyWith(perRow: 4, rowCount: 18, quantity: 72),
      );
      editor.addCargo(partialSection, pvc, spaceId: initialSpaces[1].id);
      editor.updateEntry(
        editor.entries.last.copyWith(perRow: 4, rowCount: 8, quantity: 32),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('section-drop-0')));
      await shot('v5_partial_grid_colors');
      final extra = editor
          .spacesFor(partialSection)
          .firstWhere(
            (s) => s.parentId == initialSpaces[0].id && s.name.contains('上方'),
          );
      // Space labels are now A/B zones; stable identity is independent of copy.
      await tester.ensureVisible(
        find.byKey(ValueKey('loading-space-${extra.id}')),
      );
      await shot('v5_remaining_spaces');
      editor.addCargo(partialSection, pvc, spaceId: extra.id);
      editor.updateEntry(
        editor.entries.last.copyWith(perRow: 2, rowCount: 1, quantity: 2),
      );
      await shot('v5_recursive_fill');
      editor.choosePreset(editor.preset);
      final fullSection = editor.sections.first.id;
      editor.addCargo(fullSection, v6.pallet);
      editor.updateEntry(
        editor.entries.single.copyWith(
          quantity: 1,
          horizontalPlacement: HorizontalPlacement.left,
        ),
      );
      final fullSpaces = editor.spacesFor(fullSection);
      editor.addCargo(fullSection, v6.pvc, spaceId: fullSpaces[0].id);
      editor.updateEntry(
        editor.entries.last.copyWith(perRow: 4, rowCount: 26, quantity: 104),
      );
      editor.addCargo(fullSection, wpc, spaceId: fullSpaces[1].id);
      editor.updateEntry(
        editor.entries.last.copyWith(perRow: 7, rowCount: 15, quantity: 105),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('section-drop-0')));
      expect(editor.packedCount, 210);
      for (final s
          in editor.spacesFor(fullSection).where((s) => s.parentId != null)) {
        expect(find.byKey(ValueKey('loading-space-${s.id}')), findsNothing);
      }
      await shot('v6_recommended_grids_no_small_spaces');
      editor.choosePreset(editor.preset);
      editor.setSections([800, 2900, 2900, 2900]);
      const door = CargoPackageModel(
        id: 'door',
        name: 'Door01',
        type: CargoPackageType.door,
        dimensions: Dimensions3(2000, 800, 43),
        weightGrams: 25000,
        colorValue: 0xFFD8A06B,
      );
      editor.addCargo(editor.sections.first.id, door);
      editor.updateEntry(editor.entries.single.copyWith(quantity: 51));
      editor.pack(editor.sections.first.id);
      await shot('door_51_upright');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );
}

Future<void> _loadFonts() async {
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

Future<void> _capture(GlobalKey key, String path) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) throw StateError('PNG encode failed');
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes.buffer.asUint8List());
}
