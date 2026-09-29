import 'dart:math' as math;

import '../models/container_loading_models.dart';

class PackingItem {
  const PackingItem({required this.cargo, required this.quantity});

  final CargoPackageModel cargo;
  final int quantity;
}

class PackingRequest {
  const PackingRequest({
    required this.container,
    required this.maxPayloadGrams,
    required this.items,
    int clearanceMm = 0,
    this.preferHeavyItemsLow = true,
  });

  final Dimensions3 container;
  final int maxPayloadGrams;
  final List<PackingItem> items;
  int get clearanceMm =>
      0; // Legacy argument ignored; dimensions include allowances.
  final bool preferHeavyItemsLow;
}

class GridPackingEvaluation {
  const GridPackingEvaluation({
    required this.orientation,
    required this.sections,
    required this.rows,
    required this.layers,
    required this.spaceCapacity,
    required this.weightCapacity,
    required this.maximumLoad,
    required this.limitFactor,
    required this.remainingLengthMm,
    required this.remainingWidthMm,
    required this.remainingHeightMm,
  });

  final CargoOrientation orientation;
  final int sections;
  final int rows;
  final int layers;
  final int spaceCapacity;
  final int weightCapacity;
  final int maximumLoad;
  final LoadLimitFactor limitFactor;
  final int remainingLengthMm;
  final int remainingWidthMm;
  final int remainingHeightMm;

  int get sectionCapacity => rows * layers;
}

class PackedItem {
  const PackedItem({
    required this.cargoId,
    required this.instanceIndex,
    required this.positionXmm,
    required this.positionYmm,
    required this.positionZmm,
    required this.orientation,
  });

  final String cargoId;
  final int instanceIndex;
  final int positionXmm;
  final int positionYmm;
  final int positionZmm;
  final CargoOrientation orientation;
}

class PackedGroup {
  const PackedGroup({
    required this.cargo,
    required this.quantity,
    required this.rows,
    required this.layers,
    required this.emptySlots,
    required this.dimensions,
    required this.positionXmm,
    required this.positionYmm,
    required this.positionZmm,
    required this.orientation,
  });

  final CargoPackageModel cargo;
  final int quantity;
  final int rows;
  final int layers;
  final int emptySlots;
  final Dimensions3 dimensions;
  final int positionXmm;
  final int positionYmm;
  final int positionZmm;
  final CargoOrientation orientation;
}

class PackingFailure {
  const PackingFailure({required this.cargoId, required this.unpackedCount});

  final String cargoId;
  final int unpackedCount;
}

class PackingResult {
  const PackingResult({
    required this.packedItems,
    required this.groups,
    required this.failures,
    required this.summary,
    this.grid,
  });

  final List<PackedItem> packedItems;
  final List<PackedGroup> groups;
  final List<PackingFailure> failures;
  final LoadingSummary summary;
  final GridPackingEvaluation? grid;

  int get packedCount => summary.packedCount;
  int get unpackedCount => summary.unpackedCount;
}

class WeightDistributionResult {
  const WeightDistributionResult({
    required this.frontWeightGrams,
    required this.rearWeightGrams,
  });

  final int frontWeightGrams;
  final int rearWeightGrams;

  int get totalWeightGrams => frontWeightGrams + rearWeightGrams;
  double get differenceRatio => totalWeightGrams == 0
      ? 0
      : (frontWeightGrams - rearWeightGrams).abs() / totalWeightGrams;
  bool get isUnbalanced => totalWeightGrams > 0 && differenceRatio > .30;
}

WeightDistributionResult calculateWeightDistribution(
  Iterable<PackedGroup> groups,
  int containerLengthMm,
) {
  var front = 0;
  var rear = 0;
  for (final group in groups) {
    final weight = group.quantity * group.cargo.weightGrams;
    final center = group.positionXmm + group.dimensions.lengthMm / 2;
    if (center <= containerLengthMm / 2) {
      front += weight;
    } else {
      rear += weight;
    }
  }
  return WeightDistributionResult(
    frontWeightGrams: front,
    rearWeightGrams: rear,
  );
}

abstract interface class PackingEngine {
  PackingResult pack(PackingRequest request);
}

class SingleSkuGridPackingEngine implements PackingEngine {
  const SingleSkuGridPackingEngine();

