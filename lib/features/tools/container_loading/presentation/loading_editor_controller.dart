import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/container_loading_repository.dart';
import '../domain/models/container_loading_models.dart';
import '../domain/models/section_models.dart';
import '../domain/packing/section_packing_engine.dart';
import 'scene/container_scene_controller.dart';

class LoadingEditorController extends ChangeNotifier {
  LoadingEditorController(this.repository) {
    sections = ContainerSection.defaults(draftId, preset.dimensions.lengthMm);
    scene.setSections(sections);
    scene.addListener(_sceneChanged);
  }
  final ContainerLoadingRepository repository;
  final scene = NativeContainerSceneController();
  static const uuid = Uuid();
  String draftId = uuid.v4();
  LoadingPlanModel? plan;
  ContainerPresetModel preset = const ContainerPresetModel(
    id: 'container-40hq',
    name: '40HQ',
    dimensions: Dimensions3(11900, 2200, 2690),
    maxPayloadGrams: 28000000,
    colorValue: 0xFF718096,
    isBuiltIn: true,
  );
  late List<ContainerSection> sections;
  List<SectionCargoEntry> entries = [];
  String? selectedSectionId;
  int get clearanceMm => 0; // Legacy persisted field is no longer an input.
  int maxPayloadGrams = 28000000;
  bool dirty = false;
  bool busy = false;
  int sectionArrivalRevision = 0;
  final Set<String> manuallyAdjustedSections = {};
  final Set<String> needsPacking = {};
  Map<String, CargoGroupModel> _previousGroups = {};
  bool _updating = false;
  String? get validation =>
      ContainerSection.validate(sections, preset.dimensions.lengthMm);
  int get unallocatedMm =>
      preset.dimensions.lengthMm - sections.fold(0, (a, b) => a + b.lengthMm);
  int get totalWeightGrams => scene.groups
      .where((g) => g.sectionId != null)
      .fold(
        0,
        (a, g) =>
            a +
            g.quantity *
                (entries
                        .where((e) => e.id == g.entryId)
                        .firstOrNull
                        ?.cargo
                        .weightGrams ??
                    0),
      );
  int get requestedCount => entries.fold(0, (a, e) {
    final actual = scene.groups
        .where((g) => g.entryId == e.id)
        .fold(0, (sum, g) => sum + g.quantity);
    if (manuallyAdjustedSections.contains(e.sectionId) &&
        scene.groups.any((g) => g.entryId == e.id)) {
      return a + actual;
    }
    return a + (actual > e.quantity ? actual : e.quantity);
  });
  int get packedCount => scene.groups
      .where((g) => g.sectionId != null)
      .fold(0, (a, g) => a + g.quantity);
  int packedFor(String id) => scene.groups
      .where((g) => g.entryId == id && g.sectionId != null)
      .fold(0, (a, g) => a + g.quantity);

  void _sceneChanged() {
    if (scene.focusedSectionId != null) {
      selectedSectionId = scene.focusedSectionId;
    }
    if (scene.isMoving && !_updating) {
      notifyListeners();
      return;
    }
    final next = {for (final g in scene.groups) g.id: g};
    if (!_updating) {
      final changedEntries = <String>{};
      final touchedEntries = <String>{};
      for (final id in {..._previousGroups.keys, ...next.keys}) {
        final before = _previousGroups[id];
        final after = next[id];
        if (_placementKey(before) == _placementKey(after)) continue;
        if (after?.sectionId != null && before?.sectionId != after?.sectionId) {
          sectionArrivalRevision++;
        }
        dirty = true;
        for (final g in [before, after].nonNulls) {
          if (g.entryId != null) {
            touchedEntries.add(g.entryId!);
            if (before?.quantity != after?.quantity ||
                before?.rows != after?.rows ||
                before?.layers != after?.layers ||
                before?.columns != after?.columns) {
              changedEntries.add(g.entryId!);
            }
          }
          if (g.sectionId != null) manuallyAdjustedSections.add(g.sectionId!);
          final source = entries.where((e) => e.id == g.entryId).firstOrNull;
          if (source != null) manuallyAdjustedSections.add(source.sectionId);
        }
      }
      entries = [
        for (final e in entries)
          if (touchedEntries.contains(e.id))
            e.copyWith(manualPlacement: true)
          else
            e,
      ];
      _syncManualQuantities(changedEntries);
    }
    _previousGroups = next;
    notifyListeners();
  }

