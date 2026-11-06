import 'dart:math' as math;

import '../models/container_loading_models.dart';
import '../models/section_models.dart';

class SectionPackingResult {
  const SectionPackingResult({
    required this.groups,
    required this.packedByEntry,
    required this.requestedByEntry,
    required this.weightGrams,
    this.spaces = const [],
  });
  final List<CargoGroupModel> groups;
  final Map<String, int> packedByEntry;
  final Map<String, int> requestedByEntry;
  final int weightGrams;
  final List<LoadingSpace> spaces;
  int get packedCount => packedByEntry.values.fold(0, (a, b) => a + b);
  int get unpackedCount =>
      requestedByEntry.values.fold(0, (a, b) => a + b) - packedCount;
}

/// Maximal empty spaces in section-local coordinates. Placements remain exact
/// integer boxes; an experience override preserves requested quantity, never
/// fabricates a collision-free location for physically unplaced cargo.
class SectionPackingEngine {
  const SectionPackingEngine();

  // Legacy clearance arguments are accepted for old callers but never applied.
  (int, int) recommendedGrid(Dimensions3 size, SectionCargoEntry entry) {
    var best = (0, 0);
    for (final o in entry.orientations) {
      if (o.dimensions.lengthMm > size.lengthMm) continue;
      final rows = size.widthMm ~/ o.dimensions.widthMm;
      final layers = entry.allowStack
          ? size.heightMm ~/ o.dimensions.heightMm
          : math.min(1, size.heightMm ~/ o.dimensions.heightMm);
      if (rows * layers > best.$1 * best.$2) best = (rows, layers);
    }
    return best;
  }

  int theoreticalCapacity(
    ContainerSection section,
    Dimensions3 container,
    SectionCargoEntry entry, {
    int clearanceMm = 0,
  }) {
    var best = 0;
    for (final o in entry.orientations) {
      final d = o.dimensions;
      final nz = container.heightMm ~/ d.heightMm;
      best = math.max(
        best,
        (section.lengthMm ~/ d.lengthMm) *
            (container.widthMm ~/ d.widthMm) *
            (entry.allowStack ? nz : math.min(nz, 1)),
      );
    }
    return best;
  }

