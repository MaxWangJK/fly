import 'package:flutter_test/flutter_test.dart';
import 'package:fly/features/tools/container_loading/domain/models/container_loading_models.dart';
import 'package:fly/features/tools/container_loading/domain/models/section_models.dart';

import 'container_loading_v2_test.dart' as f;

const pallet = CargoPackageModel(
  id: 'v6-pallet',
  name: '托盘',
  type: CargoPackageType.pallet,
  dimensions: Dimensions3(2800, 1200, 800),
  weightGrams: 800000,
  colorValue: 0xFFB18CAF,
);
const pvc = CargoPackageModel(
  id: 'v6-pvc',
  name: 'PVC ceiling',
  dimensions: Dimensions3(2900, 250, 100),
  weightGrams: 1000,
  colorValue: 0xFF79A88C,
);

void main() {
  test(
    'V6 screenshot reproduction: recommended grids leave only small gaps',
    () {
      final base = f.entry(
        pallet,
        1,
        bottom: true,
        position: HorizontalPlacement.left,
      );
      final roots = f.pack([base]).spaces;
      expect(
        f.engine.recommendedGrid(roots[0].bounds.dimensions, f.entry(pvc, 1)),
        (4, 26),
      );
      expect(
        f.engine.recommendedGrid(roots[1].bounds.dimensions, f.entry(f.wpc, 1)),
        (7, 15),
      );
      final entries = [
        base,
        f
            .entry(pvc, 104)
            .copyWith(spaceId: roots[0].id, perRow: 4, rowCount: 26),
        f
            .entry(f.wpc, 105)
            .copyWith(spaceId: roots[1].id, perRow: 7, rowCount: 15),
      ];
      final result = f.pack(entries);
      expect(result.packedCount, 210);
      expect(result.unpackedCount, 0);
      f.valid(result, f.section);
      final residual = result.spaces.where((s) => s.parentId != null).toList();
      expect(
        residual.map((s) => s.bounds.dimensions),
        containsAll([
          const Dimensions3(2900, 1000, 90),
          const Dimensions3(2900, 1120, 90),
          const Dimensions3(2900, 80, 1890),
        ]),
      );
      final shown = LoadingSpace.suggested(
        result.spaces,
        entries.map((e) => e.spaceId).whereType<String>(),
      );
      expect(shown.map((s) => s.id), roots.map((s) => s.id));
      expect(shown.length, 2);
    },
  );
  test('V6 500mm is inclusive; either smaller dimension hides empty space', () {
    LoadingSpace space(String id, int w, int h, {String? parent}) =>
        LoadingSpace(
          id: id,
          name: '$id · 空间',
          parentId: parent,
          bounds: Aabb3(x: 0, y: 0, z: 0, dimensions: Dimensions3(2900, w, h)),
        );
    final spaces = [
      space('a', 500, 500),
      space('b', 499, 1000),
      space('c', 1000, 499),
      space('d', 900, 900),
    ];
    final visible = LoadingSpace.suggested(spaces, []);
    expect(visible.map((s) => s.id), ['a', 'd']);
    expect(visible.last.name, 'B区');
    expect(LoadingSpace.areaName(25), 'Z区');
    expect(LoadingSpace.areaName(26), 'AA区');
    final legacy = LoadingSpace.suggested(
      [...spaces, space('e', 400, 400, parent: 'b')],
      ['e'],
    );
    expect(legacy.map((s) => s.id), containsAll(['b', 'e']));
    expect(legacy.firstWhere((s) => s.id == 'e').isUsefulForLoading, false);
  });
}