  void _syncManualQuantities(Set<String> ids) {
    entries = [
      for (final e in entries)
        if (ids.contains(e.id))
          (() {
            final groups = scene.groups
                .where((g) => g.entryId == e.id)
                .toList();
            return e.copyWith(
              quantity: groups.fold<int>(0, (n, g) => n + g.quantity),
              perRow: groups.length == 1 ? groups.single.rows : e.perRow,
              rowCount: groups.length == 1 ? groups.single.layers : e.rowCount,
              manualPlacement: true,
              manualQuantityOverride: false,
            );
          })()
        else
          e,
    ];
  }

  void removeCargoGroup(String id) {
    if (!scene.groups.any((g) => g.id == id)) return;
    scene.select(id);
    scene.deleteSelected();
  }

  String? _placementKey(CargoGroupModel? g) => g == null
      ? null
      : '${g.sectionId}:${g.quantity}:${g.rows}:${g.columns}:${g.layers}:${g.boundingDimensions.lengthMm}:${g.boundingDimensions.widthMm}:${g.boundingDimensions.heightMm}:${g.positionXmm}:${g.positionYmm}:${g.positionZmm}:${g.rotationX}:${g.rotationY}:${g.rotationZ}:${g.needsReview}';

  void _setGroups(List<CargoGroupModel> groups) {
    _updating = true;
    scene.setScene(preset.dimensions, [
      for (final g in groups)
        g.copyWith(
          colorValue:
              entries.where((e) => e.id == g.entryId).firstOrNull?.colorValue ??
              g.colorValue,
        ),
    ]);
    scene.setSections(sections);
    _updating = false;
  }

  void syncPreset(ContainerPresetModel value) {
    if (value.id != preset.id) return;
    if (value.dimensions == preset.dimensions &&
        value.name == preset.name &&
        value.maxPayloadGrams == preset.maxPayloadGrams) {
      return;
    }
    preset = value;
    maxPayloadGrams = value.maxPayloadGrams;
    dirty = true;
    _setGroups(scene.groups);
    for (final s in sections) {
      _repack(s.id);
    }
  }

  void choosePreset(ContainerPresetModel value) {
    preset = value;
    plan = null;
    draftId = uuid.v4();
    sections = ContainerSection.defaults(draftId, value.dimensions.lengthMm);
    entries = [];
    maxPayloadGrams = value.maxPayloadGrams;
    manuallyAdjustedSections.clear();
    needsPacking.clear();
    selectedSectionId = null;
    _setGroups([]);
    dirty = false;
    notifyListeners();
  }

  void focusSection(String id) {
    selectedSectionId = id;
    scene.focusSection(id);
    notifyListeners();
  }

  bool usesPlacedSpaces(String sectionId) =>
      manuallyAdjustedSections.contains(sectionId) ||
      !entries.any((e) => e.sectionId == sectionId && e.isBase);

  List<LoadingSpace> spacesFor(String sectionId) => usesPlacedSpaces(sectionId)
      ? const SectionPackingEngine().spacesForPlacement(
          section: sections.firstWhere((s) => s.id == sectionId),
          container: preset.dimensions,
          groups: scene.groups,
        )
      : const SectionPackingEngine().spacesFor(
          section: sections.firstWhere((s) => s.id == sectionId),
          container: preset.dimensions,
          entries: entries.where((e) => e.sectionId == sectionId).toList(),
          remainingPayloadGrams: maxPayloadGrams,
        );

  Dimensions3 sizeFor(SectionCargoEntry entry) {
    if (entry.spaceId != null) {
      final space = spacesFor(entry.sectionId)
          .where((s) => s.id == entry.spaceId)
          .firstOrNull;
      if (space != null) {
        final d = space.bounds.dimensions;
        return !entry.allowOverhang && space.supportedLengthMm != null
            ? Dimensions3(space.supportedLengthMm!, d.widthMm, d.heightMm)
            : d;
      }
      return const Dimensions3(1, 1, 1);
    }
    return Dimensions3(
      sections.firstWhere((s) => s.id == entry.sectionId).lengthMm,
      preset.dimensions.widthMm,
      preset.dimensions.heightMm,
    );
  }

  (int, int) gridFor(SectionCargoEntry entry) =>
      const SectionPackingEngine().recommendedGrid(sizeFor(entry), entry);

