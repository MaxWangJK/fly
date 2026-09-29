import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../domain/models/container_loading_models.dart';
import '../../domain/models/section_models.dart';
import '../../domain/packing/placement_engine.dart';

enum ContainerCameraView { perspective, top, side, front }

abstract class ContainerSceneController extends ChangeNotifier {
  Dimensions3 get container;
  List<CargoGroupModel> get groups;
  String? get selectedGroupId;
  String? get invalidGroupId;
  double get yaw;
  double get pitch;
  double get zoom;
  double get panX;
  double get panY;
  double get containerOpacity;
  bool get showGrid;
  bool get showDimensions;
  bool get canUndo;
  bool get canRedo;
  List<ContainerSection> get sections;
  String? get focusedSectionId;
  void setSections(List<ContainerSection> sections);
  void focusSection(String? id);

  void setScene(Dimensions3 container, List<CargoGroupModel> groups);
  void select(String? id);
  void orbit(double deltaX, double deltaY);
  void pan(double deltaX, double deltaY);
  void changeZoom(double factor);
  void setCameraView(ContainerCameraView view);
  void resetView();
  void setContainerOpacity(double value);
  void setShowGrid(bool value);
  void setShowDimensions(bool value);
  void beginMove(String id);
  void previewMove(int xMm, int yMm, int zMm);
  void endMove({bool allowOverflow = false, bool cancel = false});
  bool get pendingOverflow;
  bool get isMoving;
  void rotateSelectedX();
  void rotateSelectedY();
  void rotateSelectedZ();
  void deleteSelected();
  void duplicateSelected();
  void resetSelected();
  void undo();
  void redo();
}

class NativeContainerSceneController extends ContainerSceneController {
  NativeContainerSceneController({
    Dimensions3? initialContainer,
    List<CargoGroupModel> initialGroups = const [],
    this.gridSnapMm = 50,
  }) : _container = initialContainer ?? const Dimensions3(11900, 2200, 2690),
       _groups = [...initialGroups];

  final int gridSnapMm;
  Dimensions3 _container;
  List<CargoGroupModel> _groups;
  Map<String, CargoGroupModel> _baseline = const {};
  String? _selectedGroupId;
  String? _invalidGroupId;
  double _yaw = -.62;
  double _pitch = .48;
  double _zoom = 1;
  double _panX = 0;
  double _panY = 0;
  double _containerOpacity = .34;
  bool _showGrid = true;
  bool _showDimensions = true;
  List<CargoGroupModel>? _moveOrigin;
  @override
  bool get isMoving => _moveOrigin != null;
  final List<List<CargoGroupModel>> _undo = [];
  final List<List<CargoGroupModel>> _redo = [];
  List<ContainerSection> _sections = [];
  String? _focusedSectionId;
  @override
  List<ContainerSection> get sections => _sections;
  @override
  String? get focusedSectionId => _focusedSectionId;
  @override
  void setSections(List<ContainerSection> sections) {
    _sections = List.unmodifiable(sections);
    notifyListeners();
  }

  @override
  void focusSection(String? id) {
    _focusedSectionId = id;
    notifyListeners();
  }

  bool _valid(CargoGroupModel group, Aabb3 bounds, {bool manual = false}) {
    if (bounds.z < 0) return false;
    if (!manual && !bounds.inside(_container)) return false;
    final section = _sections.where((s) => s.id == group.sectionId).firstOrNull;
    if (!manual &&
        section != null &&
        (bounds.x < section.startXmm || bounds.maxX > section.endXmm)) {
      return false;
    }
    if (CargoPlacement.collides(
      bounds,
      _groups.where((g) => g.id != group.id).map((g) => g.bounds),
    )) {
      return false;
    }
    // Non-stackable cargo reserves its vertical column; touching its top is
    // not sufficient permission to place another group above it.
    for (final other in _groups.where((g) => g.id != group.id)) {
      final horizontal =
          bounds.x < other.bounds.maxX &&
          bounds.maxX > other.positionXmm &&
          bounds.y < other.bounds.maxY &&
          bounds.maxY > other.positionYmm;
      if (horizontal &&
          ((!other.allowStack && bounds.z >= other.bounds.maxZ) ||
              (!group.allowStack && other.positionZmm >= bounds.maxZ))) {
        return false;
      }
    }
    return true;
  }

