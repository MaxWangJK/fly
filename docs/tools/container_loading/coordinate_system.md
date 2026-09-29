# Coordinate system

Fly domain coordinates are right-handed and measured in integer millimetres:

- X: container length, from doors/front toward the rear.
- Y: container width, left to right.
- Z: container height, floor upward.
- Origin: front-left-bottom of the usable internal box.

Positions always describe the minimum corner of a cargo group's axis-aligned bounding box. Rotations are orthogonal degrees (`0/90/180/270`). After a 90-degree rotation the dimensions are permuted and AABB validation is repeated.

The native scene projects domain X/Y/Z to screen coordinates inside `_SceneProjection`. No renderer coordinate leaks into the database or packing engine. A future Y-up renderer must implement a scene adapter at this boundary.
