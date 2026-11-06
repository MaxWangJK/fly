import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../l10n/fly_localizations.dart';
import '../../../../../shared/design_system/fly_color_scheme.dart';
import '../../domain/models/container_loading_models.dart';
import '../../domain/models/section_models.dart';
import 'container_scene_controller.dart';

/// Front view of actual scene groups. Both editors mutate the same controller;
/// no derived packing result or second set of coordinates is persisted here.
class SectionPlacementEditor extends StatefulWidget {
  const SectionPlacementEditor({
    required this.controller,
    required this.sectionId,
    required this.names,
    this.spaces = const [],
    this.assignedSpaceIds = const [],
    this.onSpaceTap,
    super.key,
  });
  final ContainerSceneController controller;
  final String sectionId;
  final Map<String, String> names;
  final List<LoadingSpace> spaces;
  final List<String> assignedSpaceIds;
  final void Function(LoadingSpace space, Offset globalPosition)? onSpaceTap;

  @override
  State<SectionPlacementEditor> createState() => _SectionPlacementEditorState();
}

class _SectionPlacementEditorState extends State<SectionPlacementEditor> {
  CargoGroupModel? _drag;
  Offset _delta = Offset.zero;
  _SectionTransform? _dragTransform;

  Future<void> _showCargoMenu(
    CargoGroupModel group,
    Offset globalPosition,
  ) async {
    final scene = widget.controller;
    scene.select(group.id);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final point = overlay.globalToLocal(globalPosition);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(point.dx, point.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final axis in ['X', 'Y', 'Z'])
          PopupMenuItem(
            value: axis,
            child: Text(
              context.l10n.isZh ? '绕 $axis 旋转 90°' : 'Rotate $axis by 90°',
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Text(context.l10n.isZh ? '移除货物' : 'Remove cargo'),
        ),
      ],
    );
    if (!mounted ||
        action == null ||
        !scene.loadedGroups.any((g) => g.id == group.id)) {
      return;
    }
    // Act on the cargo that opened the menu, never a later selection.
    scene.select(group.id);
    switch (action) {
      case 'X':
        scene.rotateSelectedX();
      case 'Y':
        scene.rotateSelectedY();
      case 'Z':
        scene.rotateSelectedZ();
      case 'delete':
        scene.deleteSelected();
    }
    final message = action == 'delete'
        ? (context.l10n.isZh
              ? '已移除这组货物，可点撤销恢复。'
              : 'Cargo group removed. Use Undo to restore it.')
        : scene.invalidGroupId == group.id
        ? (context.l10n.isZh
              ? '旋转后会重叠、越界或不符合堆叠条件，请先调整位置。'
              : 'Rotation would overlap, exceed bounds or violate stacking rules. Adjust the position first.')
        : null;
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _finish() async {
    final controller = widget.controller;
    if (_drag == null) return;
    _drag = null;
    _dragTransform = null;
    var allow = false;
    if (controller.pendingOverflow && controller.invalidGroupId == null) {
      allow =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(context.l10n.t('cargoOverflowTitle')),
              content: Text(context.l10n.t('cargoOverflowBody')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(context.l10n.t('cargoCancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(context.l10n.t('cargoKeepPlacement')),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (mounted) controller.endMove(allowOverflow: allow);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final scene = widget.controller;
        final groups = scene.loadedGroups
            .where((g) => g.sectionId == widget.sectionId)
            .toList();
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final transform =
            _dragTransform ?? _SectionTransform(size, scene.container, groups);
        CargoGroupModel? hit(Offset point) {
          for (final g in groups.reversed) {
            if (transform.rect(g).contains(point)) return g;
          }
          return null;
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (event) {
            final group = hit(event.localPosition);
            scene.select(group?.id);
            if (group != null) return;
            final space =
                LoadingSpace.suggested(widget.spaces, widget.assignedSpaceIds)
                    .where(
                      (s) =>
                          s.isUsefulForLoading &&
                          transform.spaceRect(s).contains(event.localPosition),
                    )
                    .lastOrNull;
            if (space != null) {
              widget.onSpaceTap?.call(space, event.globalPosition);
            }
          },
          onSecondaryTapUp: (event) {
            final group = hit(event.localPosition);
            if (group != null) _showCargoMenu(group, event.globalPosition);
          },
          onPanStart: (event) {
            _drag = hit(event.localPosition);
            if (_drag == null) return;
            _delta = Offset.zero;
            _dragTransform = transform;
            scene.beginMove(_drag!.id);
          },
          onPanUpdate: (event) {
            final group = _drag;
            if (group == null) return;
            _delta += event.delta;
            scene.previewMove(
              group.positionXmm,
              group.positionYmm + (_delta.dx / transform.scale).round(),
              math.max(
                0,
                group.positionZmm - (_delta.dy / transform.scale).round(),
              ),
            );
          },
          onPanEnd: (_) => _finish(),
          onPanCancel: () {
            if (_drag != null) scene.endMove(cancel: true);
            _drag = null;
            _dragTransform = null;
          },
          child: CustomPaint(
            size: size,
            painter: _SectionPainter(
              scene,
              groups,
              transform,
              widget.names,
              context.flyColors,
              widget.spaces,
              widget.assignedSpaceIds,
              context.l10n.isZh,
            ),
          ),
        );
      },
    ),
  );
}

class _SectionTransform {
  _SectionTransform(
    Size size,
    Dimensions3 container,
    List<CargoGroupModel> groups,
  ) {
    final minY = groups.fold<int>(0, (v, g) => math.min(v, g.positionYmm));
    final maxY = groups.fold<int>(
      container.widthMm,
      (v, g) => math.max(v, g.bounds.maxY),
    );
    final maxZ = groups.fold<int>(
      container.heightMm,
      (v, g) => math.max(v, g.bounds.maxZ),
    );
    scale = math.max(
      .001,
      math.min((size.width - 48) / (maxY - minY), (size.height - 44) / maxZ),
    );
    origin = Offset(
      (size.width - (maxY - minY) * scale) / 2 - minY * scale,
      size.height - 24,
    );
  }
  late final double scale;
  late final Offset origin;
  Rect rect(CargoGroupModel g) => Rect.fromLTWH(
    origin.dx + g.positionYmm * scale,
    origin.dy - g.bounds.maxZ * scale,
    g.boundingDimensions.widthMm * scale,
    g.boundingDimensions.heightMm * scale,
  );
  Rect spaceRect(LoadingSpace space) => Rect.fromLTWH(
    origin.dx + space.bounds.y * scale,
    origin.dy - space.bounds.maxZ * scale,
    space.bounds.dimensions.widthMm * scale,
    space.bounds.dimensions.heightMm * scale,
  );
}

class _SectionPainter extends CustomPainter {
  _SectionPainter(
    this.scene,
    this.groups,
    this.transform,
    this.names,
    this.colors,
    this.spaces,
    this.assignedSpaceIds,
    this.isZh,
  );
  final ContainerSceneController scene;
  final List<CargoGroupModel> groups;
  final _SectionTransform transform;
  final Map<String, String> names;
  final FlyColorScheme colors;
  final List<LoadingSpace> spaces;
  final List<String> assignedSpaceIds;
  final bool isZh;
  void label(Canvas canvas, String text, Offset point, double width) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Microsoft YaHei UI',
          fontSize: 10,
          color: colors.textPrimary,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: math.max(1, width));
    painter.paint(canvas, point);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = transform;
    final outline = Rect.fromLTWH(
      t.origin.dx,
      t.origin.dy - scene.container.heightMm * t.scale,
      scene.container.widthMm * t.scale,
      scene.container.heightMm * t.scale,
    );
    canvas.drawRect(outline, Paint()..color = colors.canvas);
    final offered = LoadingSpace.suggested(spaces, assignedSpaceIds);
    for (final space in spaces) {
      final b = space.bounds;
      final rect = Rect.fromLTWH(
        t.origin.dx + b.y * t.scale,
        t.origin.dy - b.maxZ * t.scale,
        b.dimensions.widthMm * t.scale,
        b.dimensions.heightMm * t.scale,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = colors.accent.withValues(
            alpha: space.isUsefulForLoading ? .10 : .03,
          ),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = colors.textSecondary.withValues(alpha: .4)
          ..style = PaintingStyle.stroke,
      );
      final shown = offered.where((s) => s.id == space.id).firstOrNull;
      if (shown != null && rect.width >= 42 && rect.height >= 24) {
        label(
          canvas,
          '${isZh ? shown.name : 'Area ${shown.name.replaceAll('区', '')}'} · ${b.dimensions.widthMm} × ${b.dimensions.heightMm} mm',
          rect.topLeft + const Offset(3, 3),
          rect.width - 6,
        );
      }
    }
    for (final g in groups) {
      final rect = t.rect(g);
      final overflow = !g.bounds.inside(scene.container);
      canvas.drawRect(
        rect,
        Paint()..color = Color(g.colorValue).withValues(alpha: .65),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = scene.selectedGroupId == g.id ? 3 : 1
          ..color = overflow || scene.invalidGroupId == g.id
              ? colors.danger
              : colors.textSecondary,
      );
      label(
        canvas,
        '${names[g.cargoPackageId] ?? ''} × ${g.quantity}',
        rect.topLeft + const Offset(3, 3),
        rect.width - 6,
      );
      if (g.bounds.maxZ > scene.container.heightMm) {
        label(
          canvas,
          '+${g.bounds.maxZ - scene.container.heightMm} mm',
          Offset(rect.left, math.max(0, rect.top - 14)),
          rect.width,
        );
      }
    }
    canvas.drawRect(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = colors.accent,
    );
    label(
      canvas,
      '${scene.container.widthMm} × ${scene.container.heightMm} mm',
      Offset(outline.left, t.origin.dy + 5),
      size.width - outline.left,
    );
  }

  @override
  bool shouldRepaint(covariant _SectionPainter oldDelegate) => true;
}
