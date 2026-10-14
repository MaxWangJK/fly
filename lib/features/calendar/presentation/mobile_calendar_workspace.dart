import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/shell/mobile_details.dart';
import '../../../l10n/fly_localizations.dart';
import '../../../l10n/service_error_copy.dart';
import '../../tasks/domain/task.dart';
import '../../tasks/domain/task_date_range.dart';
import '../../tasks/presentation/task_providers.dart';
import '../../tasks/presentation/widgets/task_view_links.dart';
import 'mobile_calendar_drag.dart';

enum MobileCalendarView { schedule, day, threeDays, week, month }

bool mobileTaskOccursOnDay(FlyTask task, DateTime date) {
  if (task.isAllDay) return TaskDateRange.contains(task, date);
  if (task.isDeleted) return false;
  final start = task.startDate ?? task.dueDate;
  if (start == null) return false;
  final end = task.dueDate != null && task.dueDate!.isAfter(start)
      ? task.dueDate!
      : start.add(const Duration(hours: 1));
  final day = DateTime(date.year, date.month, date.day);
  return start.isBefore(DateTime(day.year, day.month, day.day + 1)) &&
      end.isAfter(day);
}

class MobileCalendarWorkspace extends ConsumerStatefulWidget {
  const MobileCalendarWorkspace({super.key});
  @override
  ConsumerState<MobileCalendarWorkspace> createState() =>
      _MobileCalendarWorkspaceState();
}

