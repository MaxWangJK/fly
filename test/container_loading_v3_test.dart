import 'package:drift/native.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/tools/container_loading/data/container_loading_repository.dart';
import 'package:fly/features/tools/container_loading/domain/models/container_loading_models.dart';
import 'package:fly/features/tools/container_loading/domain/models/section_models.dart';
import 'package:fly/features/tools/container_loading/presentation/loading_editor_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'container_loading_v2_test.dart' as f;

const pvc = CargoPackageModel(
  id: 'pvc',
  name: 'PVC ceiling',
  dimensions: Dimensions3(2900, 160, 160),
  weightGrams: 2000,
  colorValue: 0xFF79A88C,
);
void main() {
  test('V4 overhang beyond 1m is not permitted', () {
    const shortBase = CargoPackageModel(
      id: 'short-base',
      name: 'Short pallet',
      type: CargoPackageType.pallet,
      dimensions: Dimensions3(1899, 1200, 1000),
      weightGrams: 800000,
      colorValue: 0xFF7FA7C9,
    );
    final result = f.pack([
      f.entry(shortBase, 2, bottom: true, position: HorizontalPlacement.center),
      f.entry(pvc, 208),
    ]);
    expect(result.packedByEntry['pvc'], 96);
    expect(
      result.groups
          .where((g) => g.cargoPackageId == 'pvc')
          .every((g) => g.positionZmm == 0),
      true,
    );
    f.valid(result, f.section);
  });
  for (final alignment in [
    HorizontalPlacement.left,
    HorizontalPlacement.center,
    HorizontalPlacement.right,
  ]) {
    test('V3 spaces and overhang fill PVC above two pallets: $alignment', () {
      final base = f.entry(f.pallet, 2, bottom: true, position: alignment);
      final only = f.pack([base]);
      final spaces = f.engine.splitSpaces(f.section, f.box, only.groups);
      expect(spaces.length, alignment == HorizontalPlacement.center ? 3 : 2);
      for (var i = 0; i < spaces.length; i++) {
        expect(spaces[i].bounds.inside(f.box), true);
        for (var j = i + 1; j < spaces.length; j++) {
          expect(spaces[i].bounds.overlaps(spaces[j].bounds), false);
        }
      }
      final top = spaces.singleWhere((s) => s.bounds.z == 2000);
      expect(top.bounds.dimensions, const Dimensions3(2900, 1200, 690));
      expect(top.needsOverhang, true);
      final result = f.pack([base, f.entry(pvc, 208)]);
      expect(result.packedByEntry['pvc'], 124);
      expect(
        result.groups
            .where((g) => g.cargoPackageId == 'pvc' && g.positionZmm == 2000)
            .fold(0, (n, g) => n + g.quantity),
        28,
      );
      f.valid(result, f.section);
      final noOverhang = f.pack([
        base,
        f.entry(pvc, 208).copyWith(allowOverhang: false),
      ]);
      expect(noOverhang.packedByEntry['pvc'], 96);
      f.valid(noOverhang, f.section);
    });
  }
  test('V3 per-space rows are honoured and survive saving', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureBuiltInData();
    final repo = DriftContainerLoadingRepository(db);
    final editor = LoadingEditorController(repo);
    addTearDown(editor.dispose);
    final pallet = await repo.saveCargo(f.pallet);
    final cargo = await repo.saveCargo(pvc);
    final section = editor.sections.first;
    editor.addCargo(section.id, pallet);
    editor.updateEntry(
      editor.entries.single.copyWith(
        quantity: 2,
        allowStack: true,
        horizontalPlacement: HorizontalPlacement.center,
      ),
    );
    final space = editor
        .spacesFor(section.id)
        .singleWhere((s) => s.bounds.z == 2000);
    final id = editor.addCargo(section.id, cargo, spaceId: space.id);
    expect(editor.entries.last.quantity, 28);
    expect(editor.gridFor(editor.entries.last), (7, 4));
    editor.updateEntry(
      editor.entries.last.copyWith(perRow: 2, rowCount: 3, quantity: 6),
    );
    editor.pack(section.id);
    expect(editor.packedFor(id), 6);
    final g = editor.scene.groups.singleWhere((g) => g.entryId == id);
    expect((g.rows, g.layers, g.positionZmm), (2, 3, 2000));
    await editor.save('V3 space');
    final saved = await repo.loadSectionPlan(editor.plan!.id);
    final savedEntry = saved.entries.singleWhere((e) => e.id == id);
    expect(
      (savedEntry.perRow, savedEntry.rowCount, savedEntry.spaceId),
      (2, 3, space.id),
    );
    expect(savedEntry.quantity, 6);
    expect(saved.plan.clearanceMm, 0);
  });
  test('V3 removed space remains unplaced instead of silently relocating', () {
    final entry = f
        .entry(pvc, 10)
        .copyWith(spaceId: 'missing', perRow: 2, rowCount: 5);
    final result = f.pack([entry]);
    expect(result.packedCount, 0);
    expect(result.unpackedCount, 10);
  });
}
