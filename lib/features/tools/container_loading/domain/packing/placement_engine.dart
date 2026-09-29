import 'dart:math' as math;

import '../models/container_loading_models.dart';

abstract final class CargoPlacement {
  static bool isInside(Aabb3 candidate, Dimensions3 container) =>
      candidate.inside(container);

  static bool collides(Aabb3 candidate, Iterable<Aabb3> others) =>
      others.any(candidate.overlaps);

  static int snap(int value, {int gridMm = 50}) =>
      gridMm <= 1 ? value : (value / gridMm).round() * gridMm;

  static Aabb3 constrain(Aabb3 value, Dimensions3 container) => Aabb3(
    x: value.x
        .clamp(0, math.max(0, container.lengthMm - value.dimensions.lengthMm))
        .toInt(),
    y: value.y
        .clamp(0, math.max(0, container.widthMm - value.dimensions.widthMm))
        .toInt(),
    z: value.z
        .clamp(0, math.max(0, container.heightMm - value.dimensions.heightMm))
        .toInt(),
    dimensions: value.dimensions,
  );

  static Aabb3 snapToSurfaces(
    Aabb3 value,
    Dimensions3 container,
    Iterable<Aabb3> others, {
    int toleranceMm = 30,
  }) {
    var x = value.x;
    var y = value.y;
    var z = value.z;
    int near(int current, int target) =>
        (current - target).abs() <= toleranceMm ? target : current;
    x = near(near(x, 0), container.lengthMm - value.dimensions.lengthMm);
    y = near(near(y, 0), container.widthMm - value.dimensions.widthMm);
    z = near(near(z, 0), container.heightMm - value.dimensions.heightMm);
    for (final other in others) {
      x = near(near(x, other.maxX), other.x - value.dimensions.lengthMm);
      y = near(near(y, other.maxY), other.y - value.dimensions.widthMm);
      z = near(near(z, other.maxZ), other.z - value.dimensions.heightMm);
    }
    return Aabb3(x: x, y: y, z: z, dimensions: value.dimensions);
  }
}
