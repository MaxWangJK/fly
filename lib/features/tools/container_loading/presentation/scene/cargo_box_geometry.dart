import 'dart:math' as math;

/// Six quadrilateral faces over the standard eight box corners. Canvas batches
/// planar faces; these same indices represent twelve triangles for a mesh adapter.
const cargoBoxFaces = <List<int>>[
  [0, 3, 7, 4],
  [1, 2, 6, 5],
  [0, 1, 5, 4],
  [3, 2, 6, 7],
  [0, 1, 2, 3],
  [4, 5, 6, 7],
];
List<List<int>> visibleCargoBoxFaces(double yaw, double pitch) => [
  cargoBoxFaces[math.cos(pitch) * math.sin(yaw) >= 0 ? 1 : 0],
  cargoBoxFaces[math.cos(pitch) * math.cos(yaw) >= 0 ? 3 : 2],
  cargoBoxFaces[math.sin(pitch) >= 0 ? 5 : 4],
];
