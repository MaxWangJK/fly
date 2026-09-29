import 'dart:math' as math;

enum CargoPackageType { package, pallet, crate, door, custom }

enum LoadLimitFactor { space, weight, both }

class Dimensions3 {
  const Dimensions3(this.lengthMm, this.widthMm, this.heightMm)
    : assert(lengthMm > 0),
      assert(widthMm > 0),
      assert(heightMm > 0);

  final int lengthMm;
  final int widthMm;
  final int heightMm;

  int get volumeMm3 => lengthMm * widthMm * heightMm;

  Dimensions3 withClearance(int clearanceMm) =>
      this; // Legacy API, no allowance added.

  @override
  bool operator ==(Object other) =>
      other is Dimensions3 &&
      lengthMm == other.lengthMm &&
      widthMm == other.widthMm &&
      heightMm == other.heightMm;

  @override
  int get hashCode => Object.hash(lengthMm, widthMm, heightMm);
}

class ContainerPresetModel {
  const ContainerPresetModel({
    required this.id,
    required this.name,
    required this.dimensions,
    required this.maxPayloadGrams,
    required this.colorValue,
    required this.isBuiltIn,
    this.doorWidthMm,
    this.doorHeightMm,
  });

  final String id;
  final String name;
  final Dimensions3 dimensions;
  final int maxPayloadGrams;
  final int colorValue;
  final bool isBuiltIn;
  final int? doorWidthMm;
  final int? doorHeightMm;

  double get maxPayloadKg => maxPayloadGrams / 1000;
}

class CargoPackageModel {
  const CargoPackageModel({
    required this.id,
    required this.name,
    required this.dimensions,
    required this.weightGrams,
    required this.colorValue,
    this.type = CargoPackageType.package,
    this.allowRotateX = true,
    this.allowRotateY = true,
    this.allowRotateZ = true,
    this.stackable = true,
    this.defaultSectionQuantity,
  });

  final String id;
  final String name;
  final CargoPackageType type;
  final Dimensions3 dimensions;
  final int weightGrams;
  final int colorValue;
  final bool allowRotateX;
  final bool allowRotateY;
  final bool allowRotateZ;
  final bool stackable;
  final int? defaultSectionQuantity;

  double get weightKg => weightGrams / 1000;

  List<CargoOrientation> get orientations {
    final values = <CargoOrientation>[
      CargoOrientation(dimensions: dimensions),
      if (allowRotateX)
        CargoOrientation(
          dimensions: Dimensions3(
            dimensions.lengthMm,
            dimensions.heightMm,
            dimensions.widthMm,
          ),
          rotationX: 90,
        ),
      if (allowRotateY)
        CargoOrientation(
          dimensions: Dimensions3(
            dimensions.heightMm,
            dimensions.widthMm,
            dimensions.lengthMm,
          ),
          rotationY: 90,
        ),
      if (allowRotateZ)
        CargoOrientation(
          dimensions: Dimensions3(
            dimensions.widthMm,
            dimensions.lengthMm,
            dimensions.heightMm,
          ),
          rotationZ: 90,
        ),
      if (allowRotateX && allowRotateY)
        CargoOrientation(
          dimensions: Dimensions3(
            dimensions.widthMm,
            dimensions.heightMm,
            dimensions.lengthMm,
          ),
          rotationX: 90,
          rotationY: 90,
        ),
      if (allowRotateX && allowRotateZ)
        CargoOrientation(
          dimensions: Dimensions3(
            dimensions.heightMm,
            dimensions.lengthMm,
            dimensions.widthMm,
          ),
          rotationX: 90,
          rotationZ: 90,
        ),
    ];
    final unique = <Dimensions3>{};
    return [
      for (final value in values)
        if (unique.add(value.dimensions)) value,
    ];
  }
}

class CargoOrientation {
  const CargoOrientation({
    required this.dimensions,
    this.rotationX = 0,
    this.rotationY = 0,
    this.rotationZ = 0,
  });

  final Dimensions3 dimensions;
  final int rotationX;
  final int rotationY;
  final int rotationZ;
}

