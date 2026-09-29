# Performance

The scene never creates one Flutter widget per package. A regular section is rendered as one cuboid, then its visible face receives batched row/layer grid lines. The 1144 WPC case is four groups and roughly 140 grid lines rather than 1144 widgets or meshes.

Collision uses group-level AABB checks only. Dragging does not compare every internal package, avoiding O(n²) package collision work. Picking also targets groups.

The pure Dart performance test builds 1144 `PackedItem` records and four renderer groups within a two-second safety threshold; typical execution is far below that. Painting complexity depends on group count and capped grid subdivisions, not total package count.

Shadows, GLB loading and per-package edge geometry are disabled in V1. The scene uses ambient-looking flat colors and simple face shading.