class _MobileCalendarWorkspaceState
    extends ConsumerState<MobileCalendarWorkspace> {
  MobileCalendarView view = MobileCalendarView.week;
  late DateTime date;
  int scheduleDays = 90;
  final _monthScroll = ScrollController();
  final _monthViewport = GlobalKey();
  late final _monthAuto = CalendarDragAutoScroller(
    vertical: _monthScroll,
    verticalViewport: _monthViewport,
  );
  @override
  void dispose() {
    _monthAuto.dispose();
    _monthScroll.dispose();
    super.dispose();
  }

  bool get zh => context.l10n.isZh;
  @override
  void initState() {
    super.initState();
    date = day(ref.read(selectedDateProvider) ?? DateTime.now());
  }

  static DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  String label(MobileCalendarView value) => switch (value) {
    MobileCalendarView.schedule => zh ? '日程' : 'Schedule',
    MobileCalendarView.day => zh ? '日' : 'Day',
    MobileCalendarView.threeDays => zh ? '3天' : '3 days',
    MobileCalendarView.week => zh ? '周' : 'Week',
    MobileCalendarView.month => zh ? '月' : 'Month',
  };
  void focus(DateTime value) {
    setState(() {
      date = day(value);
      scheduleDays = 90;
    });
    ref.read(selectedDateProvider.notifier).state = date;
    ref.read(calendarMonthProvider.notifier).state = DateTime(
      date.year,
      date.month,
    );
  }

  void step(int direction) {
    focus(
      view == MobileCalendarView.month || view == MobileCalendarView.schedule
          ? DateTime(
              date.year,
              date.month + direction,
              math.min(
                date.day,
                DateTime(date.year, date.month + direction + 1, 0).day,
              ),
            )
          : date.add(
              Duration(
                days:
                    direction *
                    (view == MobileCalendarView.week
                        ? 7
                        : view == MobileCalendarView.threeDays
                        ? 3
                        : 1),
              ),
            ),
    );
  }

  List<FlyTask> onDay(List<FlyTask> tasks, DateTime value) =>
      tasks.where((task) => mobileTaskOccursOnDay(task, value)).toList()
        ..sort((a, b) {
          if (a.isAllDay != b.isAllDay) return a.isAllDay ? -1 : 1;
          final time = (a.startDate ?? a.dueDate!).compareTo(
            b.startDate ?? b.dueDate!,
          );
          return time != 0 ? time : b.createdAt.compareTo(a.createdAt);
        });

  Future<void> chooseDate(List<FlyTask> tasks) async {
    var month = DateTime(date.year, date.month);
    final chosen = await showModalBottomSheet<DateTime>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => update(
                      () => month = DateTime(month.year, month.month - 1),
                    ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        DateFormat.yMMMM(zh ? 'zh_CN' : 'en').format(month),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => update(
                      () => month = DateTime(month.year, month.month + 1),
                    ),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              monthGrid(
                month,
                tasks,
                (value) => Navigator.pop(sheet, value),
                compact: true,
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null && mounted) focus(chosen);
  }

  Future<void> create(DateTime value, {bool timed = false}) async {
    final draft =
        await showModalBottomSheet<
          ({String title, DateTime start, bool allDay, int minutes})
        >(
          context: context,
          useRootNavigator: true,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _CalendarTaskComposer(initial: value, allDay: !timed),
        );
    if (draft == null || !mounted) return;
    try {
      final repository = ref.read(taskRepositoryProvider);
      final task = await repository.createTask(
        title: draft.title,
        dueDate: draft.start,
      );
      await repository.saveTask(
        task.copyWith(
          startDate: draft.start,
          dueDate: draft.allDay
              ? day(draft.start)
              : draft.start.add(Duration(minutes: draft.minutes)),
          isAllDay: draft.allDay,
        ),
      );
      if (mounted) focus(draft.start);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.flyError(e))));
      }
    }
  }

  Future<void> moveTask(
    CalendarTaskDrag drag,
    DateTime target,
    bool time,
  ) async {
    final repo = ref.read(taskRepositoryProvider);
    try {
      final latest = await repo.watchTask(drag.task.id).first;
      if (latest == null || latest.isDeleted) throw StateError('任务已删除');
      if (latest.startDate != drag.task.startDate ||
          latest.dueDate != drag.task.dueDate ||
          latest.isAllDay != drag.task.isAllDay) {
        throw StateError('任务日期已发生变化，请重新拖动');
      }
      final moved = shiftCalendarTask(latest, drag.anchor, target, time: time);
      await repo.saveTask(moved);
      if (!mounted) return;
      final display = target.toLocal();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已改期至 ${DateFormat(latest.isAllDay || !time ? 'M月d日' : 'M月d日 HH:mm').format(display)}',
          ),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () async {
              try {
                final current = await repo.watchTask(latest.id).first;
                if (current == null ||
                    current.isDeleted ||
                    current.startDate != moved.startDate ||
                    current.dueDate != moved.dueDate) {
                  throw StateError('日期已再次变更，无法撤销这次移动');
                }
                await repo.saveTask(
                  current.copyWith(
                    startDate: latest.startDate,
                    dueDate: latest.dueDate,
                  ),
                );
              } catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('$error')));
                }
              }
            },
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('改期失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(allTasksProvider);
    return SafeArea(
      child: Column(
        key: const ValueKey('phone-calendar'),
        children: [
          Row(
            children: [
              PopupMenuButton<MobileCalendarView>(
                key: const ValueKey('mobile-calendar-view'),
                tooltip: zh ? '日历视图' : 'Calendar view',
                icon: const Icon(Icons.menu),
                initialValue: view,
                onSelected: (value) => setState(() => view = value),
                itemBuilder: (_) => [
                  for (final value in [
                    MobileCalendarView.week,
                    MobileCalendarView.month,
                  ])
                    CheckedPopupMenuItem(
                      value: value,
                      checked: value == view,
                      child: Text(label(value)),
                    ),
                ],
              ),
              Expanded(
                child: TextButton(
                  key: const ValueKey('mobile-calendar-date'),
                  onPressed: () => chooseDate(tasks.valueOrNull ?? []),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          DateFormat.yMMMM(zh ? 'zh_CN' : 'en').format(date),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.expand_more, size: 18),
                    ],
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('mobile-calendar-today'),
                tooltip: context.l10n.t('today'),
                onPressed: () => focus(DateTime.now()),
                icon: const Icon(Icons.today),
              ),
              IconButton(
                tooltip: zh ? '上一页' : 'Previous',
                onPressed: () => step(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: zh ? '下一页' : 'Next',
                onPressed: () => step(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: const TaskViewLinks(current: 'calendar'),
          ),
          Expanded(
            child: GestureDetector(
              onHorizontalDragEnd:
                  view == MobileCalendarView.month ||
                      view == MobileCalendarView.schedule
                  ? (details) {
                      if ((details.primaryVelocity ?? 0).abs() > 150) {
                        step(details.primaryVelocity! < 0 ? 1 : -1);
                      }
                    }
                  : null,
              child: tasks.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator.adaptive()),
                error: (e, _) => Center(child: Text(context.flyError(e))),
                data: (items) => Stack(
                  children: [
                    Positioned.fill(
                      child: switch (view) {
                        MobileCalendarView.schedule => schedule(items),
                        MobileCalendarView.month => SingleChildScrollView(
                          key: _monthViewport,
                          controller: _monthScroll,
                          child: monthGrid(date, items, (value) {
                            focus(value);
                            setState(() => view = MobileCalendarView.week);
                          }),
                        ),
                        _ => timeline(items),
                      },
                    ),
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: FloatingActionButton(
                        key: const ValueKey('mobile-calendar-create'),
                        tooltip: context.l10n.t('addTask'),
                        onPressed: () => create(date),
                        child: const Icon(Icons.add),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget event(FlyTask task) => Material(
    color: task.isCompleted
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : Theme.of(context).colorScheme.primaryContainer,
    borderRadius: BorderRadius.circular(10),
    child: ListTile(
      key: ValueKey('calendar-agenda-${task.id}'),
      title: Text(
        task.title,
        style: TextStyle(
          decoration: task.isCompleted ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        task.isAllDay
            ? (zh ? '全天' : 'All day')
            : '${DateFormat.Hm().format(task.startDate ?? task.dueDate!)} — ${DateFormat.Hm().format(task.dueDate ?? task.startDate!)}',
      ),
      onTap: () => showTaskDetailSheet(context, task.id),
      trailing: Checkbox(
        value: task.isCompleted,
        onChanged: (v) => ref
            .read(taskRepositoryProvider)
            .setCompleted(task.id, completed: v == true),
      ),
    ),
  );

  Widget schedule(List<FlyTask> tasks) {
    final end = date.add(Duration(days: scheduleDays));
    final dates = <DateTime>{date};
    for (final task in tasks) {
      final start = task.startDate ?? task.dueDate;
      final finish = task.dueDate ?? start;
      if (start == null ||
          finish == null ||
          day(finish).isBefore(date) ||
          !day(start).isBefore(end)) {
        continue;
      }
      final clipped = day(start).isBefore(date) ? date : day(start);
      // Multi-day tasks also remain visible on every covered day.
      for (
        var d = clipped;
        !d.isAfter(day(finish)) && d.isBefore(end);
        d = DateTime(d.year, d.month, d.day + 1)
      ) {
        if (mobileTaskOccursOnDay(task, d)) dates.add(d);
      }
    }
    final sorted = dates.toList()..sort();
    return ListView.builder(
      key: const ValueKey('mobile-calendar-schedule'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      itemCount: sorted.length + 1,
      itemBuilder: (_, index) {
        if (index == sorted.length) {
          return TextButton(
            onPressed: () => setState(() => scheduleDays += 90),
            child: Text(zh ? '查看后续日程' : 'Show later events'),
          );
        }
        final value = sorted[index];
        final entries = onDay(tasks, value);
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  DateFormat.MMMEd(zh ? 'zh_CN' : 'en').format(value),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(zh ? '当天没有日程' : 'No events on this day'),
                ),
              for (final task in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: event(task),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget monthGrid(
    DateTime month,
    List<FlyTask> tasks,
    ValueChanged<DateTime> select, {
    bool compact = false,
  }) {
    final first = DateTime(month.year, month.month);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final today = day(DateTime.now());
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      DateFormat.E(zh ? 'zh_CN' : 'en')
                          .format(start.add(Duration(days: i))),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
          ],
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 42,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: compact ? 44 : 100,
          ),
          itemBuilder: (_, i) {
            final value = DateTime(start.year, start.month, start.day + i);
            final entries = onDay(tasks, value);
            final cell = InkWell(
              key: ValueKey('mobile-calendar-day-${value.toIso8601String()}'),
              onTap: () => select(value),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withValues(alpha: .2),
                  ),
                ),
                padding: const EdgeInsets.all(3),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: value == today
                            ? Theme.of(context).colorScheme.primary
                            : value == date
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${value.day}',
                        style: TextStyle(
                          fontSize: 12,
                          color: value == today
                              ? Theme.of(context).colorScheme.onPrimary
                              : value.month == month.month
                              ? null
                              : Theme.of(context).disabledColor,
                        ),
                      ),
                    ),
                    if (compact && entries.isNotEmpty)
                      const Text('•', style: TextStyle(height: .6)),
                    if (!compact) ...[
                      for (final task in entries.take(2))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: draggableCalendarTask(
                            context,
                            task,
                            value,
                            Container(
                              key: ValueKey(
                                'month-drag-${task.id}-${value.day}',
                              ),
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              child: Text(
                                task.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                            onDragUpdate: _monthAuto.update,
                            onDragEnd: _monthAuto.end,
                          ),
                        ),
                      if (entries.length > 2)
                        Text(
                          '+${entries.length - 2}',
                          style: const TextStyle(fontSize: 10),
                        ),
                    ],
                  ],
                ),
              ),
            );
            return compact
                ? cell
                : CalendarDropTarget(
                    key: ValueKey('month-drop-${value.toIso8601String()}'),
                    target: value,
                    move: (drag, target, time) => moveTask(drag, target, time),
                    child: cell,
                  );
          },
        ),
      ],
    );
  }

  Widget timeline(List<FlyTask> tasks) {
    final count = view == MobileCalendarView.day
        ? 1
        : view == MobileCalendarView.threeDays
        ? 3
        : 7;
    final first = view == MobileCalendarView.week
        ? date.subtract(Duration(days: date.weekday - 1))
        : date;
    final days = List.generate(
      count,
      (i) => DateTime(first.year, first.month, first.day + i),
    );
    return _CalendarTimeGrid(
      key: ValueKey('$view-$date'),
      days: days,
      tasks: tasks,
      move: (drag, target, time) => moveTask(drag, target, time),
      selectDay: (d) {
        focus(d);
        setState(() => view = MobileCalendarView.week);
      },
      create: (d) => create(d, timed: true),
      open: (task) => showTaskDetailSheet(context, task.id),
    );
  }
}

class _CalendarTimeGrid extends StatefulWidget {
  const _CalendarTimeGrid({
    required this.days,
    required this.tasks,
    required this.create,
    required this.open,
    required this.selectDay,
    required this.move,
    super.key,
  });
  final List<DateTime> days;
  final List<FlyTask> tasks;
  final ValueChanged<DateTime> create, selectDay;
  final ValueChanged<FlyTask> open;
  final CalendarMove move;
  @override
  State<_CalendarTimeGrid> createState() => _CalendarTimeGridState();
}

class _CalendarTimeGridState extends State<_CalendarTimeGrid> {
  final scroll = ScrollController(initialScrollOffset: 8 * 60);
  bool allDayExpanded = false;
  final timeBody = GlobalKey();
  final horizontal = ScrollController();
  final verticalViewport = GlobalKey(), horizontalViewport = GlobalKey();
  late final auto = CalendarDragAutoScroller(
    vertical: scroll,
    verticalViewport: verticalViewport,
    horizontal: horizontal,
    horizontalViewport: horizontalViewport,
  );
  @override
  void dispose() {
    auto.dispose();
    horizontal.dispose();
    scroll.dispose();
    super.dispose();
  }

  DateTime start(FlyTask task) => task.startDate ?? task.dueDate!;
  DateTime finish(FlyTask task) =>
      task.dueDate != null && task.dueDate!.isAfter(start(task))
      ? task.dueDate!
      : start(task).add(const Duration(hours: 1));
  DateTime resolveTimeDrop(DragTargetDetails<CalendarTaskDrag> details) {
    final box = timeBody.currentContext!.findRenderObject() as RenderBox;
    final point = box.globalToLocal(
      details.offset + details.data.feedbackAnchor,
    );
    final width = (box.size.width - 44) / widget.days.length;
    final index = ((point.dx - 44) / width).floor().clamp(
      0,
      widget.days.length - 1,
    );
    final minutes = ((point.dy / 15).floor() * 15).clamp(0, 1425);
    final d = widget.days[index];
    return DateTime(d.year, d.month, d.day, minutes ~/ 60, minutes % 60);
  }

  @override
  Widget build(BuildContext context) {
    final zh = context.l10n.isZh;
    final allDay = [
      for (final d in widget.days)
        widget.tasks
            .where((t) => t.isAllDay && mobileTaskOccursOnDay(t, d))
            .toList(),
    ];
    final maxAllDay = allDay.fold(0, (n, list) => math.max(n, list.length));
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(
          100.0,
          (constraints.maxWidth - 44) / widget.days.length,
        );
        return SingleChildScrollView(
          key: horizontalViewport,
          controller: horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width * widget.days.length + 44,
            height: constraints.maxHeight,
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 44),
                    for (final d in widget.days)
                      SizedBox(
                        width: width,
                        child: CalendarDropTarget(
                          target: d,
                          move: widget.move,
                          child: TextButton(
                            onPressed: () => widget.selectDay(d),
                            child: Text(
                              DateFormat.MEd(zh ? 'zh_CN' : 'en').format(d),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (maxAllDay > 0)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.min(
                        constraints.maxHeight * (allDayExpanded ? .45 : .3),
                        allDayExpanded ? 150 : 60,
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 44,
                            child: TextButton(
                              key: const ValueKey('calendar-all-day-toggle'),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(44, 44),
                              ),
                              onPressed: () => setState(
                                () => allDayExpanded = !allDayExpanded,
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    zh ? '全天' : 'All day',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                  Icon(
                                    allDayExpanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          for (var i = 0; i < allDay.length; i++)
                            SizedBox(
                              width: width,
                              child: CalendarDropTarget(
                                target: widget.days[i],
                                move: widget.move,
                                child: Column(
                                  children: [
                                    for (final task
                                        in allDayExpanded
                                            ? allDay[i]
                                            : allDay[i].take(1))
                                      Padding(
                                        padding: const EdgeInsets.all(2),
                                        child: draggableCalendarTask(
                                          context,
                                          task,
                                          widget.days[i],
                                          Material(
                                            key: ValueKey(
                                              'all-day-drag-${task.id}-$i',
                                            ),
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primaryContainer,
                                            child: InkWell(
                                              onTap: () => widget.open(task),
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  6,
                                                ),
                                                child: Text(
                                                  task.title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                          ),
                                          onDragUpdate: auto.update,
                                          onDragEnd: auto.end,
                                        ),
                                      ),
                                    if (!allDayExpanded && allDay[i].length > 1)
                                      TextButton(
                                        key: ValueKey(
                                          'calendar-more-all-day-$i',
                                        ),
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(48, 24),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onPressed: () => setState(
                                          () => allDayExpanded = true,
                                        ),
                                        child: Text('+${allDay[i].length - 1}'),
                                      ),
                                    if (allDay[i].isEmpty)
                                      const SizedBox(
                                        height: 44,
                                        width: double.infinity,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    key: verticalViewport,
                    controller: scroll,
                    child: SizedBox(
                      key: timeBody,
                      height: 24 * 60,
                      child: CalendarDropTarget(
                        target: widget.days.first,
                        time: true,
                        move: widget.move,
                        resolveTarget: resolveTimeDrop,
                        highlight: false,
                        child: Stack(
                          children: [
                            for (var hour = 0; hour < 24; hour++)
                              Positioned(
                                top: hour * 60,
                                left: 0,
                                right: 0,
                                height: 60,
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 44,
                                      child: Align(
                                        alignment: Alignment.topCenter,
                                        child: Text(
                                          '${hour.toString().padLeft(2, '0')}:00',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                      ),
                                    ),
                                    for (final d in widget.days)
                                      SizedBox(
                                        width: width,
                                        child: Column(
                                          children: [
                                            for (
                                              var quarter = 0;
                                              quarter < 4;
                                              quarter++
                                            )
                                              SizedBox(
                                                height: 15,
                                                child: CalendarDropTarget(
                                                  key: ValueKey(
                                                    'week-drop-${d.toIso8601String()}-${hour * 60 + quarter * 15}',
                                                  ),
                                                  target: DateTime(
                                                    d.year,
                                                    d.month,
                                                    d.day,
                                                    hour,
                                                    quarter * 15,
                                                  ),
                                                  time: true,
                                                  resolveTarget:
                                                      resolveTimeDrop,
                                                  move: widget.move,
                                                  child: InkWell(
                                                    onTap: () => widget.create(
                                                      DateTime(
                                                        d.year,
                                                        d.month,
                                                        d.day,
                                                        hour,
                                                        quarter * 15,
                                                      ),
                                                    ),
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        border: Border(
                                                          top: BorderSide(
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .dividerColor
                                                                    .withValues(
                                                                      alpha:
                                                                          quarter ==
                                                                              0
                                                                          ? .35
                                                                          : .08,
                                                                    ),
                                                          ),
                                                          left: BorderSide(
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .dividerColor
                                                                    .withValues(
                                                                      alpha:
                                                                          .15,
                                                                    ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            for (
                              var index = 0;
                              index < widget.days.length;
                              index++
                            )
                              ...positions(context, index, width),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> positions(BuildContext context, int index, double width) {
    final d = widget.days[index];
    final end = DateTime(d.year, d.month, d.day + 1);
    final tasks =
        widget.tasks
            .where((t) => !t.isAllDay && mobileTaskOccursOnDay(t, d))
            .toList()
          ..sort((a, b) => start(a).compareTo(start(b)));
    final lanes = <DateTime>[];
    final assigned = <int>[];
    for (final task in tasks) {
      var lane = lanes.indexWhere(
        (previousEnd) => !previousEnd.isAfter(start(task)),
      );
      if (lane < 0) {
        lane = lanes.length;
        lanes.add(finish(task));
      } else {
        lanes[lane] = finish(task);
      }
      assigned.add(lane);
    }
    final laneWidth = (width - 4) / math.max(1, lanes.length);
    return [
      for (var i = 0; i < tasks.length; i++)
        Builder(
          builder: (_) {
            final task = tasks[i];
            final from = start(task).isBefore(d) ? d : start(task);
            final to = finish(task).isAfter(end) ? end : finish(task);
            final top = from
                .difference(d)
                .inMinutes
                .toDouble()
                .clamp(0.0, 1440.0);
            final height = math
                .max(28.0, to.difference(from).inMinutes.toDouble())
                .clamp(0.0, 1440.0 - top);
            return Positioned(
              top: top,
              left: 46 + index * width + assigned[i] * laneWidth,
              width: laneWidth - 2,
              height: height,
              child: draggableCalendarTask(
                context,
                task,
                from,
                Material(
                  key: ValueKey('week-drag-${task.id}-$index'),
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => widget.open(task),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        task.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
                onDragUpdate: auto.update,
                onDragEnd: auto.end,
              ),
            );
          },
        ),
    ];
  }
}

class _CalendarTaskComposer extends StatefulWidget {
  const _CalendarTaskComposer({required this.initial, required this.allDay});
  final DateTime initial;
  final bool allDay;
  @override
  State<_CalendarTaskComposer> createState() => _CalendarTaskComposerState();
}

class _CalendarTaskComposerState extends State<_CalendarTaskComposer> {
  final title = TextEditingController();
  late DateTime date = widget.initial;
  late bool allDay = widget.allDay;
  int minutes = 60;
  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  void submit() {
    if (title.text.trim().isEmpty) return;
    Navigator.pop(context, (
      title: title.text.trim(),
      start: allDay ? DateTime(date.year, date.month, date.day) : date,
      allDay: allDay,
      minutes: minutes,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final zh = context.l10n.isZh;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('mobile-calendar-title'),
              controller: title,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: zh ? '添加任务' : 'Add task'),
              onSubmitted: (_) => submit(),
            ),
            TextButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2200),
                );
                if (picked != null && mounted) {
                  setState(
                    () => date = DateTime(
                      picked.year,
                      picked.month,
                      picked.day,
                      date.hour,
                      date.minute,
                    ),
                  );
                }
              },
              child: Text(DateFormat.yMMMEd(zh ? 'zh_CN' : 'en').format(date)),
            ),
            SwitchListTile(
              title: Text(zh ? '全天' : 'All day'),
              value: allDay,
              onChanged: (v) => setState(() => allDay = v),
            ),
            if (!allDay)
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(date),
                        );
                        if (picked != null && mounted) {
                          setState(
                            () => date = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              picked.hour,
                              picked.minute,
                            ),
                          );
                        }
                      },
                      child: Text(DateFormat.Hm().format(date)),
                    ),
                  ),
                  Expanded(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: minutes,
                      items: [
                        for (final value in [30, 60, 120])
                          DropdownMenuItem(
                            value: value,
                            child: Text('$value ${zh ? '分钟' : 'min'}'),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => minutes = value);
                      },
                    ),
                  ),
                ],
              ),
            FilledButton(
              key: const ValueKey('mobile-calendar-save'),
              onPressed: submit,
              child: Text(zh ? '保存' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