  SectionPackingResult pack({
    required ContainerSection section,
    required Dimensions3 container,
    required List<SectionCargoEntry> entries,
    required int remainingPayloadGrams,
    int clearanceMm = 0,
  }) {
    final bases = entries.where((e) => e.isBase).toList();
    if (bases.isEmpty) {
      final result = _packRaw(
        section: section,
        container: container,
        entries: entries.where((e) => e.spaceId == null).toList(),
        remainingPayloadGrams: remainingPayloadGrams,
      );
      return SectionPackingResult(
        groups: result.groups,
        packedByEntry: {
          for (final e in entries) e.id: result.packedByEntry[e.id] ?? 0,
        },
        requestedByEntry: {for (final e in entries) e.id: e.quantity},
        weightGrams: result.weightGrams,
      );
    }
    final base = _packRaw(
      section: section,
      container: container,
      entries: bases,
      remainingPayloadGrams: remainingPayloadGrams,
    );
    final spaces = splitSpaces(section, container, base.groups);
    final groups = [...base.groups];
    final packed = {
      for (final e in entries) e.id: base.packedByEntry[e.id] ?? 0,
    };
    var weight = base.weightGrams;
    for (var spaceIndex = 0; spaceIndex < spaces.length; spaceIndex++) {
      final space = spaces[spaceIndex];
      final eligible = entries
          .where(
            (e) =>
                !e.isBase &&
                ((e.spaceId == null && space.parentId == null) ||
                    e.spaceId == space.id),
          )
          .toList();
      final local = ContainerSection(
        id: section.id,
        planId: section.planId,
        index: section.index,
        name: section.name,
        startXmm: 0,
        lengthMm: space.bounds.dimensions.lengthMm,
      );
      final result = _packRaw(
        section: local,
        container: space.bounds.dimensions,
        supportedLengthMm: space.supportedLengthMm,
        entries: [
          for (final e in eligible)
            if (!space.needsOverhang ||
                e.allowOverhang ||
                e.orientations.any(
                  (o) => o.dimensions.lengthMm <= space.supportedLengthMm!,
                ))
              e.copyWith(
                quantity: math.max(0, e.quantity - packed[e.id]!),
                horizontalPlacement:
                    e.horizontalPlacement == HorizontalPlacement.automatic &&
                        space.parentId == null &&
                        space.name.contains('右侧')
                    ? HorizontalPlacement.right
                    : e.horizontalPlacement,
              ),
        ],
        remainingPayloadGrams: math.max(0, remainingPayloadGrams - weight),
      );
      final groupStart = groups.length;
      for (final g in result.groups) {
        groups.add(
          CargoGroupModel(
            id: '${g.id}-${space.id}',
            planId: g.planId,
            cargoPackageId: g.cargoPackageId,
            sectionId: section.id,
            entryId: g.entryId,
            quantity: g.quantity,
            rows: g.rows,
            columns: g.columns,
            layers: g.layers,
            emptySlots: g.emptySlots,
            boundingDimensions: g.boundingDimensions,
            positionXmm: g.positionXmm + space.bounds.x,
            positionYmm: g.positionYmm + space.bounds.y,
            positionZmm: g.positionZmm + space.bounds.z,
            rotationX: g.rotationX,
            rotationY: g.rotationY,
            rotationZ: g.rotationZ,
            colorValue: g.colorValue,
            sortOrder: groups.length,
            allowStack: g.allowStack,
          ),
        );
      }
      for (final v in result.packedByEntry.entries) {
        packed[v.key] = packed[v.key]! + v.value;
      }
      weight += result.weightGrams;
      spaces.addAll(_remainingSpaces(space, groups.sublist(groupStart)));
    }
    final numberedSpaces = [...spaces]
      ..sort((a, b) {
        final depth = a.id
            .split('/free:')
            .length
            .compareTo(b.id.split('/free:').length);
        if (depth != 0) return depth;
        if (a.parentId == null) {
          return spaces.indexOf(a).compareTo(spaces.indexOf(b));
        }
        final top = (a.name.contains('上方') ? 0 : 1).compareTo(
          b.name.contains('上方') ? 0 : 1,
        );
        return top != 0 ? top : spaces.indexOf(a).compareTo(spaces.indexOf(b));
      });
    return SectionPackingResult(
      groups: groups,
      packedByEntry: packed,
      requestedByEntry: {for (final e in entries) e.id: e.quantity},
      weightGrams: weight,
      spaces: [
        for (final (i, s) in numberedSpaces.indexed)
          LoadingSpace(
            id: s.id,
            name:
                '${(i + 1).toString().padLeft(2, '0')} · ${s.name.split(' · ').last}',
            bounds: s.bounds,
            supportedLengthMm: s.supportedLengthMm,
            parentId: s.parentId,
          ),
      ],
    );
  }

