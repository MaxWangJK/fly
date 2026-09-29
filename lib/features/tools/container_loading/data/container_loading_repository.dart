import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../domain/models/container_loading_models.dart';
import '../domain/models/section_models.dart';

abstract interface class ContainerLoadingRepository {
  Stream<List<ContainerPresetModel>> watchPresets();
  Stream<List<CargoPackageModel>> watchCargoLibrary();
  Stream<List<LoadingPlanModel>> watchPlans();
  Stream<List<CargoGroupModel>> watchGroups(String planId);
  Future<CargoPackageModel> saveCargo(CargoPackageModel cargo);
  Future<LoadingPlanModel> createPlan({
    required String name,
    required ContainerPresetModel container,
    int? maxPayloadGrams,
    int clearanceMm,
  });
  Future<void> savePlan(LoadingPlanModel plan);
  Future<void> replaceGroups(String planId, List<CargoGroupModel> groups);
  Future<void> saveGroup(CargoGroupModel group);
  Future<void> deleteGroup(String id);
  Future<void> savePreset(ContainerPresetModel preset);
  Future<void> deleteCargo(String id);
  Future<void> deletePlan(String id);
  Future<void> renamePlan(String id, String name);
  Future<SectionPlanSnapshot> loadSectionPlan(String id);
  Future<void> saveSectionPlan(SectionPlanSnapshot snapshot);
}

class DriftContainerLoadingRepository implements ContainerLoadingRepository {
  DriftContainerLoadingRepository(this.database);

  final AppDatabase database;
  static const _uuid = Uuid();

  @override
  Stream<List<ContainerPresetModel>> watchPresets() =>
      (database.select(database.containerPresets)
            ..orderBy([(row) => OrderingTerm.asc(row.name)]))
          .watch()
          .map((rows) => rows.map(_mapPreset).toList(growable: false));

  @override
  Stream<List<CargoPackageModel>> watchCargoLibrary() =>
      (database.select(database.cargoPackages)
            ..where((row) => row.deletedAt.isNull())
            ..orderBy([(row) => OrderingTerm.asc(row.name)]))
          .watch()
          .map((rows) => rows.map(_mapCargo).toList(growable: false));

