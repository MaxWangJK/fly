import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/tools/container_loading/data/container_loading_repository.dart';
import 'package:fly/features/tools/container_loading/domain/models/container_loading_models.dart';
import 'package:fly/features/tools/container_loading/domain/models/section_models.dart';
import 'package:fly/features/tools/container_loading/domain/packing/section_packing_engine.dart';
import 'package:fly/features/tools/container_loading/presentation/loading_editor_controller.dart';

import 'container_actual_spaces_test.dart' as f;
import 'container_manual_grid_widget_test.dart' show pvc;

void main() {
  const engine = SectionPackingEngine();
  const entry = SectionCargoEntry(
    id: 'pvc',
    sectionId: 'section',
    cargo: pvc,
    quantity: 240,
    perRow: 12,
    rowCount: 20,
  );
  SectionPackingResult pack(SectionCargoEntry e, {int payload = 28000000}) =>
      engine.pack(
        section: f.section,
        container: f.container,
        entries: [e],
        remainingPayloadGrams: payload,
      );

  test('legacy automatic 12x20 explains 160+48, explicit grid keeps all240 in one block', () {
    expect(engine.recommendedGrid(const Dimensions3(2900, 2200, 2690), entry), (
      8,
      26,
    ));
    final automatic = pack(entry);
    expect(automatic.groups.map((g) => g.quantity), [160, 48]);
    expect((automatic.packedCount, automatic.unpackedCount), (208, 32));
    final manual = pack(entry.copyWith(manualGrid: true));
    final group = manual.groups.single;
    expect((manual.packedCount, manual.unpackedCount), (240, 0));
    expect(
      (group.rows, group.layers, group.quantity, group.emptySlots),
      (12, 20, 240, 0),
    );
    expect(group.boundingDimensions, const Dimensions3(2900, 3000, 2000));
    expect(
      (group.positionXmm, group.positionYmm, group.positionZmm),
      (2900, 0, 0),
    );
    expect(group.bounds.inside(f.container), isFalse);
    expect(manual.weightGrams, 4800000);
  });

  test(
    'height overflow, in-bounds manual grids, and zero retain exact quantities',
    () {
      for (final (rows, layers) in [
        (8, 30),
        (8, 20),
        (12, 20),
        (0, 20),
        (12, 0),
      ]) {
        final result = pack(
          entry.copyWith(
            manualGrid: true,
            perRow: rows,
            rowCount: layers,
            quantity: rows * layers,
          ),
        );
        expect(result.packedCount, rows * layers);
        expect(result.unpackedCount, 0);
        if (rows * layers == 0) {
          expect(result.groups, isEmpty);
        } else {
          expect(
            result.groups.single.boundingDimensions,
            Dimensions3(2900, rows * 250, layers * 100),
          );
        }
      }
      expect(
        pack(entry.copyWith(manualGrid: true), payload: 100000).packedCount,
        240,
      );
    },
  );

  test(
    'explicit grids follow the chosen orientation and horizontal alignment',
    () {
      final side = pack(
        entry.copyWith(
          manualGrid: true,
          orientation: PlacementOrientation.side,
        ),
      );
      expect(
        side.groups.single.boundingDimensions,
        const Dimensions3(2900, 1200, 5000),
      );
      expect(side.groups.single.rotationX, 90);
      for (final (alignment, y) in [
        (HorizontalPlacement.left, 0),
        (HorizontalPlacement.center, -400),
        (HorizontalPlacement.right, -800),
      ]) {
        expect(
          pack(entry.copyWith(manualGrid: true, horizontalPlacement: alignment))
              .groups
              .single
              .positionYmm,
          y,
        );
      }
    },
  );

  test('save, reopen, preset refresh and repack preserve one explicit grid; legacy flags stay false', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = DriftContainerLoadingRepository(db);
    final editor = LoadingEditorController(repo);
    try {
      await db.ensureBuiltInData();
      await repo.saveCargo(pvc);
      final section = editor.sections.first.id;
      editor.addCargo(section, pvc);
      expect(editor.entries.single.manualGrid, isFalse);
      editor.updateEntry(
        editor.entries.single.copyWith(
          manualGrid: true,
          perRow: 12,
          rowCount: 20,
          quantity: 240,
        ),
      );
      await editor.save('Explicit PVC');
      final snapshot = await repo.loadSectionPlan(editor.plan!.id);
      expect(snapshot.entries.single.manualGrid, isTrue);
      expect(snapshot.groups.single.quantity, 240);
      await editor.open(editor.plan!.id, await repo.watchPresets().first);
      expect(editor.manuallyAdjustedSections, isEmpty);
      expect(editor.entries.single.manualGrid, isTrue);
      editor.syncPreset(
        ContainerPresetModel(
          id: editor.preset.id,
          name: editor.preset.name,
          dimensions: const Dimensions3(11900, 2100, 2690),
          maxPayloadGrams: editor.preset.maxPayloadGrams,
          colorValue: editor.preset.colorValue,
          isBuiltIn: editor.preset.isBuiltIn,
        ),
      );
      editor.pack(section);
      expect(editor.scene.groups.single.quantity, 240);
      expect(
        editor.scene.groups.single.boundingDimensions,
        const Dimensions3(2900, 3000, 2000),
      );
      editor.removeEntry(editor.entries.single.id);
      expect(editor.scene.loadedGroups, isEmpty);
    } finally {
      editor.dispose();
      await db.close();
    }
  });
}
