import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/tools/container_loading/data/container_loading_repository.dart';
import 'package:fly/features/tools/container_loading/domain/models/container_loading_models.dart';
import 'package:fly/features/tools/container_loading/domain/models/section_models.dart';
import 'package:fly/features/tools/container_loading/domain/packing/section_packing_engine.dart';
import 'package:fly/features/tools/container_loading/presentation/loading_editor_controller.dart';

const pvc = CargoPackageModel(
  id: 'actual-pvc',
  name: 'PVC ceiling',
  dimensions: Dimensions3(2900, 250, 100),
  weightGrams: 1000,
  colorValue: 0xFF79A88C,
);
const small = CargoPackageModel(
  id: 'actual-small',
  name: 'WPC',
  dimensions: Dimensions3(2800, 160, 120),
  weightGrams: 1000,
  colorValue: 0xFF81AAC8,
);
const section = ContainerSection(
  id: 'section',
  planId: 'plan',
  index: 0,
  name: '',
  startXmm: 2900,
  lengthMm: 2900,
);
const container = Dimensions3(11900, 2200, 2690);

CargoGroupModel block({
  String id = 'pvc',
  int width = 2000,
  int x = 2900,
  int y = 0,
  int z = 0,
  int height = 1000,
  bool stack = true,
  String? sectionId = 'section',
}) => CargoGroupModel(
  id: id,
  planId: 'plan',
  cargoPackageId: 'pvc',
  quantity: 80,
  rows: 8,
  columns: 1,
  layers: 10,
  emptySlots: 0,
  boundingDimensions: Dimensions3(2900, width, height),
  positionXmm: x,
  positionYmm: y,
  positionZmm: z,
  rotationX: 0,
  rotationY: 0,
  rotationZ: 0,
  colorValue: 0xFF79A88C,
  sortOrder: 0,
  sectionId: sectionId,
  allowStack: stack,
);
List<LoadingSpace> spaces(List<CargoGroupModel> groups) =>
    const SectionPackingEngine().spacesForPlacement(
      section: section,
      container: container,
      groups: groups,
    );

