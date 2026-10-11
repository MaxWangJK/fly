import 'support/legacy_database_fixture.dart';

import 'dart:io';

import 'package:drift/native.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/tools/container_loading/data/container_loading_repository.dart';
import 'package:fly/features/tools/container_loading/domain/models/container_loading_models.dart';
import 'package:fly/features/tools/container_loading/domain/models/section_models.dart';
import 'package:fly/features/tools/container_loading/domain/packing/section_packing_engine.dart';
import 'package:fly/features/tools/container_loading/presentation/loading_editor_controller.dart';
import 'package:fly/features/tools/container_loading/presentation/scene/container_scene_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const box = Dimensions3(11900, 2200, 2690);
const wpc = CargoPackageModel(
  id: 'wpc',
  name: 'WPC01',
  dimensions: Dimensions3(2900, 160, 120),
  weightGrams: 18000,
  colorValue: 0xFF79A88C,
  defaultSectionQuantity: 286,
);
const pallet = CargoPackageModel(
  id: 'pallet',
  name: 'Bamboo',
  type: CargoPackageType.pallet,
  dimensions: Dimensions3(2800, 1200, 1000),
  weightGrams: 800000,
  colorValue: 0xFF7FA7C9,
);
const section = ContainerSection(
  id: 's1',
  planId: 'plan',
  index: 0,
  name: '第1节',
  startXmm: 0,
  lengthMm: 2900,
);
const engine = SectionPackingEngine();
SectionCargoEntry entry(
  CargoPackageModel cargo,
  int count, {
  String? id,
  bool stack = true,
  bool bottom = false,
  HorizontalPlacement position = HorizontalPlacement.automatic,
  PlacementOrientation orientation = PlacementOrientation.flat,
}) => SectionCargoEntry(
  id: id ?? cargo.id,
  sectionId: 's1',
  cargo: cargo,
  quantity: count,
  allowStack: stack,
  placeOnBottom: bottom,
  horizontalPlacement: position,
  orientation: orientation,
);
SectionPackingResult pack(
  List<SectionCargoEntry> entries, {
  ContainerSection s = section,
  int weight = 28000000,
  int clearance = 0,
}) => engine.pack(
  section: s,
  container: box,
  entries: entries,
  remainingPayloadGrams: weight,
  clearanceMm: clearance,
);
void valid(SectionPackingResult result, ContainerSection s) {
  for (final g in result.groups) {
    expect(g.bounds.inside(box), true);
    expect(g.positionXmm, greaterThanOrEqualTo(s.startXmm));
    expect(g.bounds.maxX, lessThanOrEqualTo(s.endXmm));
  }
  for (var i = 0; i < result.groups.length; i++) {
    for (var j = i + 1; j < result.groups.length; j++) {
      expect(
        result.groups[i].bounds.overlaps(result.groups[j].bounds),
        false,
        reason: '${result.groups[i].id} overlaps ${result.groups[j].id}',
      );
    }
  }
}