  int capacityFor(SectionCargoEntry entry) {
    if (!entry.isBase &&
        entry.spaceId == null &&
        entries.any((e) => e.sectionId == entry.sectionId && e.isBase)) {
      return spacesFor(entry.sectionId)
          .where((s) => s.parentId == null)
          .fold(0, (n, s) {
            if (!entry.allowOverhang &&
                s.needsOverhang &&
                entry.orientations.every(
                  (o) => o.dimensions.lengthMm > s.supportedLengthMm!,
                )) {
              return n;
            }
            final grid = const SectionPackingEngine().recommendedGrid(
              s.bounds.dimensions,
              entry,
            );
            return n + grid.$1 * grid.$2;
          });
    }
    final size = sizeFor(entry);
    return const SectionPackingEngine().theoreticalCapacity(
      ContainerSection(
        id: entry.sectionId,
        planId: draftId,
        index: 0,
        name: '',
        startXmm: 0,
        lengthMm: size.lengthMm,
      ),
      size,
      entry,
    );
  }

  String addCargo(
    String sectionId,
    CargoPackageModel cargo, {
    String? spaceId,
    bool stage = false,
  }) {
    if (!stage &&
        spaceId == null &&
        scene.loadedGroups.any((g) => g.sectionId == sectionId)) {
      throw StateError('本节已有货物，请从剩余区域选择位置添加');
    }
    // Add only the new block, preserving all existing manual placements.
    if (stage ||
        manuallyAdjustedSections.contains(sectionId) ||
        (spaceId != null &&
            (usesPlacedSpaces(sectionId) ||
                cargo.type == CargoPackageType.pallet ||
                cargo.type == CargoPackageType.crate))) {
      final target = spaceId == null
          ? null
          : spacesFor(sectionId).where((s) => s.id == spaceId).firstOrNull;
      if (spaceId != null && (target == null || !target.isUsefulForLoading)) {
        throw StateError('原空间已变化，请重新选择空间');
      }
      final entry = SectionCargoEntry(
        id: uuid.v4(),
        sectionId: sectionId,
        cargo: cargo,
        quantity: 1,
        allowStack: true,
        manualPlacement: true,
        spaceId: spaceId,
      );
      if (target != null &&
          !_fits(cargo.dimensions, target.bounds.dimensions)) {
        throw StateError('货物尺寸超过所选空间，请选择其他货物或调整摆放');
      }
      entries = [...entries, entry];
      _distinguishColors();
      final staged = scene.groups.where((g) => g.sectionId == null).toList();
      final x = staged.isEmpty
          ? 0
          : staged.map((g) => g.bounds.maxX).reduce((a, b) => a > b ? a : b) +
                100;
      final group = CargoGroupModel(
        id: uuid.v4(),
        planId: draftId,
        cargoPackageId: cargo.id,
        entryId: entry.id,
        sectionId: stage ? null : sectionId,
        quantity: 1,
        rows: 1,
        columns: 1,
        layers: 1,
        emptySlots: 0,
        boundingDimensions: cargo.dimensions,
        positionXmm: stage
            ? x
            : target?.bounds.x ??
                  sections.firstWhere((s) => s.id == sectionId).startXmm,
        positionYmm: stage
            ? -cargo.dimensions.widthMm - 300
            : target?.bounds.y ?? 0,
        positionZmm: target?.bounds.z ?? 0,
        rotationX: 0,
        rotationY: 0,
        rotationZ: 0,
        colorValue: entries.last.colorValue,
        sortOrder: scene.groups.length,
        needsReview: true,
      );
      manuallyAdjustedSections.add(sectionId);
      _setGroups([...scene.groups, group]);
      if (!stage) {
        sectionArrivalRevision++;
        focusSection(sectionId);
      }
      scene.select(group.id);
      dirty = true;
      notifyListeners();
      return entry.id;
    }
    var entry = SectionCargoEntry(
      id: uuid.v4(),
      sectionId: sectionId,
      cargo: cargo,
      spaceId: spaceId,
      quantity:
          cargo.defaultSectionQuantity ??
          (cargo.id == 'cargo-wpc-grille' ? 286 : 1),
      orientation: cargo.type == CargoPackageType.door
          ? PlacementOrientation.upright
          : PlacementOrientation.flat,
      placeOnBottom: cargo.type == CargoPackageType.pallet,
      allowStack: true,
    );
    if (!entry.isBase) {
      final grid = gridFor(entry);
      entry = entry.copyWith(quantity: grid.$1 * grid.$2);
    }
    entries = [...entries, entry];
    _distinguishColors();
    dirty = true;
    needsPacking.add(sectionId);
    selectedSectionId = sectionId;
    _repack(sectionId);
    return entry.id;
  }