  GridPackingEvaluation evaluate(
    Dimensions3 container,
    CargoPackageModel cargo,
    int maxPayloadGrams, {
    int clearanceMm = 0,
  }) {
    GridPackingEvaluation? best;
    for (final orientation in cargo.orientations) {
      final effective = orientation.dimensions.withClearance(clearanceMm);
      final sections = container.lengthMm ~/ effective.lengthMm;
      final rows = container.widthMm ~/ effective.widthMm;
      final layers = cargo.stackable
          ? container.heightMm ~/ effective.heightMm
          : math.min(1, container.heightMm ~/ effective.heightMm);
      final spaceCapacity = sections * rows * layers;
      final weightCapacity = cargo.weightGrams <= 0
          ? spaceCapacity
          : maxPayloadGrams ~/ cargo.weightGrams;
      final maximumLoad = math.min(spaceCapacity, weightCapacity);
      final factor = spaceCapacity == weightCapacity
          ? LoadLimitFactor.both
          : spaceCapacity < weightCapacity
          ? LoadLimitFactor.space
          : LoadLimitFactor.weight;
      final candidate = GridPackingEvaluation(
        orientation: orientation,
        sections: sections,
        rows: rows,
        layers: layers,
        spaceCapacity: spaceCapacity,
        weightCapacity: weightCapacity,
        maximumLoad: maximumLoad,
        limitFactor: factor,
        remainingLengthMm: container.lengthMm - sections * effective.lengthMm,
        remainingWidthMm: container.widthMm - rows * effective.widthMm,
        remainingHeightMm: container.heightMm - layers * effective.heightMm,
      );
      if (best == null || candidate.maximumLoad > best.maximumLoad) {
        best = candidate;
      }
    }
    return best!;
  }

  @override
  PackingResult pack(PackingRequest request) {
    if (request.items.length != 1) {
      throw ArgumentError('SingleSkuGridPackingEngine requires one cargo SKU');
    }
    final item = request.items.single;
    final grid = evaluate(
      request.container,
      item.cargo,
      request.maxPayloadGrams,
      clearanceMm: request.clearanceMm,
    );
    final packedCount = math.min(item.quantity, grid.maximumLoad);
    final effective = grid.orientation.dimensions.withClearance(
      request.clearanceMm,
    );
    final packed = <PackedItem>[];
    final groups = <PackedGroup>[];
    final perSection = math.max(1, grid.sectionCapacity);
    for (var index = 0; index < packedCount; index++) {
      final section = index ~/ perSection;
      final within = index % perSection;
      final layer = within ~/ grid.rows;
      final row = within % grid.rows;
      packed.add(
        PackedItem(
          cargoId: item.cargo.id,
          instanceIndex: index,
          positionXmm: section * effective.lengthMm,
          positionYmm: row * effective.widthMm,
          positionZmm: layer * effective.heightMm,
          orientation: grid.orientation,
        ),
      );
    }
    final sectionCount = packedCount == 0
        ? 0
        : ((packedCount - 1) ~/ perSection) + 1;
    for (var section = 0; section < sectionCount; section++) {
      final quantity = math.min(perSection, packedCount - section * perSection);
      final usedRows = math.min(grid.rows, quantity);
      final usedLayers = (quantity + grid.rows - 1) ~/ grid.rows;
      groups.add(
        PackedGroup(
          cargo: item.cargo,
          quantity: quantity,
          rows: usedRows,
          layers: usedLayers,
          emptySlots: usedRows * usedLayers - quantity,
          dimensions: Dimensions3(
            grid.orientation.dimensions.lengthMm,
            (usedRows - 1) * effective.widthMm +
                grid.orientation.dimensions.widthMm,
            (usedLayers - 1) * effective.heightMm +
                grid.orientation.dimensions.heightMm,
          ),
          positionXmm: section * effective.lengthMm,
          positionYmm: 0,
          positionZmm: 0,
          orientation: grid.orientation,
        ),
      );
    }
    final unpacked = math.max(0, item.quantity - packedCount);
    return PackingResult(
      packedItems: packed,
      groups: groups,
      failures: unpacked == 0
          ? const []
          : [PackingFailure(cargoId: item.cargo.id, unpackedCount: unpacked)],
      grid: grid,
      summary: LoadingSummary(
        packedCount: packedCount,
        unpackedCount: unpacked,
        totalWeightGrams: packedCount * item.cargo.weightGrams,
        cargoVolumeMm3: packedCount * item.cargo.dimensions.volumeMm3,
        container: request.container,
        maxPayloadGrams: request.maxPayloadGrams,
      ),
    );
  }
}

