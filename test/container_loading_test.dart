import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/tools/container_loading/data/container_loading_repository.dart';
import 'package:fly/features/tools/container_loading/domain/models/container_loading_models.dart';
import 'package:fly/features/tools/container_loading/domain/packing/packing_engine.dart';
import 'package:fly/features/tools/container_loading/domain/packing/placement_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const container40Hq = Dimensions3(11900, 2200, 2690);
  const container20Gp = Dimensions3(5800, 2200, 2320);
  const wpc = CargoPackageModel(
    id: 'wpc',
    name: 'WPC 格栅',
    dimensions: Dimensions3(2900, 160, 120),
    weightGrams: 18000,
    colorValue: 0xFF79A88C,
    allowRotateX: false,
    allowRotateY: false,
    allowRotateZ: false,
  );
  const engine = SingleSkuGridPackingEngine();

  test('40HQ WPC is 13 rows x 22 layers x 4 sections = 1144', () {
    final result = engine.pack(
      const PackingRequest(
        container: container40Hq,
        maxPayloadGrams: 28000000,
        items: [PackingItem(cargo: wpc, quantity: 2000)],
      ),
    );
    expect(result.grid?.rows, 13);
    expect(result.grid?.layers, 22);
    expect(result.grid?.sections, 4);
    expect(result.grid?.sectionCapacity, 286);
    expect(result.grid?.spaceCapacity, 1144);
    expect(result.packedCount, 1144);
  });

  test('quantity 286 fills one exact section', () {
    final result = engine.pack(
      const PackingRequest(
        container: container40Hq,
        maxPayloadGrams: 28000000,
        items: [PackingItem(cargo: wpc, quantity: 286)],
      ),
    );
    expect(result.packedCount, 286);
    expect(result.groups, hasLength(1));
    expect(result.groups.single.emptySlots, 0);
    expect(
      result.groups.single.dimensions,
      const Dimensions3(2900, 2080, 2640),
    );
  });

  test('quantity 284 retains two empty slots instead of drawing 286', () {
    final result = engine.pack(
      const PackingRequest(
        container: container40Hq,
        maxPayloadGrams: 28000000,
        items: [PackingItem(cargo: wpc, quantity: 284)],
      ),
    );
    expect(result.packedItems, hasLength(284));
    expect(result.groups.single.quantity, 284);
    expect(result.groups.single.emptySlots, 2);
  });

  test('weight becomes the limiting factor at 280 pieces', () {
    const cargo = CargoPackageModel(
      id: 'heavy',
      name: 'Heavy',
      dimensions: Dimensions3(100, 100, 100),
      weightGrams: 100000,
      colorValue: 0xFF000000,
      allowRotateX: false,
      allowRotateY: false,
      allowRotateZ: false,
    );
    final result = engine.pack(
      const PackingRequest(
        container: Dimensions3(1000, 1000, 1000),
        maxPayloadGrams: 28000000,
        items: [PackingItem(cargo: cargo, quantity: 1000)],
      ),
    );
    expect(result.grid?.spaceCapacity, 1000);
    expect(result.grid?.weightCapacity, 280);
    expect(result.grid?.limitFactor, LoadLimitFactor.weight);
    expect(result.packedCount, 280);
  });

  test('rotation selects the orientation that fits', () {
    const cargo = CargoPackageModel(
      id: 'rotate',
      name: 'Rotate',
      dimensions: Dimensions3(200, 300, 100),
      weightGrams: 1000,
      colorValue: 0xFF000000,
      allowRotateX: false,
      allowRotateY: false,
      allowRotateZ: true,
    );
    final grid = engine.evaluate(
      const Dimensions3(300, 200, 100),
      cargo,
      28000000,
    );
    expect(grid.maximumLoad, 1);
    expect(grid.orientation.rotationZ, 90);
    expect(grid.orientation.dimensions, const Dimensions3(300, 200, 100));
  });

  test('20GP uses its own internal dimensions', () {
    final grid = engine.evaluate(container20Gp, wpc, 28000000);
    expect(grid.sections, 2);
    expect(grid.rows, 13);
    expect(grid.layers, 19);
    expect(grid.spaceCapacity, 494);
  });

  test('legacy clearance no longer changes packing dimensions', () {
    final without = engine.evaluate(container40Hq, wpc, 28000000);
    final withGap = engine.evaluate(
      container40Hq,
      wpc,
      28000000,
      clearanceMm: 20,
    );
    expect(withGap.spaceCapacity, without.spaceCapacity);
  });

  test('AABB overlap, edge touch and container bounds are correct', () {
    const a = Aabb3(x: 0, y: 0, z: 0, dimensions: Dimensions3(100, 100, 100));
    const overlap = Aabb3(
      x: 99,
      y: 0,
      z: 0,
      dimensions: Dimensions3(100, 100, 100),
    );
    const touch = Aabb3(
      x: 100,
      y: 0,
      z: 0,
      dimensions: Dimensions3(100, 100, 100),
    );
    const outside = Aabb3(
      x: 950,
      y: 0,
      z: 0,
      dimensions: Dimensions3(100, 100, 100),
    );
    expect(a.overlaps(overlap), isTrue);
    expect(a.overlaps(touch), isFalse);
    expect(a.inside(const Dimensions3(1000, 1000, 1000)), isTrue);
    expect(outside.inside(const Dimensions3(1000, 1000, 1000)), isFalse);
    expect(CargoPlacement.snap(126, gridMm: 50), 150);
    final constrained = CargoPlacement.constrain(
      outside,
      const Dimensions3(1000, 1000, 1000),
    );
    expect(constrained.x, 900);
  });

  test('1000+ packages compute within interactive latency', () {
    final watch = Stopwatch()..start();
    final result = engine.pack(
      const PackingRequest(
        container: container40Hq,
        maxPayloadGrams: 28000000,
        items: [PackingItem(cargo: wpc, quantity: 1144)],
      ),
    );
    watch.stop();
    expect(result.packedItems, hasLength(1144));
    expect(result.groups, hasLength(4));
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('multi-SKU heuristic returns items, colored groups and no overlap', () {
    const pallet = CargoPackageModel(
      id: 'pallet',
      name: 'Pallet',
      type: CargoPackageType.pallet,
      dimensions: Dimensions3(1200, 1000, 1200),
      weightGrams: 800000,
      colorValue: 0xFF7FA7C9,
      stackable: false,
    );
    final result = const MultiSkuHeuristicPackingEngine().pack(
      const PackingRequest(
        container: container40Hq,
        maxPayloadGrams: 28000000,
        items: [
          PackingItem(cargo: wpc, quantity: 286),
          PackingItem(cargo: pallet, quantity: 4),
        ],
      ),
    );
    expect(result.packedItems, hasLength(result.packedCount));
    expect(result.groups.map((group) => group.cargo.id).toSet(), {
      'wpc',
      'pallet',
    });
    for (var i = 0; i < result.groups.length; i++) {
      final a = result.groups[i];
      final aabb = Aabb3(
        x: a.positionXmm,
        y: a.positionYmm,
        z: a.positionZmm,
        dimensions: a.dimensions,
      );
      expect(aabb.inside(container40Hq), isTrue);
      for (var j = i + 1; j < result.groups.length; j++) {
        final b = result.groups[j];
        expect(
          aabb.overlaps(
            Aabb3(
              x: b.positionXmm,
              y: b.positionYmm,
              z: b.positionZmm,
              dimensions: b.dimensions,
            ),
          ),
          isFalse,
        );
      }
    }
  });

  test('loading plan and positions survive repository reload', () async {
    final database = AppDatabase(NativeDatabase.memory());
    try {
      await database.ensureBuiltInData();
      final repository = DriftContainerLoadingRepository(database);
      final preset = (await repository.watchPresets().first).firstWhere(
        (value) => value.id == 'container-40hq',
      );
      final cargo = (await repository.watchCargoLibrary().first).firstWhere(
        (value) => value.id == 'cargo-wpc-grille',
      );
      final plan = await repository.createPlan(
        name: 'Persistence',
        container: preset,
      );
      final group = CargoGroupModel(
        id: 'group-1',
        planId: plan.id,
        cargoPackageId: cargo.id,
        quantity: 286,
        rows: 13,
        columns: 1,
        layers: 22,
        emptySlots: 0,
        boundingDimensions: const Dimensions3(2900, 2080, 2640),
        positionXmm: 2900,
        positionYmm: 50,
        positionZmm: 0,
        rotationX: 0,
        rotationY: 0,
        rotationZ: 0,
        colorValue: cargo.colorValue,
        sortOrder: 0,
      );
      await repository.replaceGroups(plan.id, [group]);
      final loaded = await repository.watchGroups(plan.id).first;
      expect(loaded.single.positionXmm, 2900);
      expect(loaded.single.positionYmm, 50);
      expect(loaded.single.quantity, 286);
    } finally {
      await database.close();
    }
  });

  test(
    'schema 8 to 9 preserves existing data and creates tool tables',
    () async {
      final previous = drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp('fly-v8-v9-');
      final file = File('${directory.path}${Platform.pathSeparator}fly.db');
      AppDatabase? legacy;
      AppDatabase? migrated;
      try {
        legacy = AppDatabase(NativeDatabase(file));
        await legacy.ensureBuiltInData();
        await legacy.customStatement(
          "INSERT INTO customers (id, name, priority, sort_order, created_at, updated_at) "
          "VALUES ('keep-me', 'Existing Customer', 'low', 0, 1, 1)",
        );
        await legacy.customStatement('DROP TABLE section_cargo_entries');
        await legacy.customStatement('DROP TABLE container_sections');
        await legacy.customStatement('DROP TABLE loading_plan_groups');
        await legacy.customStatement('DROP TABLE loading_plans');
        await legacy.customStatement('DROP TABLE cargo_packages');
        await legacy.customStatement('DROP TABLE container_presets');
        await legacy.customStatement('PRAGMA user_version = 8');
        await legacy.close();
        legacy = null;

        migrated = AppDatabase(NativeDatabase(file));
        await migrated.ensureBuiltInData();
        final existing = await (migrated.select(
          migrated.customers,
        )..where((row) => row.id.equals('keep-me'))).getSingle();
        expect(existing.name, 'Existing Customer');
        expect(
          await migrated.select(migrated.containerPresets).get(),
          hasLength(2),
        );
        expect(
          await migrated.select(migrated.cargoPackages).get(),
          hasLength(2),
        );
      } finally {
        await legacy?.close();
        await migrated?.close();
        if (await directory.exists()) await directory.delete(recursive: true);
        drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous;
      }
    },
  );
}