  /// Non-overlapping width strips; a base occupies the full section length for
  /// side-space planning. Length overhang is explicit and capped at 1000mm.
  List<LoadingSpace> splitSpaces(
    ContainerSection section,
    Dimensions3 container,
    List<CargoGroupModel> bases,
  ) {
    if (bases.isEmpty) return [];
    final cuts = {
      0,
      container.widthMm,
      for (final g in bases) g.positionYmm,
      for (final g in bases) g.bounds.maxY,
    }.toList()..sort();
    final result = <LoadingSpace>[];
    for (var i = 0; i < cuts.length - 1; i++) {
      final y = cuts[i], end = cuts[i + 1];
      final covering = bases
          .where((g) => g.positionYmm < end && g.bounds.maxY > y)
          .toList();
      var z = 0;
      CargoGroupModel? top;
      for (final g in covering) {
        if (g.bounds.maxZ > z) {
          z = g.bounds.maxZ;
          top = g;
        }
      }
      if (z >= container.heightMm || (top != null && !top.allowStack)) continue;
      final label = top != null ? '上方' : (y == 0 ? '左侧' : '右侧');
      final canExtend =
          top != null &&
          section.lengthMm - top.boundingDimensions.lengthMm <= 1000;
      final x = top != null && !canExtend ? top.positionXmm : section.startXmm;
      final length = top != null && !canExtend
          ? top.boundingDimensions.lengthMm
          : section.lengthMm;
      result.add(
        LoadingSpace(
          id: '${section.id}:$label:${top?.entryId ?? 'side'}:$y-$end',
          name: '${'${result.length + 1}'.padLeft(2, '0')} · $label空间',
          bounds: Aabb3(
            x: x,
            y: y,
            z: z,
            dimensions: Dimensions3(length, end - y, container.heightMm - z),
          ),
          supportedLengthMm: top?.boundingDimensions.lengthMm,
        ),
      );
    }
    if (result.length == 2) {
      result.sort(
        (a, b) => (a.bounds.z > 0 ? 1 : 0).compareTo(b.bounds.z > 0 ? 1 : 0),
      );
    }
    return [
      for (final (i, s) in result.indexed)
        LoadingSpace(
          id: s.id,
          name:
              '${(i + 1).toString().padLeft(2, '0')} · ${s.name.split(' · ').last}',
          bounds: s.bounds,
          supportedLengthMm: s.supportedLengthMm,
        ),
    ];
  }

  List<LoadingSpace> spacesFor({
    required ContainerSection section,
    required Dimensions3 container,
    required List<SectionCargoEntry> entries,
    required int remainingPayloadGrams,
  }) {
    return pack(
      section: section,
      container: container,
      entries: entries,
      remainingPayloadGrams: remainingPayloadGrams,
    ).spaces;
  }

  /// Empty boxes from the current scene, without re-running the packing search.
  /// Include intersecting cargo from adjacent sections; staged cargo is ignored.
  List<LoadingSpace> spacesForPlacement({
    required ContainerSection section,
    required Dimensions3 container,
    required List<CargoGroupModel> groups,
  }) {
    final bounds = Aabb3(
      x: section.startXmm,
      y: 0,
      z: 0,
      dimensions: Dimensions3(
        section.lengthMm,
        container.widthMm,
        container.heightMm,
      ),
    );
    final occupied =
        groups
            .where((g) => g.sectionId != null && g.bounds.overlaps(bounds))
            .toList()
          ..sort((a, b) {
            for (final pair in [
              (a.positionZmm, b.positionZmm),
              (a.positionYmm, b.positionYmm),
              (a.positionXmm, b.positionXmm),
            ]) {
              final order = pair.$1.compareTo(pair.$2);
              if (order != 0) return order;
            }
            return a.id.compareTo(b.id);
          });
    if (occupied.isEmpty) return [];
    final free = _remainingSpaces(
      LoadingSpace(id: '${section.id}:placed', name: '', bounds: bounds),
      occupied,
    );
    return [
      for (final (i, s) in free.indexed)
        LoadingSpace(
          id: s.id,
          name: '${(i + 1).toString().padLeft(2, '0')} · ${s.name}',
          bounds: s.bounds,
        ),
    ];
  }