  @override
  Dimensions3 get container => _container;
  @override
  List<CargoGroupModel> get groups => List.unmodifiable(_groups);
  @override
  String? get selectedGroupId => _selectedGroupId;
  @override
  String? get invalidGroupId => _invalidGroupId;
  @override
  double get yaw => _yaw;
  @override
  double get pitch => _pitch;
  @override
  double get zoom => _zoom;
  @override
  double get panX => _panX;
  @override
  double get panY => _panY;
  @override
  double get containerOpacity => _containerOpacity;
  @override
  bool get showGrid => _showGrid;
  @override
  bool get showDimensions => _showDimensions;
  @override
  bool get canUndo => _undo.isNotEmpty;
  @override
  bool get canRedo => _redo.isNotEmpty;

  @override
  void setScene(Dimensions3 container, List<CargoGroupModel> groups) {
    _moveOrigin = null;
    _container = container;
    _groups = [...groups];
    _baseline = {for (final group in groups) group.id: group};
    _selectedGroupId = null;
    _invalidGroupId = null;
    _undo.clear();
    _redo.clear();
    notifyListeners();
  }

  @override
  void select(String? id) {
    _selectedGroupId = id;
    _invalidGroupId = null;
    notifyListeners();
  }

  @override
  void orbit(double deltaX, double deltaY) {
    _yaw += deltaX * .008 * yawDirection;
    _pitch = (_pitch - deltaY * .006 * pitchDirection).clamp(-1.15, 1.15);
    notifyListeners();
  }

  static const double yawDirection = -1;
  static const double pitchDirection = -1;

  @override
  void pan(double deltaX, double deltaY) {
    _panX += deltaX;
    _panY += deltaY;
    notifyListeners();
  }

  @override
  void changeZoom(double factor) {
    _zoom = (_zoom * factor).clamp(.45, 4.5);
    notifyListeners();
  }

  @override
  void setCameraView(ContainerCameraView view) {
    switch (view) {
      case ContainerCameraView.perspective:
        _yaw = -.62;
        _pitch = .48;
      case ContainerCameraView.top:
        _yaw = 0;
        _pitch = 1.15;
      case ContainerCameraView.side:
        _yaw = math.pi / 2;
        _pitch = 0;
      case ContainerCameraView.front:
        _yaw = 0;
        _pitch = 0;
    }
    notifyListeners();
  }

  @override
  void resetView() {
    _yaw = -.62;
    _pitch = .48;
    _zoom = 1;
    _panX = 0;
    _panY = 0;
    notifyListeners();
  }

  @override
  void setContainerOpacity(double value) {
    _containerOpacity = value.clamp(.08, .8);
    notifyListeners();
  }

  @override
  void setShowGrid(bool value) {
    _showGrid = value;
    notifyListeners();
  }

  @override
  void setShowDimensions(bool value) {
    _showDimensions = value;
    notifyListeners();
  }

  @override
  void beginMove(String id) {
    select(id);
    _moveOrigin = [..._groups];
  }

  @override
  void previewMove(int xMm, int yMm, int zMm) {
    final index = _groups.indexWhere((group) => group.id == _selectedGroupId);
    if (index < 0) return;
    final value = _groups[index];
    var candidate = Aabb3(
      x: CargoPlacement.snap(xMm, gridMm: gridSnapMm),
      y: CargoPlacement.snap(yMm, gridMm: gridSnapMm),
      z: CargoPlacement.snap(zMm, gridMm: gridSnapMm),
      dimensions: value.boundingDimensions,
    );
    candidate = CargoPlacement.snapToSurfaces(
      candidate,
      _container,
      _groups
          .where((group) => group.id != value.id)
          .map((group) => group.bounds),
    );
    final collision = CargoPlacement.collides(
      candidate,
      _groups
          .where((group) => group.id != value.id)
          .map((group) => group.bounds),
    );
    _invalidGroupId = !collision && _valid(value, candidate, manual: true)
        ? null
        : value.id;
    _groups[index] = value.copyWith(
      positionXmm: candidate.x,
      positionYmm: candidate.y,
      positionZmm: candidate.z,
    );
    notifyListeners();
  }

