import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/container_loading_models.dart';
import '../../domain/models/section_models.dart';
import 'container_scene_controller.dart';
import 'cargo_box_geometry.dart';
import '../../../../../l10n/fly_localizations.dart';

class ContainerSceneView extends StatefulWidget {
  const ContainerSceneView({
    required this.controller,
    this.cargoNames = const {},
    this.cargoTypes = const {},
    super.key,
  });

  final ContainerSceneController controller;
  final Map<String, String> cargoNames;
  final Map<String, CargoPackageType> cargoTypes;

  @override
  State<ContainerSceneView> createState() => _ContainerSceneViewState();
}

class _ContainerSceneViewState extends State<ContainerSceneView> {
  String? _draggingGroup;
  CargoGroupModel? _dragOrigin;
  Offset _dragDelta = Offset.zero;
  Size _size = Size.zero;
  String? _pressedGroup;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _size = Size(constraints.maxWidth, constraints.maxHeight);
      return AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Listener(
              onPointerDown: (event) {
                if (event.buttons == kPrimaryMouseButton) {
                  _pressedGroup = _pickGroup(event.localPosition);
                }
              },
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  controller.changeZoom(event.scrollDelta.dy > 0 ? .9 : 1.1);
                }
              },
              child: GestureDetector(
                dragStartBehavior: DragStartBehavior.down,
                key: const ValueKey('container-3d-scene'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) =>
                    controller.select(_pickGroup(details.localPosition)),
                onPanStart: (details) {
                  final id = _pressedGroup;
                  _dragOrigin = null;
                  if (id == null ||
                      HardwareKeyboard.instance.isShiftPressed ||
                      HardwareKeyboard.instance.isAltPressed) {
                    _draggingGroup = null;
                    return;
                  }
                  controller.beginMove(id);
                  _draggingGroup = id;
                  _dragOrigin = controller.loadedGroups.firstWhere(
                    (group) => group.id == id,
                  );
                  _dragDelta = Offset.zero;
                },
                onPanUpdate: (details) {
                  if (_draggingGroup == null || _dragOrigin == null) {
                    if (HardwareKeyboard.instance.isAltPressed) {
                      controller.orbit(details.delta.dx, details.delta.dy);
                    } else {
                      controller.pan(details.delta.dx, details.delta.dy);
                    }
                    return;
                  }
                  _dragDelta += details.delta;
                  final scale =
                      math.min(_size.width * .76, _size.height * 1.42) /
                      controller.container.lengthMm *
                      controller.zoom;
                  final screenX = _dragDelta.dx / scale;
                  final sinPitch = math.sin(controller.pitch);
                  final depthDelta = sinPitch.abs() < .1
                      ? 0.0
                      : _dragDelta.dy / scale / sinPitch;
                  final dx =
                      math.cos(controller.yaw) * screenX +
                      math.sin(controller.yaw) * depthDelta;
                  final dy =
                      -math.sin(controller.yaw) * screenX +
                      math.cos(controller.yaw) * depthDelta;
                  controller.previewMove(
                    _dragOrigin!.positionXmm + dx.round(),
                    _dragOrigin!.positionYmm + dy.round(),
                    _dragOrigin!.positionZmm,
                  );
                },
                onPanEnd: (_) async {
                  final wasDragging = _draggingGroup != null;
                  _draggingGroup = null;
                  _dragOrigin = null;
                  if (!wasDragging) return;
                  var allow = false;
                  if (controller.pendingOverflow &&
                      controller.invalidGroupId == null) {
                    final bounds = controller.loadedGroups
                        .firstWhere((g) => g.id == controller.selectedGroupId)
                        .bounds;
                    final size = controller.container;
                    final excess =
                        'X +${math.max(0, -bounds.x) + math.max(0, bounds.maxX - size.lengthMm)} / '
                        'Y +${math.max(0, -bounds.y) + math.max(0, bounds.maxY - size.widthMm)} / '
                        'Z +${math.max(0, bounds.maxZ - size.heightMm)} mm';
                    allow =
                        await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: Text(c.l10n.t('cargoOverflowTitle')),
                            content: Text(
                              '$excess\n\n${c.l10n.t('cargoOverflowBody')}',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: Text(c.l10n.t('cargoCancel')),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: Text(c.l10n.t('cargoKeepPlacement')),
                              ),
                            ],
                          ),
                        ) ??
                        false;
                  }
                  if (mounted) controller.endMove(allowOverflow: allow);
                },
                onPanCancel: () {
                  if (_draggingGroup != null) controller.endMove(cancel: true);
                  _draggingGroup = null;
                  _dragOrigin = null;
                },
                onSecondaryTapDown: (details) =>
                    _showGroupMenu(context, details),
                child: MouseRegion(
                  cursor: _draggingGroup == null
                      ? SystemMouseCursors.grab
                      : SystemMouseCursors.grabbing,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: ContainerScenePainter(
                        isZh: context.l10n.isZh,
                        container: controller.container,
                        groups: controller.loadedGroups,
                        cargoNames: widget.cargoNames,
                        selectedGroupId: controller.selectedGroupId,
                        invalidGroupId: controller.invalidGroupId,
                        yaw: controller.yaw,
                        pitch: controller.pitch,
                        zoom: controller.zoom,
                        pan: Offset(controller.panX, controller.panY),
                        containerOpacity: controller.containerOpacity,
                        showGrid: controller.showGrid,
                        showDimensions: controller.showDimensions,
                        sections: controller.sections,
                        focusedSectionId: controller.focusedSectionId,
                        cargoTypes: widget.cargoTypes,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  String? _pickGroup(Offset point) {
    final projection = _SceneProjection(
      size: _size,
      container: widget.controller.container,
      yaw: widget.controller.yaw,
      pitch: widget.controller.pitch,
      zoom: widget.controller.zoom,
      pan: Offset(widget.controller.panX, widget.controller.panY),
    );
    final ordered = [...widget.controller.loadedGroups]
      ..sort(
        (a, b) => projection
            .boxDepth(b.bounds)
            .compareTo(projection.boxDepth(a.bounds)),
      );
    for (final group in ordered) {
      final points = projection.corners(group.bounds);
      for (final face in visibleCargoBoxFaces(
        widget.controller.yaw,
        widget.controller.pitch,
      )) {
        final path = Path()
          ..moveTo(points[face.first].dx, points[face.first].dy);
        for (final i in face.skip(1)) {
          path.lineTo(points[i].dx, points[i].dy);
        }
        path.close();
        if (path.contains(point)) return group.id;
      }
    }
    return null;
  }

  Future<void> _showGroupMenu(
    BuildContext context,
    TapDownDetails details,
  ) async {
    final id = _pickGroup(details.localPosition);
    if (id == null) return;
    widget.controller.select(id);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(details.globalPosition, details.globalPosition),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final axis in ['X', 'Y', 'Z'])
          PopupMenuItem(
            value: 'rotate$axis',
            child: Text(
              context.l10n.isZh ? '绕 $axis 旋转 90°' : 'Rotate $axis by 90°',
            ),
          ),
        PopupMenuItem(
          value: 'duplicate',
          child: Text(context.l10n.isZh ? '复制货物组' : 'Duplicate cargo group'),
        ),
        PopupMenuItem(
          value: 'reset',
          child: Text(
            context.l10n.isZh ? '恢复自动装柜位置' : 'Restore automatic position',
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Text(context.l10n.isZh ? '删除货物组' : 'Delete cargo group'),
        ),
      ],
    );
    switch (value) {
      case 'rotateX':
        widget.controller.rotateSelectedX();
      case 'rotateY':
        widget.controller.rotateSelectedY();
      case 'rotateZ':
        widget.controller.rotateSelectedZ();
      case 'duplicate':
        widget.controller.duplicateSelected();
      case 'reset':
        widget.controller.resetSelected();
      case 'delete':
        widget.controller.deleteSelected();
    }
  }
}