  bool _fits(Dimensions3 cargo, Dimensions3 space) =>
      cargo.lengthMm <= space.lengthMm &&
      cargo.widthMm <= space.widthMm &&
      cargo.heightMm <= space.heightMm;

  bool canAddToSpace(
    String sectionId,
    CargoPackageModel cargo,
    LoadingSpace space,
  ) =>
      (!usesPlacedSpaces(sectionId) &&
          cargo.type != CargoPackageType.pallet &&
          cargo.type != CargoPackageType.crate) ||
      _fits(cargo.dimensions, space.bounds.dimensions);

  void updateEntry(SectionCargoEntry entry) {
    final previous = entries.firstWhere((e) => e.id == entry.id);
    if (!entry.isBase &&
        entry.perRow == null &&
        entry.rowCount == null &&
        (previous.orientation != entry.orientation ||
            previous.allowStack != entry.allowStack ||
            previous.allowOverhang != entry.allowOverhang)) {
      final grid = gridFor(entry);
      entry = entry.copyWith(quantity: grid.$1 * grid.$2);
    }
    entries = [
      for (final e in entries)
        if (e.id == entry.id) entry else e,
    ];
    entries = [
      for (final e in entries)
        if (entry.isBase &&
            e.sectionId == entry.sectionId &&
            !e.isBase &&
            e.perRow == null &&
            e.rowCount == null &&
            (e.spaceId == null ||
                spacesFor(e.sectionId).any((s) => s.id == e.spaceId)))
          e.copyWith(quantity: gridFor(e).$1 * gridFor(e).$2)
        else
          e,
    ];
    needsPacking.add(entry.sectionId);
    dirty = true;
    _repack(entry.sectionId);
  }

  /// Keep a cargo's color consistent throughout the plan, while separating
  /// library defaults that happen to use the same (or very similar) green.
  void _distinguishColors() {
    const palette = [
      0xFF79A88C,
      0xFF81AAC8,
      0xFFD3A06D,
      0xFFB18CAF,
      0xFFCEC17D,
      0xFF79B8B2,
      0xFFCC8D89,
    ];
    final assigned = <String, int>{};
    int distance(int a, int b) {
      var sum = 0;
      for (final shift in [0, 8, 16]) {
        final d = ((a >> shift) & 255) - ((b >> shift) & 255);
        sum += d * d;
      }
      return sum;
    }

    entries = [
      for (final e in entries)
        (() {
          var color = assigned[e.cargo.id];
          if (color == null) {
            color = e.colorValue;
            if (assigned.values.any((v) => distance(v, color!) < 2500)) {
              color = palette.reduce((a, b) {
                int nearest(int c) => assigned.values
                    .map((v) => distance(v, c))
                    .reduce((x, y) => x < y ? x : y);
                return nearest(a) >= nearest(b) ? a : b;
              });
            }
            assigned[e.cargo.id] = color;
          }
          return e.copyWith(colorOverride: color);
        })(),
    ];
  }

  void removeEntry(String id) {
    final entry = entries.firstWhere((e) => e.id == id);
    entries = entries.where((e) => e.id != id).toList();
    _setGroups(scene.groups.where((g) => g.entryId != id).toList());
    needsPacking.add(entry.sectionId);
    dirty = true;
    _repack(entry.sectionId);
  }

  void _repack(String sectionId) {
    if (manuallyAdjustedSections.contains(sectionId)) {
      notifyListeners();
      return;
    }
    if (validation == null) {
      pack(sectionId);
    } else {
      notifyListeners();
    }
  }

  /// Acknowledge the shortfall without changing cargo geometry or marking it
  /// stale. An acknowledgement is not proof that the cargo physically fits.
  void acknowledgeUnpacked() {
    entries = [
      for (final entry in entries)
        if (!needsPacking.contains(entry.sectionId) &&
            packedFor(entry.id) < entry.quantity)
          entry.copyWith(manualQuantityOverride: true)
        else
          entry,
    ];
    dirty = true;
    notifyListeners();
  }