  @override
  bool get pendingOverflow {
    final group = _groups.where((g) => g.id == _selectedGroupId).firstOrNull;
    if (group != null && _stagingSnap(group) != null) return false;
    return _moveOrigin != null &&
        group != null &&
        _overContainer(group.bounds) &&
        !group.bounds.inside(_container);
  }

  bool _overContainer(Aabb3 b) =>
      b.maxX > 0 &&
      b.x < _container.lengthMm &&
      b.maxY > 0 &&
      b.y < _container.widthMm;

  CargoGroupModel? _stagingSnap(CargoGroupModel group) {
    final original = _moveOrigin?.where((g) => g.id == group.id).firstOrNull;
    if (original == null ||
        original.sectionId != null ||
        !_overContainer(group.bounds) ||
        _sections.isEmpty) {
      return null;
    }
    final center = group.bounds.x + group.boundingDimensions.lengthMm / 2;
    final sections = [..._sections]
      ..sort((a, b) {
        double distance(ContainerSection s) => center < s.startXmm
            ? s.startXmm - center
            : center > s.endXmm
            ? center - s.endXmm
            : 0;
        return distance(a).compareTo(distance(b));
      });
    final target = sections.first;
    final d = group.boundingDimensions;
    if (d.lengthMm > target.lengthMm ||
        d.widthMm > _container.widthMm ||
        d.heightMm > _container.heightMm) {
      return null;
    }
    final right = _container.widthMm - d.widthMm;
    final desiredY = group.positionYmm.clamp(0, right);
    final others = _groups.where((g) => g.id != group.id).toList();
    final xs = <int>{
      group.positionXmm.clamp(target.startXmm, target.endXmm - d.lengthMm),
      target.startXmm,
      target.endXmm - d.lengthMm,
    };
    final ys = <int>{
      0,
      right,
      right ~/ 2,
      for (final g in others) ...[g.bounds.maxY, g.bounds.y - d.widthMm],
    };
    final zs = <int>{
      0,
      for (final g in others.where((g) => g.allowStack)) g.bounds.maxZ,
    };
    final candidates = <CargoGroupModel>[];
    for (final x in xs) {
      for (final y in ys) {
        for (final z in zs) {
          final candidate = group.copyWith(
            positionXmm: x,
            positionYmm: y,
            positionZmm: z,
            sectionId: target.id,
          );
          if (_valid(candidate, candidate.bounds)) candidates.add(candidate);
        }
      }
    }
    candidates.sort((a, b) {
      final floor = a.positionZmm.compareTo(b.positionZmm);
      if (floor != 0) return floor;
      int score(CargoGroupModel g) =>
          (g.positionYmm - desiredY).abs() +
          (g.positionXmm - group.positionXmm).abs();
      return score(a).compareTo(score(b));
    });
    return candidates.firstOrNull;
  }

  @override
  void endMove({bool allowOverflow = false, bool cancel = false}) {
    final origin = _moveOrigin;
    if (origin == null) return;
    if (!cancel) {
      final i = _groups.indexWhere((g) => g.id == _selectedGroupId);
      if (i >= 0) {
        final snapped = _stagingSnap(_groups[i]);
        if (snapped != null) {
          _groups[i] = snapped;
          _invalidGroupId = null;
        }
      }
    }
    if (cancel ||
        _invalidGroupId != null ||
        (pendingOverflow && !allowOverflow)) {
      _groups = origin;
    } else if (!_samePositions(origin, _groups)) {
      final index = _groups.indexWhere((g) => g.id == _selectedGroupId);
      if (index >= 0) {
        final group = _groups[index];
        // Use the center of the intersecting part, including oversize cargo.
        final center =
            (math.max(0, group.bounds.x) +
                math.min(_container.lengthMm, group.bounds.maxX)) /
            2;
        final target = _overContainer(group.bounds)
            ? _sections
                  .where((s) => center >= s.startXmm && center < s.endXmm)
                  .firstOrNull
            : null;
        _groups[index] = group.copyWith(
          sectionId: target?.id,
          needsReview: true,
          clearSection: target == null,
        );
        if (target != null) _focusedSectionId = target.id;
      }
      _undo.add(origin);
      _redo.clear();
    }
    _moveOrigin = null;
    _invalidGroupId = null;
    notifyListeners();
  }

