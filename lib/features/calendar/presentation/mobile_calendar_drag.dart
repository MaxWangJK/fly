import 'dart:async';

import 'package:flutter/material.dart';

import '../../tasks/domain/task.dart';

class CalendarTaskDrag {
  CalendarTaskDrag(this.task, this.anchor);
  final FlyTask task;
  final DateTime anchor;
  Offset feedbackAnchor = Offset.zero;
}

FlyTask shiftCalendarTask(
  FlyTask task,
  DateTime from,
  DateTime to, {
  bool time = false,
}) {
  final days = DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
  final minutes = time && !task.isAllDay
      ? to.hour * 60 + to.minute - from.hour * 60 - from.minute
      : 0;
  DateTime? shift(DateTime? value) {
    if (value == null) return null;
    final shifted = value.isUtc
        ? DateTime.utc(
            value.year,
            value.month,
            value.day + days,
            value.hour,
            value.minute,
            value.second,
            value.millisecond,
            value.microsecond,
          )
        : DateTime(
            value.year,
            value.month,
            value.day + days,
            value.hour,
            value.minute,
            value.second,
            value.millisecond,
            value.microsecond,
          );
    return shifted.add(Duration(minutes: minutes));
  }

  return task.copyWith(
    startDate: shift(task.startDate),
    dueDate: shift(task.dueDate),
  );
}

typedef CalendarMove = void Function(
  CalendarTaskDrag drag,
  DateTime target,
  bool time,
);

Widget draggableCalendarTask(
  BuildContext context,
  FlyTask task,
  DateTime anchor,
  Widget child, {
  ValueChanged<DragUpdateDetails>? onDragUpdate,
  VoidCallback? onDragEnd,
}) {
  final data = CalendarTaskDrag(task, anchor);
  return LongPressDraggable<CalendarTaskDrag>(
    data: data,
    dragAnchorStrategy: (draggable, context, position) {
      data.feedbackAnchor = childDragAnchorStrategy(
        draggable,
        context,
        position,
      );
      return data.feedbackAnchor;
    },
    maxSimultaneousDrags: 1,
    onDragUpdate: onDragUpdate,
    onDragEnd: (_) => onDragEnd?.call(),
    feedback: Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: SizedBox(
        width: 150,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ),
    ),
    childWhenDragging: IgnorePointer(
      child: Opacity(opacity: .35, child: child),
    ),
    child: child,
  );
}

class CalendarDropTarget extends StatelessWidget {
  const CalendarDropTarget({
    required this.target,
    required this.move,
    required this.child,
    this.time = false,
    this.resolveTarget,
    this.highlight = true,
    super.key,
  });
  final DateTime target;
  final CalendarMove move;
  final Widget child;
  final bool time, highlight;
  final DateTime Function(DragTargetDetails<CalendarTaskDrag>)? resolveTarget;
  @override
  Widget build(BuildContext context) => DragTarget<CalendarTaskDrag>(
    onAcceptWithDetails: (details) =>
        move(details.data, resolveTarget?.call(details) ?? target, time),
    builder: (context, candidates, rejected) => Container(
      decoration: candidates.isEmpty || !highlight
          ? null
          : BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer
                  .withValues(alpha: .5),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
      child: child,
    ),
  );
}

class CalendarDragAutoScroller {
  CalendarDragAutoScroller({
    required this.vertical,
    required this.verticalViewport,
    this.horizontal,
    this.horizontalViewport,
  });
  final ScrollController vertical;
  final GlobalKey verticalViewport;
  final ScrollController? horizontal;
  final GlobalKey? horizontalViewport;
  Timer? _timer;
  Offset? _position;
  void update(DragUpdateDetails details) {
    _position = details.globalPosition;
    _timer ??= Timer.periodic(const Duration(milliseconds: 20), (_) {
      _scroll(vertical, verticalViewport, false);
      if (horizontal != null && horizontalViewport != null) {
        _scroll(horizontal!, horizontalViewport!, true);
      }
    });
  }

  void _scroll(ScrollController controller, GlobalKey key, bool horizontal) {
    final object = key.currentContext?.findRenderObject();
    if (_position == null ||
        !controller.hasClients ||
        object is! RenderBox ||
        !object.hasSize) {
      return;
    }
    final rect = object.localToGlobal(Offset.zero) & object.size;
    final pointer = horizontal ? _position!.dx : _position!.dy;
    final from = horizontal ? rect.left : rect.top,
        to = horizontal ? rect.right : rect.bottom;
    final delta = pointer >= from - 24 && pointer < from + 26
        ? -5.0
        : pointer <= to + 24 && pointer > to - 26
        ? 5.0
        : 0.0;
    if (delta == 0) return;
    final next = (controller.offset + delta).clamp(
      controller.position.minScrollExtent,
      controller.position.maxScrollExtent,
    );
    if (next != controller.offset) controller.jumpTo(next);
  }

  void end() {
    _timer?.cancel();
    _timer = null;
    _position = null;
  }

  void dispose() => end();
}