class LoadingPlanModel {
  const LoadingPlanModel({
    required this.id,
    required this.name,
    required this.containerPresetId,
    required this.maxPayloadGrams,
    required this.clearanceMm,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String containerPresetId;
  final int maxPayloadGrams;
  final int clearanceMm;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class CargoGroupModel {
  const CargoGroupModel({
    required this.id,
    required this.planId,
    required this.cargoPackageId,
    required this.quantity,
    required this.rows,
    required this.columns,
    required this.layers,
    required this.emptySlots,
    required this.boundingDimensions,
    required this.positionXmm,
    required this.positionYmm,
    required this.positionZmm,
    required this.rotationX,
    required this.rotationY,
    required this.rotationZ,
    required this.colorValue,
    required this.sortOrder,
    this.sectionId,
    this.entryId,
    this.needsReview = false,
    this.allowStack = true,
  });

  final String id;
  final String planId;
  final String cargoPackageId;
  final int quantity;
  final int rows;
  final int columns;
  final int layers;
  final int emptySlots;
  final Dimensions3 boundingDimensions;
  final int positionXmm;
  final int positionYmm;
  final int positionZmm;
  final int rotationX;
  final int rotationY;
  final int rotationZ;
  final int colorValue;
  final int sortOrder;
  final String? sectionId;
  final String? entryId;
  final bool needsReview;
  final bool allowStack;

  Aabb3 get bounds => Aabb3(
    x: positionXmm,
    y: positionYmm,
    z: positionZmm,
    dimensions: boundingDimensions,
  );

  CargoGroupModel copyWith({
    String? id,
    String? planId,
    String? sectionId,
    bool clearSection = false,
    String? entryId,
    bool? needsReview,
    bool? allowStack,
    int? quantity,
    int? rows,
    int? columns,
    int? layers,
    int? emptySlots,
    Dimensions3? boundingDimensions,
    int? positionXmm,
    int? positionYmm,
    int? positionZmm,
    int? rotationX,
    int? rotationY,
    int? rotationZ,
    int? colorValue,
  }) => CargoGroupModel(
    id: id ?? this.id,
    planId: planId ?? this.planId,
    cargoPackageId: cargoPackageId,
    quantity: quantity ?? this.quantity,
    rows: rows ?? this.rows,
    columns: columns ?? this.columns,
    layers: layers ?? this.layers,
    emptySlots: emptySlots ?? this.emptySlots,
    boundingDimensions: boundingDimensions ?? this.boundingDimensions,
    positionXmm: positionXmm ?? this.positionXmm,
    positionYmm: positionYmm ?? this.positionYmm,
    positionZmm: positionZmm ?? this.positionZmm,
    rotationX: rotationX ?? this.rotationX,
    rotationY: rotationY ?? this.rotationY,
    rotationZ: rotationZ ?? this.rotationZ,
    colorValue: colorValue ?? this.colorValue,
    sortOrder: sortOrder,
    sectionId: clearSection ? null : sectionId ?? this.sectionId,
    entryId: entryId ?? this.entryId,
    needsReview: needsReview ?? this.needsReview,
    allowStack: allowStack ?? this.allowStack,
  );
}

class Aabb3 {
  const Aabb3({
    required this.x,
    required this.y,
    required this.z,
    required this.dimensions,
  });

  final int x;
  final int y;
  final int z;
  final Dimensions3 dimensions;

  int get maxX => x + dimensions.lengthMm;
  int get maxY => y + dimensions.widthMm;
  int get maxZ => z + dimensions.heightMm;

  bool overlaps(Aabb3 other) =>
      x < other.maxX &&
      maxX > other.x &&
      y < other.maxY &&
      maxY > other.y &&
      z < other.maxZ &&
      maxZ > other.z;

  bool inside(Dimensions3 container) =>
      x >= 0 &&
      y >= 0 &&
      z >= 0 &&
      maxX <= container.lengthMm &&
      maxY <= container.widthMm &&
      maxZ <= container.heightMm;
}

class LoadingSummary {
  const LoadingSummary({
    required this.packedCount,
    required this.unpackedCount,
    required this.totalWeightGrams,
    required this.cargoVolumeMm3,
    required this.container,
    required this.maxPayloadGrams,
  });

  final int packedCount;
  final int unpackedCount;
  final int totalWeightGrams;
  final int cargoVolumeMm3;
  final Dimensions3 container;
  final int maxPayloadGrams;

  double get volumeUtilization =>
      math.min(1, cargoVolumeMm3 / math.max(1, container.volumeMm3));
  double get weightUtilization =>
      math.min(1, totalWeightGrams / math.max(1, maxPayloadGrams));
}
