import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/tools/container_loading/data/container_loading_repository.dart';
import 'package:fly/features/tools/container_loading/domain/models/container_loading_models.dart';
import 'package:fly/features/tools/container_loading/domain/models/section_models.dart';
import 'package:fly/features/tools/container_loading/presentation/loading_editor_controller.dart';

import 'container_actual_spaces_test.dart' as f;

const grille = CargoPackageModel(
  id: 'area-wpc',
  name: 'WPC 格栅',
  dimensions: Dimensions3(2900, 160, 120),
  weightGrams: 1000,
  colorValue: 0xFFD3A06D,
);

void main() {
  for (final type in [CargoPackageType.pallet, CargoPackageType.crate]) {
    test(
      'additional $type uses selected area rather than becoming a new floor base',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final editor = LoadingEditorController(
          DriftContainerLoadingRepository(db),
        );
        try {
          await db.ensureBuiltInData();
          final section = editor.sections.first.id;
          // Keep the first pallet automatic to cover the legacy base-packing path.
          final base = CargoPackageModel(
            id: 'base',
            name: 'Base',
            type: CargoPackageType.pallet,
            dimensions: const Dimensions3(2800, 1800, 1200),
            weightGrams: 1,
            colorValue: 0xFF79A88C,
          );
          editor.addCargo(section, base);
          final original = editor.scene.groups.single;
          expect(editor.usesPlacedSpaces(section), isFalse);
          final top = editor
              .spacesFor(section)
              .firstWhere((s) => s.bounds.z > 0);
          final extra = CargoPackageModel(
            id: 'extra',
            name: 'Extra',
            type: type,
            dimensions: const Dimensions3(1000, 600, 500),
            weightGrams: 1,
            colorValue: 0xFFD3A06D,
          );
          expect(editor.canAddToSpace(section, extra, top), isTrue);
          editor.addCargo(section, extra, spaceId: top.id);
          expect(editor.manuallyAdjustedSections, contains(section));
          final added = editor.scene.groups.last;
          expect(
            (added.positionXmm, added.positionYmm, added.positionZmm),
            (top.bounds.x, top.bounds.y, top.bounds.z),
          );
          expect(added.bounds.overlaps(original.bounds), isFalse);
          final kept = editor.scene.groups.first;
          expect(
            (
              kept.positionXmm,
              kept.positionYmm,
              kept.positionZmm,
              kept.boundingDimensions,
            ),
            (
              original.positionXmm,
              original.positionYmm,
              original.positionZmm,
              original.boundingDimensions,
            ),
          );
          expect(
            editor.scene.loadedGroups.any(editor.scene.hasPlacementConflict),
            isFalse,
          );
        } finally {
          editor.dispose();
          await db.close();
        }
      },
    );
  }
  test('160 PVC plus 60 WPC must enter the overhead area without floor overlap; reopen retains both', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = DriftContainerLoadingRepository(db);
    final editor = LoadingEditorController(repo);
    try {
      await db.ensureBuiltInData();
      await repo.saveCargo(f.pvc);
      await repo.saveCargo(grille);
      final section = editor.sections.first.id;
      editor.addCargo(section, f.pvc);
      final pvc = editor.scene.groups.single;
      editor.scene.resizeGroup(pvc.id, rows: 8, layers: 20);
      final before = editor.entries.length;
      expect(() => editor.addCargo(section, grille), throwsStateError);
      expect(editor.entries.length, before);
      final area = LoadingSpace.suggested(editor.spacesFor(section), []).single;
      expect(area.name, 'A区');
      expect(area.bounds.dimensions, const Dimensions3(2900, 2000, 690));
      editor.addCargo(section, grille, spaceId: area.id);
      final wpc = editor.scene.groups.last;
      editor.scene.resizeGroup(wpc.id, rows: 12, layers: 5);
      expect(editor.scene.loadedGroups.map((g) => g.quantity), [160, 60]);
      expect(editor.scene.groups.last.positionZmm, 2000);
      expect(
        editor.scene.groups.first.bounds.overlaps(
          editor.scene.groups.last.bounds,
        ),
        isFalse,
      );
      expect(
        editor.scene.loadedGroups.any(editor.scene.hasPlacementConflict),
        isFalse,
      );
      await editor.save('Areas');
      await editor.open(editor.plan!.id, await repo.watchPresets().first);
      expect(editor.packedCount, 220);
      expect(editor.scene.groups.last.positionZmm, 2000);
      editor.removeCargoGroup(wpc.id);
      expect(editor.packedCount, 160);
      expect(
        LoadingSpace.suggested(editor.spacesFor(section), []).single.name,
        'A区',
      );
      editor.scene.undo();
      expect(editor.packedCount, 220);
    } finally {
      editor.dispose();
      await db.close();
    }
  });

  test('unassigned second cargo is rejected before manual mode; empty section can add again', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final editor = LoadingEditorController(DriftContainerLoadingRepository(db));
    try {
      await db.ensureBuiltInData();
      final section = editor.sections.first.id;
      editor.addCargo(section, f.pvc);
      expect(editor.manuallyAdjustedSections.contains(section), isFalse);
      expect(() => editor.addCargo(section, grille), throwsStateError);
      final first = editor.scene.groups.single;
      editor.scene.resizeGroup(first.id, rows: 0, layers: 0);
      editor.addCargo(section, grille);
      expect(editor.scene.loadedGroups.single.cargoPackageId, grille.id);
      editor.removeCargoGroup(editor.scene.loadedGroups.single.id);
      expect(editor.scene.loadedGroups, isEmpty);
      editor.addCargo(section, grille);
      expect(editor.scene.loadedGroups.single.positionZmm, 0);
    } finally {
      editor.dispose();
      await db.close();
    }
  });
}
