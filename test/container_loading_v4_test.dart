import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/tools/container_loading/data/container_loading_repository.dart';
import 'package:fly/features/tools/container_loading/domain/models/container_loading_models.dart';
import 'package:fly/features/tools/container_loading/domain/models/section_models.dart';
import 'package:fly/features/tools/container_loading/presentation/loading_editor_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'container_loading_v2_test.dart' as f;

void main() {
  test(
    'V4 preserves explicit stacking choice, repairs legacy default once',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureBuiltInData();
      final repo = DriftContainerLoadingRepository(db);
      final e = LoadingEditorController(repo);
      addTearDown(e.dispose);
      final cargo = await repo.saveCargo(f.pallet);
      e.addCargo(e.sections.first.id, cargo);
      e.updateEntry(e.entries.single.copyWith(quantity: 2, allowStack: false));
      await e.save('Stacking compatibility');
      final id = e.plan!.id;
      final presets = await repo.watchPresets().first;
      await e.open(id, presets);
      expect(e.entries.single.allowStack, false);
      expect(e.packedCount, 1);
      final row = await db.select(db.sectionCargoEntries).getSingle();
      final json = jsonDecode(row.cargoSnapshot) as Map<String, dynamic>;
      (json['layoutV3'] as Map<String, dynamic>).remove('stackPolicyV4');
      await db.customStatement(
        'UPDATE section_cargo_entries SET cargo_snapshot=? WHERE id=?',
        [jsonEncode(json), row.id],
      );
      await e.open(id, presets);
      expect(e.entries.single.allowStack, true);
      expect(e.packedCount, 2);
      expect(e.spacesFor(e.sections.first.id).any((s) => s.bounds.z > 0), true);
    },
  );
  test('V4 adding and editing pallets calculates immediately and stacks vertically', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureBuiltInData();
    final e = LoadingEditorController(DriftContainerLoadingRepository(db));
    addTearDown(e.dispose);
    const p = CargoPackageModel(
      id: 'p',
      name: 'Pallet',
      type: CargoPackageType.pallet,
      dimensions: Dimensions3(2000, 1000, 800),
      weightGrams: 1000,
      colorValue: 0xFF7FA7C9,
    );
    e.addCargo(e.sections.first.id, p);
    expect(e.packedCount, 1);
    expect(e.entries.single.allowStack, true);
    e.updateEntry(
      e.entries.single.copyWith(
        quantity: 2,
        horizontalPlacement: HorizontalPlacement.left,
      ),
    );
    expect(e.packedCount, 2);
    expect(e.scene.groups.single.layers, 2);
    expect(e.scene.groups.single.rows, 1);
    expect(e.scene.groups.single.bounds.maxZ, 1600);
    var spaces = e.spacesFor(e.sections.first.id);
    expect(spaces.map((s) => s.name), ['01 · 右侧空间', '02 · 上方空间']);
    expect(spaces.last.bounds.dimensions, const Dimensions3(2900, 1000, 1090));
    e.updateEntry(
      e.entries.single.copyWith(
        horizontalPlacement: HorizontalPlacement.center,
      ),
    );
    spaces = e.spacesFor(e.sections.first.id);
    expect(spaces.map((s) => s.name), ['01 · 左侧空间', '02 · 上方空间', '03 · 右侧空间']);
    expect(e.needsPacking, isEmpty);
    e.removeEntry(e.entries.single.id);
    expect(e.packedCount, 0);
  });
  test('V4 exact 1m overhang is accepted as a planning option', () {
    const p = CargoPackageModel(
      id: 'p',
      name: 'Pallet',
      type: CargoPackageType.pallet,
      dimensions: Dimensions3(1900, 1200, 1000),
      weightGrams: 1000,
      colorValue: 0xFF7FA7C9,
    );
    final result = f.pack([
      f.entry(p, 1, bottom: true, position: HorizontalPlacement.left),
      f.entry(f.wpc, 286),
    ]);
    expect(
      result.groups.any(
        (g) => g.cargoPackageId == f.wpc.id && g.positionZmm == 1000,
      ),
      true,
    );
    f.valid(result, f.section);
  });
}