  @override
  Stream<List<LoadingPlanModel>> watchPlans() =>
      (database.select(database.loadingPlans)
            ..where((row) => row.deletedAt.isNull())
            ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
          .watch()
          .map((rows) => rows.map(_mapPlan).toList(growable: false));

  @override
  Stream<List<CargoGroupModel>> watchGroups(String planId) =>
      (database.select(database.loadingPlanGroups)
            ..where((row) => row.planId.equals(planId))
            ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
          .watch()
          .map((rows) => rows.map(_mapGroup).toList(growable: false));

  @override
  Future<CargoPackageModel> saveCargo(CargoPackageModel cargo) async {
    final now = DateTime.now();
    final value = cargo.id.isEmpty
        ? CargoPackageModel(
            id: _uuid.v4(),
            name: cargo.name,
            dimensions: cargo.dimensions,
            weightGrams: cargo.weightGrams,
            colorValue: cargo.colorValue,
            type: cargo.type,
            allowRotateX: cargo.allowRotateX,
            allowRotateY: cargo.allowRotateY,
            allowRotateZ: cargo.allowRotateZ,
            stackable: cargo.stackable,
            defaultSectionQuantity: cargo.defaultSectionQuantity,
          )
        : cargo;
    final existing = await (database.select(
      database.cargoPackages,
    )..where((row) => row.id.equals(value.id))).getSingleOrNull();
    await database
        .into(database.cargoPackages)
        .insertOnConflictUpdate(
          CargoPackagesCompanion.insert(
            id: value.id,
            name: value.name,
            type: Value(value.type.name),
            lengthMm: value.dimensions.lengthMm,
            widthMm: value.dimensions.widthMm,
            heightMm: value.dimensions.heightMm,
            weightGrams: value.weightGrams,
            colorValue: Value(value.colorValue),
            allowRotateX: Value(value.allowRotateX),
            allowRotateY: Value(value.allowRotateY),
            allowRotateZ: Value(value.allowRotateZ),
            stackable: Value(value.stackable),
            defaultSectionQuantity: Value(value.defaultSectionQuantity),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
    return value;
  }

  @override
  Future<LoadingPlanModel> createPlan({
    required String name,
    required ContainerPresetModel container,
    int? maxPayloadGrams,
    int clearanceMm = 0,
  }) async {
    final now = DateTime.now();
    final plan = LoadingPlanModel(
      id: _uuid.v4(),
      name: name.trim().isEmpty
          ? '${container.name} · ${now.month.toString().padLeft(2, '0')}月${now.day.toString().padLeft(2, '0')}日 ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}'
          : name.trim(),
      containerPresetId: container.id,
      maxPayloadGrams: maxPayloadGrams ?? container.maxPayloadGrams,
      clearanceMm: clearanceMm,
      createdAt: now,
      updatedAt: now,
    );
    await savePlan(plan);
    return plan;
  }

  @override
  Future<void> savePlan(LoadingPlanModel plan) async {
    await database
        .into(database.loadingPlans)
        .insertOnConflictUpdate(
          LoadingPlansCompanion.insert(
            id: plan.id,
            name: plan.name,
            containerPresetId: plan.containerPresetId,
            maxPayloadGrams: plan.maxPayloadGrams,
            clearanceMm: Value(plan.clearanceMm),
            createdAt: plan.createdAt,
            updatedAt: DateTime.now(),
          ),
        );
  }

  @override
  Future<void> replaceGroups(String planId, List<CargoGroupModel> groups) =>
      database.transaction(() async {
        await (database.delete(
          database.loadingPlanGroups,
        )..where((row) => row.planId.equals(planId))).go();
        for (final group in groups) {
          await _insertGroup(group);
        }
      });

  @override
  Future<void> saveGroup(CargoGroupModel group) async {
    await database
        .into(database.loadingPlanGroups)
        .insertOnConflictUpdate(_groupCompanion(group));
  }

  @override
  Future<void> deleteGroup(String id) => (database.delete(
    database.loadingPlanGroups,
  )..where((row) => row.id.equals(id))).go();

  Future<void> _insertGroup(CargoGroupModel group) =>
      database.into(database.loadingPlanGroups).insert(_groupCompanion(group));

  LoadingPlanGroupsCompanion _groupCompanion(CargoGroupModel value) {
    final now = DateTime.now();
    return LoadingPlanGroupsCompanion.insert(
      id: value.id,
      planId: value.planId,
      cargoPackageId: value.cargoPackageId,
      sectionId: Value(value.sectionId),
      entryId: Value(value.entryId),
      needsReview: Value(value.needsReview),
      allowStack: Value(value.allowStack),
      quantity: value.quantity,
      rows: value.rows,
      columns: value.columns,
      layers: value.layers,
      emptySlots: Value(value.emptySlots),
      boundingLengthMm: value.boundingDimensions.lengthMm,
      boundingWidthMm: value.boundingDimensions.widthMm,
      boundingHeightMm: value.boundingDimensions.heightMm,
      positionXmm: Value(value.positionXmm),
      positionYmm: Value(value.positionYmm),
      positionZmm: Value(value.positionZmm),
      rotationX: Value(value.rotationX),
      rotationY: Value(value.rotationY),
      rotationZ: Value(value.rotationZ),
      colorValue: value.colorValue,
      sortOrder: value.sortOrder,
      createdAt: now,
      updatedAt: now,
    );
  }

  static ContainerPresetModel _mapPreset(ContainerPresetRecord row) =>
      ContainerPresetModel(
        id: row.id,
        name: row.name,
        dimensions: Dimensions3(
          row.innerLengthMm,
          row.innerWidthMm,
          row.innerHeightMm,
        ),
        maxPayloadGrams: row.maxPayloadGrams,
        colorValue: row.colorValue,
        isBuiltIn: row.isBuiltIn,
        doorWidthMm: row.doorWidthMm,
        doorHeightMm: row.doorHeightMm,
      );

  static CargoPackageModel _mapCargo(CargoPackageRecord row) =>
      CargoPackageModel(
        id: row.id,
        name: row.name,
        type: CargoPackageType.values.firstWhere(
          (value) => value.name == row.type,
          orElse: () => CargoPackageType.custom,
        ),
        dimensions: Dimensions3(row.lengthMm, row.widthMm, row.heightMm),
        weightGrams: row.weightGrams,
        colorValue: row.colorValue,
        allowRotateX: row.allowRotateX,
        allowRotateY: row.allowRotateY,
        allowRotateZ: row.allowRotateZ,
        stackable: row.stackable,
        defaultSectionQuantity: row.defaultSectionQuantity,
      );

  static LoadingPlanModel _mapPlan(LoadingPlanRecord row) => LoadingPlanModel(
    id: row.id,
    name: row.name,
    containerPresetId: row.containerPresetId,
    maxPayloadGrams: row.maxPayloadGrams,
    clearanceMm: row.clearanceMm,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  static CargoGroupModel _mapGroup(LoadingPlanGroupRecord row) =>
      CargoGroupModel(
        id: row.id,
        planId: row.planId,
        cargoPackageId: row.cargoPackageId,
        quantity: row.quantity,
        rows: row.rows,
        columns: row.columns,
        layers: row.layers,
        emptySlots: row.emptySlots,
        boundingDimensions: Dimensions3(
          row.boundingLengthMm,
          row.boundingWidthMm,
          row.boundingHeightMm,
        ),
        positionXmm: row.positionXmm,
        positionYmm: row.positionYmm,
        positionZmm: row.positionZmm,
        rotationX: row.rotationX,
        rotationY: row.rotationY,
        rotationZ: row.rotationZ,
        colorValue: row.colorValue,
        sortOrder: row.sortOrder,
        sectionId: row.sectionId,
        entryId: row.entryId,
        needsReview: row.needsReview,
        allowStack: row.allowStack,
      );

  @override
  Future<void> savePreset(ContainerPresetModel preset) async {
    final existing = await (database.select(
      database.containerPresets,
    )..where((r) => r.id.equals(preset.id))).getSingleOrNull();
    final now = DateTime.now();
    await database
        .into(database.containerPresets)
        .insertOnConflictUpdate(
          ContainerPresetsCompanion.insert(
            id: preset.id,
            name: preset.name,
            innerLengthMm: preset.dimensions.lengthMm,
            innerWidthMm: preset.dimensions.widthMm,
            innerHeightMm: preset.dimensions.heightMm,
            maxPayloadGrams: preset.maxPayloadGrams,
            colorValue: Value(preset.colorValue),
            isBuiltIn: Value(preset.isBuiltIn),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
  }

  @override
  Future<void> deleteCargo(String id) async {
    await (database.update(database.cargoPackages)
          ..where((r) => r.id.equals(id)))
        .write(CargoPackagesCompanion(deletedAt: Value(DateTime.now())));
  }

  @override
  Future<void> deletePlan(String id) async {
    await (database.update(database.loadingPlans)
          ..where((r) => r.id.equals(id)))
        .write(LoadingPlansCompanion(deletedAt: Value(DateTime.now())));
  }

  @override
  Future<void> renamePlan(String id, String name) async {
    if (name.trim().isEmpty) return;
    await (database.update(
      database.loadingPlans,
    )..where((r) => r.id.equals(id))).write(
      LoadingPlansCompanion(
        name: Value(name.trim()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  static String encodeCargo(CargoPackageModel c) => jsonEncode({
    'id': c.id,
    'name': c.name,
    'type': c.type.name,
    'l': c.dimensions.lengthMm,
    'w': c.dimensions.widthMm,
    'h': c.dimensions.heightMm,
    'weight': c.weightGrams,
    'color': c.colorValue,
    'default': c.defaultSectionQuantity,
  });
  static CargoPackageModel decodeCargo(String text) {
    final c = jsonDecode(text) as Map<String, dynamic>;
    return CargoPackageModel(
      id: c['id'] as String,
      name: c['name'] as String,
      type: CargoPackageType.values.firstWhere(
        (v) => v.name == c['type'],
        orElse: () => CargoPackageType.custom,
      ),
      dimensions: Dimensions3(c['l'] as int, c['w'] as int, c['h'] as int),
      weightGrams: c['weight'] as int,
      colorValue: c['color'] as int,
      defaultSectionQuantity: c['default'] as int?,
    );
  }

  @override
  Future<void> saveSectionPlan(SectionPlanSnapshot snapshot) async {
    final preset = await (database.select(
      database.containerPresets,
    )..where((r) => r.id.equals(snapshot.plan.containerPresetId))).getSingle();
    final error = ContainerSection.validate(
      snapshot.sections,
      preset.innerLengthMm,
    );
    if (error != null) throw ArgumentError(error);
    if (snapshot.sections.any((s) => s.planId != snapshot.plan.id) ||
        snapshot.entries.any(
          (e) => !snapshot.sections.any((s) => s.id == e.sectionId),
        )) {
      throw ArgumentError('Invalid plan relationships');
    }
    await database.transaction(() async {
      await savePlan(snapshot.plan);
      await (database.delete(
        database.loadingPlanGroups,
      )..where((r) => r.planId.equals(snapshot.plan.id))).go();
      await (database.delete(database.sectionCargoEntries)..where(
            (r) => r.sectionId.isInQuery(
              database.selectOnly(database.containerSections)
                ..addColumns([database.containerSections.id])
                ..where(
                  database.containerSections.planId.equals(snapshot.plan.id),
                ),
            ),
          ))
          .go();
      await (database.delete(
        database.containerSections,
      )..where((r) => r.planId.equals(snapshot.plan.id))).go();
      final now = DateTime.now();
      for (final s in snapshot.sections) {
        await database
            .into(database.containerSections)
            .insert(
              ContainerSectionsCompanion.insert(
                id: s.id,
                planId: s.planId,
                sectionIndex: s.index,
                name: s.name,
                startXmm: s.startXmm,
                lengthMm: s.lengthMm,
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      for (final e in snapshot.entries) {
        await database
            .into(database.sectionCargoEntries)
            .insert(
              SectionCargoEntriesCompanion.insert(
                id: e.id,
                sectionId: e.sectionId,
                cargoPackageId: e.cargo.id,
                cargoSnapshot: jsonEncode({
                  ...jsonDecode(encodeCargo(e.cargo)) as Map<String, dynamic>,
                  'layoutV3': {
                    'stackPolicyV4': true,
                    'perRow': e.perRow,
                    'rowCount': e.rowCount,
                    'spaceId': e.spaceId,
                    'allowOverhang': e.allowOverhang,
                  },
                }),
                quantity: e.quantity,
                orientation: Value(e.orientation.name),
                placeOnBottom: Value(e.placeOnBottom),
                allowStack: Value(e.allowStack),
                horizontalPlacement: Value(e.horizontalPlacement.name),
                manualQuantityOverride: Value(e.manualQuantityOverride),
                colorOverride: Value(e.colorOverride),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      for (final g in snapshot.groups) {
        await _insertGroup(g);
      }
    });
  }

  @override
  Future<SectionPlanSnapshot> loadSectionPlan(String id) async {
    final plan = _mapPlan(
      await (database.select(
        database.loadingPlans,
      )..where((r) => r.id.equals(id))).getSingle(),
    );
    var rows =
        await (database.select(database.containerSections)
              ..where((r) => r.planId.equals(id))
              ..orderBy([(r) => OrderingTerm.asc(r.sectionIndex)]))
            .get();
    var sections = rows
        .map(
          (r) => ContainerSection(
            id: r.id,
            planId: r.planId,
            index: r.sectionIndex,
            name: r.name,
            startXmm: r.startXmm,
            lengthMm: r.lengthMm,
          ),
        )
        .toList();
    if (sections.isEmpty) {
      final preset = await (database.select(
        database.containerPresets,
      )..where((r) => r.id.equals(plan.containerPresetId))).getSingle();
      sections = ContainerSection.defaults(id, preset.innerLengthMm);
    }
    final entryRows = await (database.select(
      database.sectionCargoEntries,
    )..where((r) => r.sectionId.isIn(sections.map((s) => s.id)))).get();
    final entries = entryRows
        .map(
          (r) => SectionCargoEntry(
            id: r.id,
            sectionId: r.sectionId,
            cargo: decodeCargo(r.cargoSnapshot),
            quantity: r.quantity,
            orientation: PlacementOrientation.values.byName(r.orientation),
            placeOnBottom: r.placeOnBottom,
            allowStack: r.allowStack,
            legacyStackDefault:
                !r.allowStack &&
                decodeCargo(r.cargoSnapshot).type == CargoPackageType.pallet &&
                ((jsonDecode(r.cargoSnapshot)
                            as Map<String, dynamic>)['layoutV3']
                        as Map<String, dynamic>?)?['stackPolicyV4'] !=
                    true,
            horizontalPlacement: HorizontalPlacement.values.byName(
              r.horizontalPlacement,
            ),
            manualQuantityOverride: r.manualQuantityOverride,
            colorOverride: r.colorOverride,
            perRow:
                ((jsonDecode(r.cargoSnapshot)
                            as Map<String, dynamic>)['layoutV3']
                        as Map<String, dynamic>?)?['perRow']
                    as int?,
            rowCount:
                ((jsonDecode(r.cargoSnapshot)
                            as Map<String, dynamic>)['layoutV3']
                        as Map<String, dynamic>?)?['rowCount']
                    as int?,
            spaceId:
                ((jsonDecode(r.cargoSnapshot)
                            as Map<String, dynamic>)['layoutV3']
                        as Map<String, dynamic>?)?['spaceId']
                    as String?,
            allowOverhang:
                ((jsonDecode(r.cargoSnapshot)
                            as Map<String, dynamic>)['layoutV3']
                        as Map<String, dynamic>?)?['allowOverhang']
                    as bool? ??
                true,
          ),
        )
        .toList();
    return SectionPlanSnapshot(
      plan: plan,
      sections: sections,
      entries: entries,
      groups: await watchGroups(id).first,
    );
  }
}