void main() {
  test('old sections extending past an edited container only expose space inside the current box', () {
    const shorter = Dimensions3(4000, 2200, 2690);
    final free = const SectionPackingEngine().spacesForPlacement(
      section: section,
      container: shorter,
      groups: [block()],
    );
    expect(free, isNotEmpty);
    expect(free.every((s) => s.bounds.inside(shorter)), isTrue);
    const outside = ContainerSection(
      id: 'outside',
      planId: 'plan',
      index: 3,
      name: '',
      startXmm: 8700,
      lengthMm: 2900,
    );
    expect(
      const SectionPackingEngine().spacesForPlacement(
        section: outside,
        container: shorter,
        groups: [block()],
      ),
      isEmpty,
    );
  });
  test('saved geometry still opens when the preset is shorter than the original sections', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final editor = LoadingEditorController(DriftContainerLoadingRepository(db));
    try {
      await db.ensureBuiltInData();
      final repo = DriftContainerLoadingRepository(db);
      await repo.saveCargo(pvc);
      editor.addCargo(editor.sections.first.id, pvc);
      await editor.save('Before preset change');
      final old = editor.preset;
      final shorter = ContainerPresetModel(
        id: old.id,
        name: old.name,
        dimensions: const Dimensions3(5800, 2200, 2690),
        maxPayloadGrams: old.maxPayloadGrams,
        colorValue: old.colorValue,
        isBuiltIn: old.isBuiltIn,
      );
      await editor.open(editor.plan!.id, [shorter]);
      expect(editor.validation, isNotNull);
      expect(editor.scene.groups, isNotEmpty);
      expect(
        editor.manuallyAdjustedSections,
        containsAll(editor.sections.map((s) => s.id)),
      );
      for (final s in editor.sections) {
        expect(
          editor
              .spacesFor(s.id)
              .every((v) => v.bounds.inside(shorter.dimensions)),
          isTrue,
        );
      }
    } finally {
      editor.dispose();
      await db.close();
    }
  });
  test(
    'PVC 8x10 exposes1690mm overhead and keeps200mm gap out of loading cards',
    () {
      final result = spaces([block()]);
      expect(
        result.map((s) => s.bounds.dimensions),
        containsAll([
          const Dimensions3(2900, 2000, 1690),
          const Dimensions3(2900, 200, 2690),
        ]),
      );
      final offered = LoadingSpace.suggested(result, []);
      expect(offered.single.bounds.z, 1000);
      expect(offered.single.bounds.x, 2900);
      expect(offered.single.name, 'A区');
      expect(
        result.fold<int>(0, (n, s) => n + s.bounds.dimensions.volumeMm3) +
            block().boundingDimensions.volumeMm3,
        2900 * 2200 * 2690,
      );
    },
  );
  test(
    'side moves,500mm threshold and non-stackable top use actual geometry',
    () {
      expect(
        LoadingSpace.suggested(
          spaces([block(width: 1700)]),
          [],
        ).where((s) => s.bounds.z == 0).single.bounds.dimensions.widthMm,
        500,
      );
      expect(
        LoadingSpace.suggested(
          spaces([block(width: 1701)]),
          [],
        ).where((s) => s.bounds.z == 0),
        isEmpty,
      );
      final right = spaces([block(width: 1500, y: 700)]);
      expect(right.singleWhere((s) => s.bounds.z == 0).bounds.y, 0);
      expect(
        spaces([block(stack: false)]).where((s) => s.bounds.z > 0),
        isEmpty,
      );
      expect(spaces([block(sectionId: null)]), isEmpty);
    },
  );
  test(
    'multiple and neighboring-section cargo leave disjoint clipped empty boxes',
    () {
      final cargo = [
        block(width: 1200),
        block(
          id: 'neighbor',
          width: 500,
          y: 1500,
          x: 5700,
          height: 600,
          sectionId: 'next',
        ),
      ];
      final result = spaces(cargo);
      expect(
        spaces(cargo.reversed.toList()).map((s) => s.id),
        result.map((s) => s.id),
      );
      for (var i = 0; i < result.length; i++) {
        final b = result[i].bounds;
        expect(
          b.x >= section.startXmm &&
              b.maxX <= section.endXmm &&
              b.inside(container),
          isTrue,
        );
        for (final g in cargo) {
          expect(b.overlaps(g.bounds), isFalse);
        }
        for (var j = i + 1; j < result.length; j++) {
          expect(b.overlaps(result[j].bounds), isFalse);
        }
      }
    },
  );
  test('resize,undo,redo,save/reopen and filling a free space preserve manual cargo', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = DriftContainerLoadingRepository(db);
    final editor = LoadingEditorController(repo);
    try {
      await db.ensureBuiltInData();
      await repo.saveCargo(pvc);
      await repo.saveCargo(small);
      final id = editor.sections.first.id;
      editor.addCargo(id, pvc);
      final g = editor.scene.groups.single;
      expect(editor.scene.resizeGroup(g.id, rows: 8, layers: 10), isTrue);
      expect(editor.packedCount, 80);
      expect(
        editor
            .spacesFor(id)
            .singleWhere((s) => s.bounds.z == 1000)
            .bounds
            .dimensions
            .heightMm,
        1690,
      );
      editor.scene.undo();
      expect(LoadingSpace.suggested(editor.spacesFor(id), []), isEmpty);
      editor.scene.redo();
      final top = editor.spacesFor(id).singleWhere((s) => s.bounds.z == 1000);
      await editor.save('Actual placement');
      await editor.open(editor.plan!.id, await repo.watchPresets().first);
      expect(editor.manuallyAdjustedSections, contains(id));
      expect(editor.scene.groups.single.quantity, 80);
      expect(editor.spacesFor(id).map((s) => s.id), contains(top.id));
      final unchanged = editor.scene.groups.single;
      final added = editor.addCargo(id, small, spaceId: top.id);
      final child = editor.scene.groups.singleWhere((g) => g.entryId == added);
      expect(
        (child.positionXmm, child.positionYmm, child.positionZmm),
        (top.bounds.x, top.bounds.y, top.bounds.z),
      );
      expect(
        editor.scene.groups
            .where((g) => g.id == unchanged.id)
            .map(
              (g) => (
                g.quantity,
                g.positionXmm,
                g.positionYmm,
                g.positionZmm,
                g.boundingDimensions,
              ),
            ),
        [
          (
            unchanged.quantity,
            unchanged.positionXmm,
            unchanged.positionYmm,
            unchanged.positionZmm,
            unchanged.boundingDimensions,
          ),
        ],
      );
      for (final s in editor.spacesFor(id)) {
        for (final g in editor.scene.groups) {
          expect(s.bounds.overlaps(g.bounds), isFalse);
        }
      }
      final before = editor.scene.groups.toList();
      await editor.save('Filled space');
      await editor.open(editor.plan!.id, await repo.watchPresets().first);
      expect(editor.manuallyAdjustedSections, contains(id));
      expect(
        editor.scene.groups.map(
          (g) => (g.quantity, g.positionYmm, g.positionZmm),
        ),
        before.map((g) => (g.quantity, g.positionYmm, g.positionZmm)),
      );
    } finally {
      editor.dispose();
      await db.close();
    }
  });
  test(
    'stale or oversized space selection fails before adding any cargo',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final editor = LoadingEditorController(
        DriftContainerLoadingRepository(db),
      );
      try {
        await db.ensureBuiltInData();
        final id = editor.sections.first.id;
        editor.addCargo(id, pvc);
        final g = editor.scene.groups.single;
        editor.scene.resizeGroup(g.id, rows: 6, layers: 10);
        final old = editor.spacesFor(id).first;
        editor.scene.resizeGroup(g.id, rows: 8, layers: 10);
        final count = editor.entries.length;
        expect(
          () => editor.addCargo(id, small, spaceId: old.id),
          throwsStateError,
        );
        final top = editor.spacesFor(id).first;
        const huge = CargoPackageModel(
          id: 'huge',
          name: 'Huge',
          dimensions: Dimensions3(3000, 2000, 2000),
          weightGrams: 1,
          colorValue: 0,
        );
        expect(editor.canAddToSpace(id, huge, top), isFalse);
        expect(
          () => editor.addCargo(id, huge, spaceId: top.id),
          throwsStateError,
        );
        expect(editor.entries.length, count);
        expect(editor.scene.groups.length, 1);
      } finally {
        editor.dispose();
        await db.close();
      }
    },
  );
}