  void setSections(List<int> lengths) {
    var x = 0;
    final next = <ContainerSection>[];
    for (var i = 0; i < lengths.length; i++) {
      next.add(
        ContainerSection(
          id: i < sections.length ? sections[i].id : uuid.v4(),
          planId: draftId,
          index: i,
          name: '第${i + 1}节',
          startXmm: x,
          lengthMm: lengths[i],
        ),
      );
      x += lengths[i];
    }
    final error = ContainerSection.validate(next, preset.dimensions.lengthMm);
    if (error != null) throw ArgumentError(error);
    final kept = next.map((s) => s.id).toSet();
    if (entries.any((e) => !kept.contains(e.sectionId))) {
      throw StateError('请先移除待删除分节中的货物条目，避免丢失柜内或暂存区货物。');
    }
    entries = entries.where((e) => kept.contains(e.sectionId)).toList();
    // Preserve positions as requested, mark incompatible old geometry for review.
    final old = {for (final s in sections) s.id: s};
    sections = next;
    _setGroups([
      for (final g in scene.groups)
        if (g.sectionId == null)
          g
        else if (kept.contains(g.sectionId))
          g.copyWith(
            needsReview:
                g.needsReview ||
                old[g.sectionId]?.startXmm !=
                    next.firstWhere((s) => s.id == g.sectionId).startXmm ||
                g.bounds.maxX >
                    next.firstWhere((s) => s.id == g.sectionId).endXmm,
          ),
    ]);
    needsPacking.addAll(kept);
    dirty = true;
    for (final s in sections) {
      _repack(s.id);
    }
  }

  void setClearance(int value) {
    // Compatibility only: carton dimensions already include user allowances.
  }

  SectionPackingResult pack(String sectionId) {
    if (validation != null) throw ArgumentError(validation);
    if (scene.groups.any((g) {
      final source = entries.where((e) => e.id == g.entryId).firstOrNull;
      return source != null &&
          source.sectionId != g.sectionId &&
          (source.sectionId == sectionId || g.sectionId == sectionId);
    })) {
      throw StateError('此分节有关联的手动搬运货物，请先移回原分节再重新计算，避免覆盖人工摆放。');
    }
    final other = scene.groups.where((g) => g.sectionId != sectionId).toList();
    final usedWeight = other
        .where((g) => g.sectionId != null)
        .fold<int>(
          0,
          (a, g) =>
              a +
              g.quantity *
                  (entries
                          .where((e) => e.id == g.entryId)
                          .firstOrNull
                          ?.cargo
                          .weightGrams ??
                      0),
        );
    final result = const SectionPackingEngine().pack(
      section: sections.firstWhere((s) => s.id == sectionId),
      container: preset.dimensions,
      entries: entries.where((e) => e.sectionId == sectionId).toList(),
      remainingPayloadGrams: maxPayloadGrams - usedWeight,
    );
    _setGroups([...other, ...result.groups]);
    manuallyAdjustedSections.remove(sectionId);
    entries = [
      for (final e in entries)
        if (e.sectionId == sectionId) e.copyWith(manualPlacement: false) else e,
    ];
    needsPacking.remove(sectionId);
    selectedSectionId = sectionId;
    scene.focusSection(sectionId);
    dirty = true;
    notifyListeners();
    return result;
  }