void main() {
  test('section_layout and length_validation preserve 300 mm in 40HQ', () {
    final sections = ContainerSection.defaults('p', 11900);
    expect(sections, hasLength(4));
    expect(sections.last.endXmm, 11600);
    expect(ContainerSection.defaults('p', 5800), hasLength(2));
    expect(ContainerSection.validate(sections, 11900), isNull);
    expect(
      ContainerSection.validate([section.copyWith(lengthMm: 0)], 11900),
      isNotNull,
    );
    expect(
      ContainerSection.validate([section.copyWith(lengthMm: 12200)], 11900),
      contains('超过'),
    );
  });
  test('section_wpc_grid 286 and partial 100 packages use actual height', () {
    final result = pack([entry(wpc, 286)]);
    expect(result.packedCount, 286);
    expect(result.groups.single.rows, 13);
    expect(result.groups.single.layers, 22);
    valid(result, section);
    final partial = pack([entry(wpc, 100)]);
    expect(partial.packedCount, 100);
    expect(
      partial.groups.map((g) => g.bounds.maxZ).reduce((a, b) => a > b ? a : b),
      960,
    );
    valid(partial, section);
    expect(pack([entry(wpc, 284)]).packedCount, 284);
  });
  test('section_pallet_edge and center preserve explicit placement', () {
    final left = pack([
      entry(
        pallet,
        1,
        bottom: true,
        stack: false,
        position: HorizontalPlacement.left,
      ),
    ]);
    expect(left.groups.single.positionYmm, 0);
    expect(left.groups.single.boundingDimensions, pallet.dimensions);
    valid(left, section);
    final center = pack([
      entry(pallet, 1, bottom: true, position: HorizontalPlacement.center),
    ]);
    expect(center.groups.single.positionYmm, 500);
    expect(center.groups.single.positionZmm, 0);
    valid(center, section);
  });
  test('section_pallet_stack two pallets share XY and total height 2000', () {
    final result = pack([
      entry(pallet, 2, bottom: true, position: HorizontalPlacement.center),
    ]);
    expect(result.packedCount, 2);
    expect(result.groups.single.layers, 2);
    expect(result.groups.single.positionYmm, 500);
    expect(result.groups.single.boundingDimensions.heightMm, 2000);
    valid(result, section);
    expect(pack([entry(pallet, 2, bottom: true, stack: false)]).packedCount, 1);
  });
  test('section_mixed_cargo fills left right and supported top spaces', () {
    const small = CargoPackageModel(
      id: 'small',
      name: 'WPC short',
      dimensions: Dimensions3(2800, 160, 120),
      weightGrams: 18000,
      colorValue: 0xFF79A88C,
    );
    final result = pack([
      entry(pallet, 2, bottom: true, position: HorizontalPlacement.center),
      entry(small, 180),
    ]);
    final pieces = result.groups
        .where((g) => g.cargoPackageId == 'small')
        .toList();
    expect(pieces.any((g) => g.positionYmm < 500), true);
    expect(pieces.any((g) => g.positionYmm >= 1700), true);
    expect(
      pieces.any(
        (g) =>
            g.positionZmm >= 2000 &&
            g.positionYmm >= 500 &&
            g.bounds.maxY <= 1700,
      ),
      true,
    );
    valid(result, section);
    final blocked = pack([
      entry(
        pallet,
        1,
        bottom: true,
        stack: false,
        position: HorizontalPlacement.left,
      ),
      entry(small, 200),
    ]);
    expect(
      blocked.groups
          .where((g) => g.cargoPackageId == 'small')
          .every((g) => g.positionYmm >= 1200),
      true,
    );
    valid(blocked, section);
  });
  test('door_upright 2000 x 800 x 43 maps to X800 Y43 Z2000', () {
    const door = CargoPackageModel(
      id: 'door',
      name: 'Door01',
      type: CargoPackageType.door,
      dimensions: Dimensions3(2000, 800, 43),
      weightGrams: 25000,
      colorValue: 0xFFD8A06B,
    );
    final s = section.copyWith(lengthMm: 800);
    final result = pack([
      entry(door, 51, orientation: PlacementOrientation.upright),
    ], s: s);
    expect(result.packedCount, 51);
    expect(
      result.groups.single.boundingDimensions,
      const Dimensions3(800, 2193, 2000),
    );
    valid(result, s);
  });
  test('section weight and clearance are hard constraints', () {
    final result = pack([entry(wpc, 286)], weight: 1800000);
    expect(result.packedCount, 100);
    expect(result.weightGrams, 1800000);
    expect(pack([entry(wpc, 286)], clearance: 10).packedCount, 286);
  });
  test('40 mm gaps fit exact section length and retain genuine overflow', () {
    expect(
      engine.theoreticalCapacity(
        section,
        box,
        entry(wpc, 200),
        clearanceMm: 40,
      ),
      286,
    );
    for (final count in [180, 187, 200]) {
      final result = pack([entry(wpc, count)], clearance: 40);
      expect(result.packedCount, count);
      expect(result.unpackedCount, 0);
      expect(result.groups.first.positionXmm, 0);
      valid(result, section);
    }
    expect(
      pack(
        [entry(wpc, 200)],
        s: section.copyWith(lengthMm: 2899),
        clearance: 40,
      ).packedCount,
      0,
    );
    final floorOnly = entry(wpc, 200, stack: false);
    expect(
      engine.theoreticalCapacity(section, box, floorOnly, clearanceMm: 40),
      13,
    );
    expect(pack([floorOnly], clearance: 40).packedCount, 13);
  });
  test(
    'single SKU capacity and packed geometry agree across gaps and quantities',
    () {
      for (final gap in [0, 1, 10, 40, 100, 500]) {
        final capacity = engine.theoreticalCapacity(
          section,
          box,
          entry(wpc, 1000),
          clearanceMm: gap,
        );
        for (final quantity in [1, 9, 100, capacity, capacity + 1]) {
          final result = pack([entry(wpc, quantity)], clearance: gap);
          expect(result.packedCount, quantity > capacity ? capacity : quantity);
          valid(result, section);
        }
      }
    },
  );
  test(
    'section two global origin remains correct while manual drag can unassign',
    () {
      final second = section.copyWith(startXmm: 2900);
      final result = pack([entry(wpc, 286)], s: second);
      expect(result.groups.single.positionXmm, 2900);
      valid(result, second);
      final scene = NativeContainerSceneController(initialGroups: result.groups)
        ..setSections([second]);
      addTearDown(scene.dispose);
      scene.beginMove(result.groups.single.id);
      scene.previewMove(0, 0, 0);
      expect(scene.invalidGroupId, isNull);
      scene.endMove();
      expect(scene.groups.single.positionXmm, 0);
      expect(scene.groups.single.sectionId, isNull);
      expect(scene.groups.single.needsReview, isTrue);
    },
  );
  test(
    'manual_quantity_override survives recalculation and complete plan reload',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureBuiltInData();
      final repository = DriftContainerLoadingRepository(db);
      final editor = LoadingEditorController(repository);
      addTearDown(editor.dispose);
      final cargo = await repository.saveCargo(wpc);
      final id = editor.addCargo(editor.sections.first.id, cargo);
      expect(editor.entries.single.quantity, 286);
      editor.updateEntry(
        editor.entries.single.copyWith(
          quantity: 300,
          manualQuantityOverride: true,
        ),
      );
      editor.pack(editor.sections.first.id);
      editor.pack(editor.sections.first.id);
      expect(editor.entries.single.quantity, 300);
      expect(editor.packedFor(id), 286);
      final g = editor.scene.groups.first;
      editor.scene.beginMove(g.id);
      editor.scene.previewMove(0, 50, 0);
      editor.scene.endMove();
      await editor.save('');
      final savedId = editor.plan!.id;
      expect(editor.plan!.name, startsWith('40HQ · '));
      await repository.deleteCargo(cargo.id);
      final saved = await repository.loadSectionPlan(savedId);
      expect(saved.sections, hasLength(4));
      expect(saved.entries.single.quantity, 300);
      expect(saved.entries.single.manualQuantityOverride, true);
      expect(saved.groups.single.positionYmm, 50);
      expect(saved.entries.single.cargo.name, 'WPC01');
      await repository.renamePlan(savedId, 'Renamed');
      expect((await repository.watchPlans().first).single.name, 'Renamed');
      await repository.deletePlan(savedId);
      expect(await repository.watchPlans().first, isEmpty);
      expect(await repository.watchPresets().first, hasLength(2));
    },
  );
  test(
    'schema9 migration assigns legacy groups and preserves ambiguous geometry',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'fly-section-migration-',
      );
      final file = File('${dir.path}/fly.db');
      var db = AppDatabase(NativeDatabase(file));
      try {
        await db.ensureBuiltInData();
        final repo = DriftContainerLoadingRepository(db);
        final preset = (await repo.watchPresets().first).firstWhere(
          (p) => p.id == 'container-40hq',
        );
        final plan = await repo.createPlan(name: 'Legacy', container: preset);
        final result = pack([entry(wpc, 286)]);
        final library = (await repo.watchCargoLibrary().first).firstWhere(
          (c) => c.id == 'cargo-wpc-grille',
        );
        final g = result.groups.single;
        await db.customStatement(
          'INSERT INTO loading_plan_groups (id,plan_id,cargo_package_id,quantity,rows,columns,layers,bounding_length_mm,bounding_width_mm,bounding_height_mm,position_xmm,color_value,sort_order,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
          [
            'old',
            plan.id,
            library.id,
            286,
            13,
            1,
            22,
            2900,
            2080,
            2640,
            3000,
            g.colorValue,
            0,
            1,
            1,
          ],
        );
        await removeSyncSchema(db);
        await db.customStatement('DROP TABLE section_cargo_entries');
        await db.customStatement('DROP TABLE container_sections');
        for (final column in [
          'section_id',
          'entry_id',
          'needs_review',
          'allow_stack',
        ]) {
          await db.customStatement(
            'ALTER TABLE loading_plan_groups DROP COLUMN $column',
          );
        }
        await db.customStatement(
          'ALTER TABLE cargo_packages DROP COLUMN default_section_quantity',
        );
        await db.customStatement('PRAGMA user_version = 9');
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        final loaded = await DriftContainerLoadingRepository(db)
            .loadSectionPlan(plan.id);
        expect(loaded.sections, hasLength(4));
        expect(loaded.groups.single.positionXmm, 3000);
        expect(loaded.groups.single.needsReview, true);
        expect(loaded.groups.single.sectionId, loaded.sections.first.id);
        expect(loaded.entries.single.quantity, 286);
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
