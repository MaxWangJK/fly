import 'container_loading_models.dart';

enum PlacementOrientation { flat, upright, side, automatic }

enum HorizontalPlacement { automatic, left, center, right }

class ContainerSection {
  const ContainerSection({
    required this.id,
    required this.planId,
    required this.index,
    required this.name,
    required this.startXmm,
    required this.lengthMm,
  });
  final String id;
  final String planId;
  final int index;
  final String name;
  final int startXmm;
  final int lengthMm;
  int get endXmm => startXmm + lengthMm;
  ContainerSection copyWith({
    String? planId,
    int? index,
    String? name,
    int? startXmm,
    int? lengthMm,
  }) => ContainerSection(
    id: id,
    planId: planId ?? this.planId,
    index: index ?? this.index,
    name: name ?? this.name,
    startXmm: startXmm ?? this.startXmm,
    lengthMm: lengthMm ?? this.lengthMm,
  );

  static List<ContainerSection> defaults(String planId, int lengthMm) {
    final count = lengthMm ~/ 2900;
    if (count == 0) {
      return [
        ContainerSection(
          id: '$planId-section-0',
          planId: planId,
          index: 0,
          name: '第一节',
          startXmm: 0,
          lengthMm: lengthMm,
        ),
      ];
    }
    return [
      for (var i = 0; i < count; i++)
        ContainerSection(
          id: '$planId-section-$i',
          planId: planId,
          index: i,
          name: '第${i + 1}节',
          startXmm: i * 2900,
          lengthMm: 2900,
        ),
    ];
  }

  static String? validate(
    List<ContainerSection> sections,
    int containerLength,
  ) {
    if (sections.isEmpty) return '至少需要一个分节';
    var cursor = 0;
    for (final section in sections) {
      if (section.lengthMm <= 0) return '每节长度必须大于 0';
      if (section.startXmm != cursor) return '分节必须按顺序连续排列';
      cursor += section.lengthMm;
    }
    if (cursor > containerLength) {
      return '分节总长度 ${(cursor / 1000).toStringAsFixed(2)}m 超过集装箱 ${(containerLength / 1000).toStringAsFixed(2)}m';
    }
    return null;
  }
}

class SectionCargoEntry {
  const SectionCargoEntry({
    required this.id,
    required this.sectionId,
    required this.cargo,
    required this.quantity,
    this.orientation = PlacementOrientation.flat,
    this.placeOnBottom = false,
    this.allowStack = true,
    this.horizontalPlacement = HorizontalPlacement.automatic,
    this.manualQuantityOverride = false,
    this.manualPlacement = false,
    this.colorOverride,
    this.perRow,
    this.rowCount,
    this.spaceId,
    this.allowOverhang = true,
    this.legacyStackDefault = false,
  });
  final String id;
  final String sectionId;
  // A snapshot protects saved plans from subsequent cargo-library edits/deletes.
  final CargoPackageModel cargo;
  final int quantity;
  final PlacementOrientation orientation;
  final bool placeOnBottom;
  final bool allowStack;
  final HorizontalPlacement horizontalPlacement;
  final bool manualQuantityOverride;
  final bool manualPlacement;
  final int? colorOverride;
  final int? perRow;
  final int? rowCount;
  final String? spaceId;
  final bool allowOverhang;
  final bool legacyStackDefault;
  bool get isBase =>
      cargo.type == CargoPackageType.pallet ||
      cargo.type == CargoPackageType.crate;
  int get colorValue => colorOverride ?? cargo.colorValue;
  SectionCargoEntry copyWith({
    int? quantity,
    PlacementOrientation? orientation,
    bool? placeOnBottom,
    bool? allowStack,
    HorizontalPlacement? horizontalPlacement,
    bool? manualQuantityOverride,
    bool? manualPlacement,
    int? colorOverride,
    int? perRow,
    int? rowCount,
    String? spaceId,
    bool? allowOverhang,
  }) => SectionCargoEntry(
    id: id,
    sectionId: sectionId,
    cargo: cargo,
    quantity: quantity ?? this.quantity,
    orientation: orientation ?? this.orientation,
    placeOnBottom: placeOnBottom ?? this.placeOnBottom,
    allowStack: allowStack ?? this.allowStack,
    horizontalPlacement: horizontalPlacement ?? this.horizontalPlacement,
    manualQuantityOverride:
        manualQuantityOverride ?? this.manualQuantityOverride,
    manualPlacement: manualPlacement ?? this.manualPlacement,
    colorOverride: colorOverride ?? this.colorOverride,
    perRow: perRow ?? this.perRow,
    rowCount: rowCount ?? this.rowCount,
    spaceId: spaceId ?? this.spaceId,
    allowOverhang: allowOverhang ?? this.allowOverhang,
    legacyStackDefault: legacyStackDefault,
  );