  Future<void> open(String id, List<ContainerPresetModel> presets) async {
    busy = true;
    notifyListeners();
    try {
      final saved = await repository.loadSectionPlan(id);
      preset = presets.firstWhere((p) => p.id == saved.plan.containerPresetId);
      plan = saved.plan;
      draftId = saved.plan.id;
      sections = saved.sections;
      entries = saved.entries;
      _distinguishColors();
      // Earlier versions disabled pallet stacking by default, which also
      // incorrectly suppressed the entire space above the pallet.
      final legacyPallets = entries
          .where((e) => e.legacyStackDefault)
          .map((e) => e.sectionId)
          .toSet();
      entries = [
        for (final e in entries)
          if (e.legacyStackDefault) e.copyWith(allowStack: true) else e,
      ];
      entries = [for (final e in entries) _restoreGrid(e)];
      maxPayloadGrams = saved.plan.maxPayloadGrams;
      needsPacking.clear();
      manuallyAdjustedSections.clear();
      manuallyAdjustedSections.addAll(
        entries.where((e) => e.manualPlacement).map((e) => e.sectionId),
      );
      selectedSectionId = null;
      _setGroups(saved.groups);
      for (final group in saved.groups) {
        final source = entries
            .where((entry) => entry.id == group.entryId)
            .firstOrNull;
        if (group.needsReview || group.sectionId != source?.sectionId) {
          if (group.sectionId != null) {
            manuallyAdjustedSections.add(group.sectionId!);
          }
          if (source != null) manuallyAdjustedSections.add(source.sectionId);
        }
      }
      // Valid manual moves/resizes need not carry a conflict warning. Recognize
      // their persisted geometry as well, so reopening never restores stale
      // automatic space suggestions over the actual cargo.
      for (final section in sections) {
        if (validation != null) {
          manuallyAdjustedSections.add(section.id);
          continue;
        }
        if (legacyPallets.contains(section.id) ||
            manuallyAdjustedSections.contains(section.id)) {
          continue;
        }
        final actual = scene.groups
            .where((g) => g.sectionId == section.id)
            .toList();
        final otherWeight = scene.groups
            .where((g) => g.sectionId != null && g.sectionId != section.id)
            .fold<int>(
              0,
              (n, g) =>
                  n +
                  g.quantity *
                      (entries
                              .where((e) => e.id == g.entryId)
                              .firstOrNull
                              ?.cargo
                              .weightGrams ??
                          0),
            );
        final automatic = const SectionPackingEngine()
            .pack(
              section: section,
              container: preset.dimensions,
              entries: entries.where((e) => e.sectionId == section.id).toList(),
              remainingPayloadGrams: (maxPayloadGrams - otherWeight).clamp(
                0,
                maxPayloadGrams,
              ),
            )
            .groups;
        List<String> layout(List<CargoGroupModel> groups) => [
          for (final g in groups)
            '${g.entryId}:${g.cargoPackageId}:${_placementKey(g)}',
        ]..sort();
        if (!listEquals(layout(actual), layout(automatic))) {
          manuallyAdjustedSections.add(section.id);
        }
      }
      dirty = false;
      _syncManualQuantities(
        entries
            .where(
              (e) =>
                  !e.manualQuantityOverride &&
                  manuallyAdjustedSections.contains(e.sectionId),
            )
            .map((e) => e.id)
            .toSet(),
      );
      for (final id in legacyPallets) {
        _repack(id);
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> save(String name) async {
    if (validation != null) throw ArgumentError(validation);
    busy = true;
    notifyListeners();
    try {
      final now = DateTime.now();
      final title = name.trim().isEmpty
          ? '${preset.name} · ${now.month.toString().padLeft(2, '0')}月${now.day.toString().padLeft(2, '0')}日 ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}'
          : name.trim();
      final saved = LoadingPlanModel(
        id: draftId,
        name: title,
        containerPresetId: preset.id,
        maxPayloadGrams: maxPayloadGrams,
        clearanceMm: clearanceMm,
        createdAt: plan?.createdAt ?? now,
        updatedAt: now,
      );
      await repository.saveSectionPlan(
        SectionPlanSnapshot(
          plan: saved,
          sections: sections,
          entries: entries,
          groups: scene.groups,
        ),
      );
      plan = saved;
      dirty = false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  SectionCargoEntry _restoreGrid(SectionCargoEntry e) {
    if (e.isBase || e.perRow != null || e.rowCount != null) return e;
    var row = gridFor(e).$1;
    if (row <= 0) row = 1;
    while (row > 1 && e.quantity % row != 0) {
      row--;
    }
    return e.copyWith(perRow: row, rowCount: e.quantity ~/ row);
  }

  Future<void> rename(String id, String name) async {
    await repository.renamePlan(id, name);
    final current = plan;
    if (current != null && current.id == id) {
      plan = LoadingPlanModel(
        id: id,
        name: name.trim(),
        containerPresetId: current.containerPresetId,
        maxPayloadGrams: current.maxPayloadGrams,
        clearanceMm: current.clearanceMm,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
      );
      notifyListeners();
    }
  }

  @override
  void dispose() {
    scene.removeListener(_sceneChanged);
    scene.dispose();
    super.dispose();
  }
}
