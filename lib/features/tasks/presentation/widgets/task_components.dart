import 'package:flutter/material.dart';

import '../../../../shared/design_system/design_tokens.dart';
import '../../domain/task.dart';

class FlyTaskCheckbox extends StatelessWidget {
  const FlyTaskCheckbox({
    required this.value,
    this.onChanged,
    this.compact = false,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: compact ? 22 : 28,
    child: Transform.scale(
      scale: compact ? 0.78 : 0.88,
      child: Checkbox(
        value: value,
        onChanged: onChanged == null
            ? null
            : (next) => onChanged!(next ?? false),
      ),
    ),
  );
}

class FlyTaskTitle extends StatelessWidget {
  const FlyTaskTitle({
    required this.task,
    this.compact = false,
    this.maxLines = 1,
    this.disabled = false,
    super.key,
  });

  final FlyTask task;
  final bool compact;
  final int maxLines;
  final bool disabled;

  @override
  Widget build(BuildContext context) => Text(
    task.title,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontSize: compact ? FlyType.meta : FlyType.task,
      height: compact ? 1.1 : 1.25,
      color: disabled || task.isCompleted
          ? Theme.of(context).colorScheme.onSurfaceVariant
          : Theme.of(context).colorScheme.onSurface,
      decoration: task.isCompleted ? TextDecoration.lineThrough : null,
      decorationColor: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class FlyTaskRowSurface extends StatefulWidget {
  const FlyTaskRowSurface({
    required this.task,
    required this.onTap,
    this.onCompleted,
    this.selected = false,
    this.compact = false,
    this.dateLabel,
    this.metadata,
    this.accent,
    this.trailing,
    this.onSecondaryTapDown,
    this.disabled = false,
    super.key,
  });

  final FlyTask task;
  final VoidCallback onTap;
  final ValueChanged<bool>? onCompleted;
  final bool selected;
  final bool compact;
  final String? dateLabel;
  final String? metadata;
  final Color? accent;
  final Widget? trailing;
  final GestureTapDownCallback? onSecondaryTapDown;
  final bool disabled;

  @override
  State<FlyTaskRowSurface> createState() => _FlyTaskRowSurfaceState();
}

class _FlyTaskRowSurfaceState extends State<FlyTaskRowSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = widget.disabled
        ? (dark ? FlyColors.hoverDark : FlyColors.hoverLight)
        : widget.task.isCompleted
        ? (dark ? FlyColors.completedDark : FlyColors.completedLight)
        : widget.selected
        ? (dark ? FlyColors.selectedDark : FlyColors.selectedLight)
        : _hovered
        ? (dark ? FlyColors.hoverDark : FlyColors.hoverLight)
        : Colors.transparent;
    final accent = widget.accent ?? FlyColors.accent;

    return MouseRegion(
      cursor: widget.disabled
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        child: InkWell(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: FlyMotion.fast,
            height: widget.metadata != null
                ? 44
                : widget.compact
                ? FlyMetrics.compactTaskRowHeight
                : FlyMetrics.taskRowHeight,
            decoration: BoxDecoration(
              color: background,
              border: Border(
                left: BorderSide(
                  color: widget.selected ? accent : Colors.transparent,
                  width: 2,
                ),
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: widget.compact ? 0.5 : 1,
                ),
              ),
            ),
            padding: EdgeInsets.only(
              left: widget.compact ? 2 : FlySpacing.xs,
              right: widget.compact ? 4 : FlySpacing.xs,
            ),
            child: Row(
              children: [
                FlyTaskCheckbox(
                  value: widget.task.isCompleted,
                  compact: widget.compact,
                  onChanged: widget.onCompleted,
                ),
                SizedBox(width: widget.compact ? 2 : FlySpacing.xs),
                Expanded(
                  child: widget.metadata == null
                      ? FlyTaskTitle(
                          task: widget.task,
                          compact: widget.compact,
                          disabled: widget.disabled,
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: FlyTaskTitle(
                                task: widget.task,
                                compact: false,
                                disabled: widget.disabled,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.metadata!,
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                ),
                if (widget.task.priority != TaskPriority.none) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.flag_rounded,
                    size: widget.compact ? 12 : 15,
                    color: switch (widget.task.priority) {
                      TaskPriority.high => FlyColors.danger,
                      TaskPriority.medium => FlyColors.warning,
                      TaskPriority.low => FlyColors.accent,
                      TaskPriority.none => Colors.transparent,
                    },
                  ),
                ],
                if (widget.dateLabel != null) ...[
                  const SizedBox(width: FlySpacing.xs),
                  Text(
                    widget.dateLabel!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FlyTaskDragFeedback extends StatelessWidget {
  const FlyTaskDragFeedback({required this.task, super.key});

  final FlyTask task;

  @override
  Widget build(BuildContext context) => Material(
    elevation: FlyElevation.popup,
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(FlyRadius.sm),
    child: SizedBox(
      width: 260,
      height: FlyMetrics.taskRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: FlySpacing.sm),
        child: Row(
          children: [
            const Icon(Icons.drag_indicator, size: 16),
            const SizedBox(width: FlySpacing.xs),
            Expanded(child: FlyTaskTitle(task: task)),
          ],
        ),
      ),
    ),
  );
}