  @override
  void rotateSelectedX() => _rotate('x');
  @override
  void rotateSelectedY() => _rotate('y');
  @override
  void rotateSelectedZ() => _rotate('z');

  void _rotate(String axis) {
    final index = _groups.indexWhere((group) => group.id == _selectedGroupId);
    if (index < 0) return;
    final before = [..._groups];
    final value = _groups[index];
    final d = value.boundingDimensions;
    final dimensions = switch (axis) {
      'x' => Dimensions3(d.lengthMm, d.heightMm, d.widthMm),
      'y' => Dimensions3(d.heightMm, d.widthMm, d.lengthMm),
      _ => Dimensions3(d.widthMm, d.lengthMm, d.heightMm),
    };
    final rawBounds = Aabb3(
      x: value.positionXmm,
      y: value.positionYmm,
      z: value.positionZmm,
      dimensions: dimensions,
    );
    final bounds = value.sectionId == null
        ? rawBounds
        : CargoPlacement.constrain(rawBounds, _container);
    final collision = CargoPlacement.collides(
      bounds,
      _groups
          .where((group) => group.id != value.id)
          .map((group) => group.bounds),
    );
    if (collision ||
        !_valid(value, bounds, manual: value.sectionId == null) ||
        (value.sectionId == null && _overContainer(bounds))) {
      _invalidGroupId = value.id;
      notifyListeners();
      return;
    }
    _groups[index] = value.copyWith(
      boundingDimensions: dimensions,
      positionXmm: bounds.x,
      positionYmm: bounds.y,
      positionZmm: bounds.z,
      rotationX: axis == 'x' ? (value.rotationX + 90) % 360 : value.rotationX,
      rotationY: axis == 'y' ? (value.rotationY + 90) % 360 : value.rotationY,
      rotationZ: axis == 'z' ? (value.rotationZ + 90) % 360 : value.rotationZ,
      rows: axis == 'x'
          ? value.layers
          : axis == 'z'
          ? value.columns
          : value.rows,
      columns: axis == 'y'
          ? value.layers
          : axis == 'z'
          ? value.rows
          : value.columns,
      layers: axis == 'x'
          ? value.rows
          : axis == 'y'
          ? value.columns
          : value.layers,
    );
    _invalidGroupId = null;
    _record(before);
  }

  @override
  void deleteSelected() {
    if (_selectedGroupId == null) return;
    final before = [..._groups];
    _groups.removeWhere((group) => group.id == _selectedGroupId);
    _selectedGroupId = null;
    _record(before);
  }

  @override
  void duplicateSelected() {
    final index = _groups.indexWhere((group) => group.id == _selectedGroupId);
    if (index < 0) return;
    final before = [..._groups];
    final source = _groups[index];
    final offset = source.boundingDimensions.lengthMm;
    var x = source.positionXmm + offset;
    if (source.sectionId != null &&
        x + source.boundingDimensions.lengthMm > _container.lengthMm) {
      x = 0;
    }
    final copy = CargoGroupModel(
      id: '${source.id}-copy-${DateTime.now().microsecondsSinceEpoch}',
      planId: source.planId,
      cargoPackageId: source.cargoPackageId,
      quantity: source.quantity,
      rows: source.rows,
      columns: source.columns,
      layers: source.layers,
      emptySlots: source.emptySlots,
      boundingDimensions: source.boundingDimensions,
      positionXmm: x,
      positionYmm: source.positionYmm,
      positionZmm: source.positionZmm,
      rotationX: source.rotationX,
      rotationY: source.rotationY,
      rotationZ: source.rotationZ,
      colorValue: source.colorValue,
      sortOrder: _groups.length * 1024,
      sectionId: source.sectionId,
      entryId: source.entryId,
      allowStack: source.allowStack,
      needsReview: true,
    );
    if (_valid(copy, copy.bounds, manual: source.sectionId == null) &&
        (source.sectionId != null || !_overContainer(copy.bounds))) {
      _groups.add(copy);
      _selectedGroupId = copy.id;
      _record(before);
    }
  }