class ContainerScenePainter extends CustomPainter {
  const ContainerScenePainter({
    this.isZh = true,
    required this.container,
    required this.groups,
    required this.cargoNames,
    required this.selectedGroupId,
    required this.invalidGroupId,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.pan,
    required this.containerOpacity,
    required this.showGrid,
    required this.showDimensions,
    this.sections = const [],
    this.focusedSectionId,
    this.cargoTypes = const {},
  });

  final Dimensions3 container;
  final bool isZh;
  final List<CargoGroupModel> groups;
  final Map<String, String> cargoNames;
  final String? selectedGroupId;
  final String? invalidGroupId;
  final double yaw;
  final double pitch;
  final double zoom;
  final Offset pan;
  final double containerOpacity;
  final bool showGrid;
  final bool showDimensions;
  final List<ContainerSection> sections;
  final String? focusedSectionId;
  final Map<String, CargoPackageType> cargoTypes;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF152334), Color(0xFF24384B)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    final projection = _SceneProjection(
      size: size,
      container: container,
      yaw: yaw,
      pitch: pitch,
      zoom: zoom,
      pan: pan,
    );
    _drawFloor(canvas, projection);

    final sorted = [...groups]
      ..sort(
        (a, b) => projection
            .boxDepth(a.bounds)
            .compareTo(projection.boxDepth(b.bounds)),
      );
    for (final group in sorted) {
      _drawCargoGroup(canvas, projection, group);
    }
    // X-ray outlines are intentionally composited last: a centred pallet must
    // remain identifiable even behind an opaque neighbouring carton block.
    for (final g in sorted.where(
      (g) =>
          cargoTypes[g.cargoPackageId] == CargoPackageType.pallet ||
          cargoTypes[g.cargoPackageId] == CargoPackageType.crate,
    )) {
      _drawEdges(
        canvas,
        projection.corners(g.bounds),
        Paint()
          ..color = const Color(0xFF9EDBFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
      _label(
        canvas,
        '${cargoNames[g.cargoPackageId] ?? (isZh ? '托盘' : 'Pallet')} ×${g.quantity}',
        projection
            .project(
              g.positionXmm + g.boundingDimensions.lengthMm / 2,
              g.positionYmm + g.boundingDimensions.widthMm / 2,
              g.bounds.maxZ,
            )
            .translate(0, -10),
        const Color(0xFFBAE5FF),
      );
    }
    _drawContainer(canvas, projection);
    _drawSections(canvas, projection);
    if (showDimensions) _drawDimensions(canvas, projection);
    _drawLegend(canvas, size);
  }

  void _drawFloor(Canvas canvas, _SceneProjection p) {
    final floor = [
      p.project(0, 0, 0),
      p.project(container.lengthMm, 0, 0),
      p.project(container.lengthMm, container.widthMm, 0),
      p.project(0, container.widthMm, 0),
    ];
    canvas.drawPath(
      _path(floor),
      Paint()..color = const Color(0xFFB8CAD7).withValues(alpha: .12),
    );
    if (!showGrid) return;
    final paint = Paint()
      ..color = const Color(0xFFCAD8E2).withValues(alpha: .12)
      ..strokeWidth = 1;
    const parts = 12;
    for (var i = 1; i < parts; i++) {
      final x = container.lengthMm * i / parts;
      canvas.drawLine(
        p.project(x, 0, 0),
        p.project(x, container.widthMm, 0),
        paint,
      );
    }
    for (var i = 1; i < 4; i++) {
      final y = container.widthMm * i / 4;
      canvas.drawLine(
        p.project(0, y, 0),
        p.project(container.lengthMm, y, 0),
        paint,
      );
    }
  }

  void _drawSections(Canvas canvas, _SceneProjection p) {
    final baseline =
        p.boundsFor(Aabb3(x: 0, y: 0, z: 0, dimensions: container)).bottom + 30;
    for (final s in sections) {
      final selected = s.id == focusedSectionId;
      final paint = Paint()
        ..color = selected ? const Color(0xFFFFD28D) : const Color(0xFF8DAABE)
        ..strokeWidth = selected ? 2 : 1;
      canvas.drawLine(
        p.project(s.startXmm, 0, 0),
        p.project(s.startXmm, container.widthMm, 0),
        paint,
      );
      canvas.drawLine(
        p.project(s.endXmm, 0, 0),
        p.project(s.endXmm, container.widthMm, 0),
        paint,
      );
      final anchor = p.project(s.startXmm + s.lengthMm / 2, 0, 0);
      canvas.drawLine(
        anchor.translate(0, 5),
        Offset(anchor.dx, baseline - 10),
        Paint()
          ..color = paint.color.withValues(alpha: .18)
          ..strokeWidth = .7,
      );
      _label(
        canvas,
        'Section ${s.index + 1} · ${(s.lengthMm / 1000).toStringAsFixed(2)}m',
        Offset(anchor.dx, baseline),
        paint.color,
      );
    }
    if (sections.isNotEmpty && sections.last.endXmm < container.lengthMm) {
      _label(
        canvas,
        '${isZh ? '未分配' : 'Unallocated'} ${container.lengthMm - sections.last.endXmm} mm',
        p.project(container.lengthMm, 0, 0).translate(-25, -18),
        const Color(0xFFBCC9D4),
      );
    }
  }

  void _drawLegend(Canvas canvas, Size size) {
    final counts = <String, int>{};
    final colors = <String, int>{};
    for (final g in groups) {
      counts.update(
        g.cargoPackageId,
        (n) => n + g.quantity,
        ifAbsent: () => g.quantity,
      );
      colors[g.cargoPackageId] = g.colorValue;
    }
    var y = 20.0;
    for (final id in counts.keys) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(18, y + 2, 8, 12),
          const Radius.circular(2),
        ),
        Paint()..color = Color(colors[id]!),
      );
      final painter = TextPainter(
        text: TextSpan(
          text: '${cargoNames[id] ?? (isZh ? '货物' : 'Cargo')}  × ${counts[id]}',
          style: const TextStyle(
            fontFamily: 'Microsoft YaHei UI',
            fontSize: 12,
            color: Color(0xFFE7EEF3),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(20, size.width - 300));
      painter.paint(canvas, Offset(34, y));
      y += 24;
    }
  }

  void _drawContainer(Canvas canvas, _SceneProjection p) {
    final box = Aabb3(x: 0, y: 0, z: 0, dimensions: container);
    final corners = p.corners(box);
    final facePaint = Paint()
      ..color = const Color(0xFF91AABC)
          .withValues(alpha: containerOpacity * .22);
    canvas.drawPath(
      _path([corners[4], corners[5], corners[6], corners[7]]),
      facePaint,
    );
    final edge = Paint()
      ..color = const Color(0xFFD4E2EB).withValues(alpha: containerOpacity + .3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35;
    _drawEdges(canvas, corners, edge);
    final door = Paint()
      ..color = const Color(0xFFE5EEF4).withValues(alpha: .45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(
      _path([corners[0], corners[3], corners[7], corners[4]]),
      door,
    );
  }

  void _drawCargoGroup(
    Canvas canvas,
    _SceneProjection p,
    CargoGroupModel group,
  ) {
    final points = p.corners(group.bounds);
    final color =
        focusedSectionId != null && group.sectionId != focusedSectionId
        ? Color.lerp(Color(group.colorValue), const Color(0xFF203343), .35)!
        : Color(group.colorValue);
    final invalid =
        group.id == invalidGroupId ||
        (group.sectionId != null && !group.bounds.inside(container));
    final selected = group.id == selectedGroupId;
    // Select the visible face for each axis from the camera direction. The
    // previous implementation always painted +X/-Y/+Z, leaving holes on orbit.
    final visible = visibleCargoBoxFaces(yaw, pitch);
    final faces = [(visible[0], .82), (visible[1], .94), (visible[2], 1.12)];
    for (final face in faces) {
      final material = face.$2 > 1
          ? Color.lerp(color, Colors.white, face.$2 - 1)!
          : Color.lerp(Colors.black, color, face.$2)!;
      canvas.drawPath(
        _path([for (final i in face.$1) points[i]]),
        Paint()..color = material,
      );
    }
    final edge = Paint()
      ..color = invalid
          ? const Color(0xFFFF7A70)
          : selected
          ? const Color(0xFFFFD28D)
          : const Color(0xFF172431).withValues(alpha: .7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = invalid || selected ? 2.4 : .8;
    _drawEdges(canvas, points, edge);
    if (cargoTypes[group.cargoPackageId] == CargoPackageType.pallet) {
      canvas.drawLine(
        points[0],
        points[1],
        Paint()
          ..color = Color.lerp(color, Colors.black, .3)!
          ..strokeWidth = 4,
      );
      canvas.drawLine(
        points[1],
        points[2],
        Paint()
          ..color = Color.lerp(color, Colors.black, .3)!
          ..strokeWidth = 4,
      );
    }
    if (showGrid) _drawGroupGrid(canvas, p, group);
  }

  void _drawGroupGrid(
    Canvas canvas,
    _SceneProjection p,
    CargoGroupModel group,
  ) {
    final paint = Paint()
      ..color = const Color(0xFF1C2B36).withValues(alpha: .42)
      ..strokeWidth = .65;
    final x =
        group.positionXmm +
        (math.sin(yaw) >= 0 ? group.boundingDimensions.lengthMm : 0);
    final y0 = group.positionYmm;
    final z0 = group.positionZmm;
    for (var row = 1; row < group.rows; row += math.max(1, group.rows ~/ 160)) {
      final y = y0 + group.boundingDimensions.widthMm * row / group.rows;
      canvas.drawLine(
        p.project(x, y, z0),
        p.project(x, y, z0 + group.boundingDimensions.heightMm),
        paint,
      );
    }
    for (
      var layer = 1;
      layer < group.layers;
      layer += math.max(1, group.layers ~/ 160)
    ) {
      final z = z0 + group.boundingDimensions.heightMm * layer / group.layers;
      canvas.drawLine(
        p.project(x, y0, z),
        p.project(x, y0 + group.boundingDimensions.widthMm, z),
        paint,
      );
    }
  }

  void _drawDimensions(Canvas canvas, _SceneProjection p) {
    _label(
      canvas,
      '${_m(container.lengthMm)} m',
      Offset(
        p.project(container.lengthMm / 2, 0, 0).dx,
        p.boundsFor(Aabb3(x: 0, y: 0, z: 0, dimensions: container)).bottom + 60,
      ),
      const Color(0xFFCFDCE5),
    );
    _label(
      canvas,
      '${_m(container.widthMm)} m',
      p.project(container.lengthMm, container.widthMm / 2, 0).translate(20, 0),
      const Color(0xFFCFDCE5),
    );
    _label(
      canvas,
      '${_m(container.heightMm)} m',
      p.project(0, 0, container.heightMm / 2).translate(-22, 0),
      const Color(0xFFCFDCE5),
    );
  }

  static String _m(int mm) => (mm / 1000).toStringAsFixed(2);

  static void _drawEdges(Canvas canvas, List<Offset> p, Paint paint) {
    const edges = [
      (0, 1),
      (1, 2),
      (2, 3),
      (3, 0),
      (4, 5),
      (5, 6),
      (6, 7),
      (7, 4),
      (0, 4),
      (1, 5),
      (2, 6),
      (3, 7),
    ];
    for (final edge in edges) {
      canvas.drawLine(p[edge.$1], p[edge.$2], paint);
    }
  }

  static Path _path(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  static void _label(Canvas canvas, String value, Offset center, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          fontFamily: 'Microsoft YaHei UI',
          shadows: const [Shadow(color: Color(0x99000000), blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(ContainerScenePainter oldDelegate) => true;
}

class _SceneProjection {
  const _SceneProjection({
    required this.size,
    required this.container,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.pan,
  });

  final Size size;
  final Dimensions3 container;
  final double yaw;
  final double pitch;
  final double zoom;
  final Offset pan;

  double boxDepth(Aabb3 box) =>
      math.cos(pitch) *
          (math.sin(yaw) * (box.x + box.dimensions.lengthMm / 2) +
              math.cos(yaw) * (box.y + box.dimensions.widthMm / 2)) +
      math.sin(pitch) * (box.z + box.dimensions.heightMm / 2);

  Offset project(num x, num y, num z) {
    final cx = container.lengthMm / 2;
    final cy = container.widthMm / 2;
    final cz = container.heightMm / 2;
    final vx = x - cx;
    final vy = y - cy;
    final vz = z - cz;
    final rx = math.cos(yaw) * vx - math.sin(yaw) * vy;
    final depth = math.sin(yaw) * vx + math.cos(yaw) * vy;
    final ry = math.cos(pitch) * vz - math.sin(pitch) * depth;
    final scale =
        math.min(size.width * .76, size.height * 1.42) /
        container.lengthMm *
        zoom;
    return Offset(
      size.width / 2 + pan.dx + rx * scale,
      size.height / 2 + pan.dy - ry * scale,
    );
  }

  List<Offset> corners(Aabb3 box) => [
    project(box.x, box.y, box.z),
    project(box.maxX, box.y, box.z),
    project(box.maxX, box.maxY, box.z),
    project(box.x, box.maxY, box.z),
    project(box.x, box.y, box.maxZ),
    project(box.maxX, box.y, box.maxZ),
    project(box.maxX, box.maxY, box.maxZ),
    project(box.x, box.maxY, box.maxZ),
  ];

  Rect boundsFor(Aabb3 box) {
    final values = corners(box);
    return Rect.fromLTRB(
      values.map((point) => point.dx).reduce(math.min),
      values.map((point) => point.dy).reduce(math.min),
      values.map((point) => point.dx).reduce(math.max),
      values.map((point) => point.dy).reduce(math.max),
    );
  }
}