  /// Disjoint residual boxes, unlike the overlapping maximal boxes used by
  /// the packing search. IDs include geometry so moving an ancestor never
  /// silently relocates cargo assigned to one of its old residual spaces.
  List<LoadingSpace> _remainingSpaces(
    LoadingSpace parent,
    List<CargoGroupModel> cargo,
  ) {
    if (cargo.isEmpty) return [];
    var free = [parent.bounds];
    for (final g in cargo) {
      final next = <Aabb3>[];
      for (final f in free) {
        final u = g.bounds;
        if (!f.overlaps(u)) {
          next.add(f);
          continue;
        }
        final x = math.max(f.x, u.x), mx = math.min(f.maxX, u.maxX);
        final y = math.max(f.y, u.y), my = math.min(f.maxY, u.maxY);
        final z = math.max(f.z, u.z), mz = math.min(f.maxZ, u.maxZ);
        void add(int a, int b, int c, int d, int e, int h) {
          if (d > a && e > b && h > c) {
            next.add(
              Aabb3(
                x: a,
                y: b,
                z: c,
                dimensions: Dimensions3(d - a, e - b, h - c),
              ),
            );
          }
        }

        add(f.x, f.y, f.z, x, f.maxY, f.maxZ);
        add(mx, f.y, f.z, f.maxX, f.maxY, f.maxZ);
        add(x, f.y, f.z, mx, y, f.maxZ);
        add(x, my, f.z, mx, f.maxY, f.maxZ);
        add(x, y, f.z, mx, my, z);
        add(x, y, mz, mx, my, f.maxZ);
      }
      free = next;
    }
    final result = <LoadingSpace>[];
    for (final b in free) {
      final floor = b.z == parent.bounds.z;
      final supported = cargo.any(
        (g) =>
            g.allowStack &&
            g.bounds.maxZ == b.z &&
            g.bounds.x <= b.x &&
            g.bounds.maxX >= b.maxX &&
            g.bounds.y <= b.y &&
            g.bounds.maxY >= b.maxY,
      );
      if (!floor && !supported) continue;
      result.add(
        LoadingSpace(
          id: '${parent.id}/free:${b.x},${b.y},${b.z},${b.maxX},${b.maxY},${b.maxZ}',
          parentId: parent.id,
          name: floor ? '侧面剩余空间' : '货物上方空间',
          bounds: b,
          supportedLengthMm: floor ? parent.supportedLengthMm : null,
        ),
      );
    }
    result.sort((a, b) {
      final top = (a.bounds.z == parent.bounds.z ? 1 : 0).compareTo(
        b.bounds.z == parent.bounds.z ? 1 : 0,
      );
      return top != 0 ? top : a.bounds.y.compareTo(b.bounds.y);
    });
    return result;
  }