/// A deterministic slab heuristic: heavier SKUs are assigned low, regular
/// cross-sections first and every slab advances along container X. It favors
/// predictable loading blocks over a visually fragmented theoretical optimum.
class MultiSkuHeuristicPackingEngine implements PackingEngine {
  const MultiSkuHeuristicPackingEngine();

  @override
  PackingResult pack(PackingRequest request) {
    final ordered = [...request.items];
    if (request.preferHeavyItemsLow) {
      ordered.sort(
        (a, b) => b.cargo.weightGrams.compareTo(a.cargo.weightGrams),
      );
    }
    var cursorX = 0;
    var remainingWeight = request.maxPayloadGrams;
    var totalWeight = 0;
    var totalVolume = 0;
    var packedCount = 0;
    var requestedCount = 0;
    final groups = <PackedGroup>[];
    final packed = <PackedItem>[];
    final failures = <PackingFailure>[];
    const gridEngine = SingleSkuGridPackingEngine();

    for (final item in ordered) {
      requestedCount += item.quantity;
      if (cursorX >= request.container.lengthMm || remainingWeight <= 0) {
        failures.add(
          PackingFailure(cargoId: item.cargo.id, unpackedCount: item.quantity),
        );
        continue;
      }
      final available = Dimensions3(
        request.container.lengthMm - cursorX,
        request.container.widthMm,
        request.container.heightMm,
      );
      final evaluation = gridEngine.evaluate(
        available,
        item.cargo,
        remainingWeight,
        clearanceMm: request.clearanceMm,
      );
      final count = math.min(item.quantity, evaluation.maximumLoad);
      final perSection = math.max(1, evaluation.sectionCapacity);
      final sections = count == 0 ? 0 : ((count - 1) ~/ perSection) + 1;
      final baseX = cursorX;
      for (var section = 0; section < sections; section++) {
        final quantity = math.min(perSection, count - section * perSection);
        final usedRows = math.min(evaluation.rows, quantity);
        final usedLayers = (quantity + evaluation.rows - 1) ~/ evaluation.rows;
        final effective = evaluation.orientation.dimensions.withClearance(
          request.clearanceMm,
        );
        groups.add(
          PackedGroup(
            cargo: item.cargo,
            quantity: quantity,
            rows: usedRows,
            layers: usedLayers,
            emptySlots: usedRows * usedLayers - quantity,
            dimensions: Dimensions3(
              evaluation.orientation.dimensions.lengthMm,
              (usedRows - 1) * effective.widthMm +
                  evaluation.orientation.dimensions.widthMm,
              (usedLayers - 1) * effective.heightMm +
                  evaluation.orientation.dimensions.heightMm,
            ),
            positionXmm: cursorX + section * effective.lengthMm,
            positionYmm: 0,
            positionZmm: 0,
            orientation: evaluation.orientation,
          ),
        );
      }
      for (var index = 0; index < count; index++) {
        final section = index ~/ perSection;
        final within = index % perSection;
        final layer = within ~/ evaluation.rows;
        final row = within % evaluation.rows;
        packed.add(
          PackedItem(
            cargoId: item.cargo.id,
            instanceIndex: index,
            positionXmm:
                baseX +
                section *
                    (evaluation.orientation.dimensions.lengthMm +
                        request.clearanceMm),
            positionYmm:
                row *
                (evaluation.orientation.dimensions.widthMm +
                    request.clearanceMm),
            positionZmm:
                layer *
                (evaluation.orientation.dimensions.heightMm +
                    request.clearanceMm),
            orientation: evaluation.orientation,
          ),
        );
      }
      final effectiveLength =
          evaluation.orientation.dimensions.lengthMm + request.clearanceMm;
      cursorX += sections * effectiveLength;
      packedCount += count;
      totalWeight += count * item.cargo.weightGrams;
      totalVolume += count * item.cargo.dimensions.volumeMm3;
      remainingWeight -= count * item.cargo.weightGrams;
      final unpacked = item.quantity - count;
      if (unpacked > 0) {
        failures.add(
          PackingFailure(cargoId: item.cargo.id, unpackedCount: unpacked),
        );
      }
    }

    return PackingResult(
      packedItems: packed,
      groups: groups,
      failures: failures,
      summary: LoadingSummary(
        packedCount: packedCount,
        unpackedCount: requestedCount - packedCount,
        totalWeightGrams: totalWeight,
        cargoVolumeMm3: totalVolume,
        container: request.container,
        maxPayloadGrams: request.maxPayloadGrams,
      ),
    );
  }
}