  @override
  void resetSelected() {
    final id = _selectedGroupId;
    if (id == null) return;
    final original = _baseline[id];
    final index = _groups.indexWhere((group) => group.id == id);
    if (original == null || index < 0) return;
    final collision = CargoPlacement.collides(
      original.bounds,
      _groups.where((group) => group.id != id).map((group) => group.bounds),
    );
    if (collision ||
        !_valid(
          original,
          original.bounds,
          manual: original.sectionId == null,
        )) {
      return;
    }
    final before = [..._groups];
    _groups[index] = original;
    _record(before);
  }

  @override
  void undo() {
    if (_undo.isEmpty) return;
    _redo.add([..._groups]);
    _groups = _undo.removeLast();
    _selectedGroupId = null;
    _invalidGroupId = null;
    notifyListeners();
  }

  @override
  void redo() {
    if (_redo.isEmpty) return;
    _undo.add([..._groups]);
    _groups = _redo.removeLast();
    _selectedGroupId = null;
    _invalidGroupId = null;
    notifyListeners();
  }

  /// Resize only this block; never repack neighbouring manually placed cargo.
  bool resizeGroup(String id, {required int rows, required int layers}) {
    final index = _groups.indexWhere((g) => g.id == id);
    if (index < 0 ||
        isMoving ||
        rows < 1 ||
        layers < 1 ||
        rows > 10000 ||
        layers > 10000) {
      return false;
    }
    final old = _groups[index];
    if (old.rows < 1 || old.layers < 1) return false;
    final dimensions = Dimensions3(
      old.boundingDimensions.lengthMm,
      (old.boundingDimensions.widthMm * rows / old.rows).round(),
      (old.boundingDimensions.heightMm * layers / old.layers).round(),
    );
    var updated = old.copyWith(
      rows: rows,
      layers: layers,
      quantity: rows * old.columns * layers,
      emptySlots: 0,
      boundingDimensions: dimensions,
      // Keep the edge nearest the container fixed when staged on its left.
      positionYmm: old.sectionId == null && old.bounds.maxY <= 0
          ? old.bounds.maxY - dimensions.widthMm
          : old.positionYmm,
    );
    if (old.sectionId != null) {
      final section = _sections.where((s) => s.id == old.sectionId).firstOrNull;
      final start = section?.startXmm ?? 0;
      final end = section?.endXmm ?? _container.lengthMm;
      // Resize from the current position, fitting the edited block back into
      // its section when possible. Never move any neighbouring cargo.
      updated = updated.copyWith(
        positionXmm: old.positionXmm.clamp(
          start,
          math.max(start, end - dimensions.lengthMm),
        ),
        positionYmm: old.positionYmm.clamp(
          0,
          math.max(0, _container.widthMm - dimensions.widthMm),
        ),
        positionZmm: old.positionZmm.clamp(
          0,
          math.max(0, _container.heightMm - dimensions.heightMm),
        ),
      );
    }
    updated = updated.copyWith(
      needsReview: !_valid(
        updated,
        updated.bounds,
        manual: updated.sectionId == null,
      ),
    );
    if (old.rows == rows && old.layers == layers && old.emptySlots == 0) {
      return true;
    }
    final before = [..._groups];
    _groups[index] = updated;
    _selectedGroupId = id;
    _record(before);
    return true;
  }

  bool hasPlacementConflict(CargoGroupModel group) =>
      !_valid(group, group.bounds, manual: group.sectionId == null);

  void _record(List<CargoGroupModel> before) {
    _undo.add(before);
    _redo.clear();
    notifyListeners();
  }

  static bool _samePositions(List<CargoGroupModel> a, List<CargoGroupModel> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].positionXmm != b[i].positionXmm ||
          a[i].positionYmm != b[i].positionYmm ||
          a[i].positionZmm != b[i].positionZmm) {
        return false;
      }
    }
    return true;
  }
}