  List<CargoOrientation> get orientations {
    final d = cargo.dimensions;
    return switch (orientation) {
      PlacementOrientation.flat => [CargoOrientation(dimensions: d)],
      PlacementOrientation.side => [
        CargoOrientation(
          dimensions: Dimensions3(d.lengthMm, d.heightMm, d.widthMm),
          rotationX: 90,
        ),
      ],
      PlacementOrientation.upright => [
        CargoOrientation(
          dimensions: Dimensions3(d.widthMm, d.heightMm, d.lengthMm),
          rotationX: 90,
          rotationY: 90,
        ),
      ],
      PlacementOrientation.automatic => CargoPackageModel(
        id: cargo.id,
        name: cargo.name,
        dimensions: d,
        weightGrams: cargo.weightGrams,
        colorValue: colorValue,
      ).orientations,
    };
  }
}

class LoadingSpace {
  const LoadingSpace({
    required this.id,
    required this.name,
    required this.bounds,
    this.supportedLengthMm,
    this.parentId,
  });
  final String id, name;
  final String? parentId;
  final Aabb3 bounds;
  final int? supportedLengthMm;

  /// Labels follow the current visible areas; stable geometry IDs keep saved
  /// allocations independent of labels, including more than 26 areas.
  static String areaName(int index) {
    var n = index + 1;
    var letters = '';
    while (n > 0) {
      n--;
      letters = String.fromCharCode(65 + n % 26) + letters;
      n ~/= 26;
    }
    return '$letters区';
  }

  bool get isUsefulForLoading =>
      bounds.dimensions.widthMm >= 500 && bounds.dimensions.heightMm >= 500;

  /// Presentation projection only. Keep precise geometry and old assignments
  /// in the packing engine, even when a small empty remainder is not offered.
  static List<LoadingSpace> suggested(
    List<LoadingSpace> spaces,
    Iterable<String> assignedIds,
  ) {
    final keep = {
      ...assignedIds,
      for (final s in spaces)
        if (s.isUsefulForLoading) s.id,
    };
    final byId = {for (final s in spaces) s.id: s};
    for (final id in keep.toList()) {
      var parent = byId[id]?.parentId;
      final visited = <String>{};
      while (parent != null && visited.add(parent)) {
        keep.add(parent);
        parent = byId[parent]?.parentId;
      }
    }
    final visible = spaces.where((s) => keep.contains(s.id)).toList();
    return [
      for (final (i, s) in visible.indexed)
        LoadingSpace(
          id: s.id,
          name: areaName(i),
          bounds: s.bounds,
          parentId: s.parentId,
          supportedLengthMm: s.supportedLengthMm,
        ),
    ];
  }

  bool get needsOverhang =>
      supportedLengthMm != null &&
      supportedLengthMm! < bounds.dimensions.lengthMm;
}

class SectionPlanSnapshot {
  const SectionPlanSnapshot({
    required this.plan,
    required this.sections,
    required this.entries,
    required this.groups,
  });
  final LoadingPlanModel plan;
  final List<ContainerSection> sections;
  final List<SectionCargoEntry> entries;
  final List<CargoGroupModel> groups;
}