  SectionPackingResult _packRaw({
    required ContainerSection section,
    required Dimensions3 container,
    required List<SectionCargoEntry> entries,
    required int remainingPayloadGrams,
    int? supportedLengthMm,
  }) {
    if (section.lengthMm <= 0 ||
        section.startXmm < 0 ||
        section.endXmm > container.lengthMm) {
      throw ArgumentError('Invalid section bounds or clearance');
    }
    final size = Dimensions3(
      section.lengthMm,
      container.widthMm,
      container.heightMm,
    );
    var spaces = [Aabb3(x: 0, y: 0, z: 0, dimensions: size)];
    final groups = <CargoGroupModel>[];
    final packed = <String, int>{};
    final requested = <String, int>{};
    var weight = 0;
    final ordered = [...entries]
      ..sort((a, b) {
        final floor = (b.placeOnBottom ? 1 : 0).compareTo(
          a.placeOnBottom ? 1 : 0,
        );
        if (floor != 0) return floor;
        final pallet = (b.cargo.type == CargoPackageType.pallet ? 1 : 0)
            .compareTo(a.cargo.type == CargoPackageType.pallet ? 1 : 0);
        if (pallet != 0) return pallet;
        return b.cargo.dimensions.volumeMm3.compareTo(
          a.cargo.dimensions.volumeMm3,
        );
      });
    for (final entry in ordered) {
      if (entry.sectionId != section.id || entry.quantity < 0) {
        throw ArgumentError('Invalid section entry');
      }
      requested[entry.id] = entry.quantity;
      packed[entry.id] = 0;
      var remaining = entry.quantity;
      while (remaining > 0) {
        final byWeight = entry.cargo.weightGrams == 0
            ? remaining
            : math.max(0, remainingPayloadGrams - weight) ~/
                  entry.cargo.weightGrams;
        final wanted = math.min(remaining, byWeight);
        if (wanted == 0) break;
        _Candidate? best;
        spaces.sort((a, b) {
          final z = a.z.compareTo(b.z);
          if (z != 0) return z;
          final x = a.x.compareTo(b.x);
          return x != 0 ? x : a.y.compareTo(b.y);
        });
        final supportedSpaces = <Aabb3>[];
        for (final free in spaces) {
          if (free.z == 0) {
            supportedSpaces.add(free);
            continue;
          }
          for (final g in groups) {
            if (!g.allowStack ||
                g.bounds.maxZ != free.z ||
                (entry.placeOnBottom && g.entryId != entry.id)) {
              continue;
            }
            final x = math.max(free.x, g.positionXmm - section.startXmm);
            final y = math.max(free.y, g.positionYmm);
            final mx = math.min(free.maxX, g.bounds.maxX - section.startXmm);
            final my = math.min(free.maxY, g.bounds.maxY);
            if (mx > x && my > y) {
              supportedSpaces.add(
                Aabb3(
                  x: x,
                  y: y,
                  z: free.z,
                  dimensions: Dimensions3(
                    mx - x,
                    my - y,
                    free.dimensions.heightMm,
                  ),
                ),
              );
            }
          }
        }
        for (final free in supportedSpaces) {
          for (final orientation in entry.orientations) {
            final d = orientation.dimensions;
            if (!entry.allowOverhang &&
                supportedLengthMm != null &&
                d.lengthMm > supportedLengthMm) {
              continue;
            }
            final effective = d;
            final nx = free.dimensions.lengthMm ~/ d.lengthMm;
            final ny = math.min(
              free.dimensions.widthMm ~/ d.widthMm,
              entry.perRow ?? 0x7fffffff,
            );
            final heightCount = math.min(
              free.dimensions.heightMm ~/ d.heightMm,
              entry.rowCount ?? 0x7fffffff,
            );
            final nz = entry.allowStack
                ? heightCount
                : math.min(1, heightCount);
            if (nx == 0 || ny == 0 || nz == 0) continue;
            final count = math.min(wanted, nx * ny * nz);
            final rows = entry.isBase && entry.allowStack
                ? math.min(ny, (count + nz - 1) ~/ nz)
                : math.min(count, ny);
            final usedWidth = (rows - 1) * effective.widthMm + d.widthMm;
            final y = switch (entry.horizontalPlacement) {
              HorizontalPlacement.left => 0,
              HorizontalPlacement.center =>
                (container.widthMm - usedWidth) ~/ 2,
              HorizontalPlacement.right => container.widthMm - usedWidth,
              HorizontalPlacement.automatic => free.y,
            };
            if (y < free.y || y + usedWidth > free.maxY) continue;
            if (free.z > 0) {
              final support = groups.any(
                (g) =>
                    g.allowStack &&
                    (!entry.placeOnBottom || g.entryId == entry.id) &&
                    g.bounds.maxZ == free.z &&
                    free.x + section.startXmm >= g.positionXmm &&
                    free.x + section.startXmm + d.lengthMm <= g.bounds.maxX &&
                    y >= g.positionYmm &&
                    y + usedWidth <= g.bounds.maxY,
              );
              if (!support) continue;
            }
            final candidate = _Candidate(
              free.x,
              y,
              free.z,
              rows,
              nz,
              count,
              orientation,
              effective,
            );
            // First fit lowest support plane, then maximize a regular block.
            if (best == null ||
                candidate.z < best.z ||
                (candidate.z == best.z && candidate.count > best.count)) {
              best = candidate;
            }
          }
        }
        if (best == null) break;
        // Emit exact rectangular blocks: full layers plus the partial final row.
        // Thus 100 packages never become an opaque 286-package cuboid.
        var toPlace = best.count;
        var x = best.x;
        while (toPlace > 0) {
          final inColumn = math.min(toPlace, best.rows * best.layers);
          final fullLayers = inColumn ~/ best.rows;
          final tail = inColumn % best.rows;
          final blocks = <(int, int, int)>[
            if (fullLayers > 0) (best.rows, fullLayers, 0),
            if (tail > 0) (tail, 1, fullLayers * best.effective.heightMm),
          ];
          for (final block in blocks) {
            final d = best.orientation.dimensions;
            final bounds = Dimensions3(
              d.lengthMm,
              (block.$1 - 1) * best.effective.widthMm + d.widthMm,
              (block.$2 - 1) * best.effective.heightMm + d.heightMm,
            );
            final group = CargoGroupModel(
              id: '${entry.id}-group-${groups.length}',
              planId: section.planId,
              cargoPackageId: entry.cargo.id,
              sectionId: section.id,
              entryId: entry.id,
              quantity: block.$1 * block.$2,
              rows: block.$1,
              columns: 1,
              layers: block.$2,
              emptySlots: 0,
              boundingDimensions: bounds,
              positionXmm: section.startXmm + x,
              positionYmm: best.y,
              positionZmm: best.z + block.$3,
              rotationX: best.orientation.rotationX,
              rotationY: best.orientation.rotationY,
              rotationZ: best.orientation.rotationZ,
              colorValue: entry.colorValue,
              sortOrder: groups.length,
              allowStack: entry.allowStack,
            );
            groups.add(group);
            final blockHeight = entry.allowStack
                ? math.min(size.heightMm - group.positionZmm, bounds.heightMm)
                : size.heightMm - group.positionZmm;
            final occupied = Aabb3(
              x: x,
              y: best.y,
              z: group.positionZmm,
              dimensions: Dimensions3(
                math.min(size.lengthMm - x, bounds.lengthMm),
                math.min(size.widthMm - best.y, bounds.widthMm),
                blockHeight,
              ),
            );
            spaces = _subtract(spaces, occupied);
          }
          x += best.effective.lengthMm;
          toPlace -= inColumn;
        }
        remaining -= best.count;
        packed[entry.id] = packed[entry.id]! + best.count;
        weight += best.count * entry.cargo.weightGrams;
      }
    }
    return SectionPackingResult(
      groups: groups,
      packedByEntry: packed,
      requestedByEntry: requested,
      weightGrams: weight,
    );
  }

  static List<Aabb3> _subtract(List<Aabb3> spaces, Aabb3 used) {
    final result = <Aabb3>[];
    void add(int x, int y, int z, int mx, int my, int mz) {
      if (mx > x && my > y && mz > z) {
        result.add(
          Aabb3(
            x: x,
            y: y,
            z: z,
            dimensions: Dimensions3(mx - x, my - y, mz - z),
          ),
        );
      }
    }

    for (final f in spaces) {
      if (!f.overlaps(used)) {
        result.add(f);
        continue;
      }
      add(f.x, f.y, f.z, math.min(f.maxX, used.x), f.maxY, f.maxZ);
      add(math.max(f.x, used.maxX), f.y, f.z, f.maxX, f.maxY, f.maxZ);
      add(f.x, f.y, f.z, f.maxX, math.min(f.maxY, used.y), f.maxZ);
      add(f.x, math.max(f.y, used.maxY), f.z, f.maxX, f.maxY, f.maxZ);
      add(f.x, f.y, f.z, f.maxX, f.maxY, math.min(f.maxZ, used.z));
      add(f.x, f.y, math.max(f.z, used.maxZ), f.maxX, f.maxY, f.maxZ);
    }
    final unique = <String, Aabb3>{
      for (final f in result)
        '${f.x},${f.y},${f.z},${f.maxX},${f.maxY},${f.maxZ}': f,
    }.values.toList();
    return [
      for (var i = 0; i < unique.length; i++)
        if (!unique.indexed.any((v) => v.$1 != i && _contains(v.$2, unique[i])))
          unique[i],
    ];
  }

  static bool _contains(Aabb3 a, Aabb3 b) =>
      a.x <= b.x &&
      a.y <= b.y &&
      a.z <= b.z &&
      a.maxX >= b.maxX &&
      a.maxY >= b.maxY &&
      a.maxZ >= b.maxZ;
}

class _Candidate {
  const _Candidate(
    this.x,
    this.y,
    this.z,
    this.rows,
    this.layers,
    this.count,
    this.orientation,
    this.effective,
  );
  final int x, y, z, rows, layers, count;
  final CargoOrientation orientation;
  final Dimensions3 effective;
}
