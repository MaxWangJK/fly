import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/fly_localizations.dart';
import '../../../shared/design_system/design_tokens.dart';
import '../../../shared/design_system/fly_color_scheme.dart';
import '../../tasks/domain/task.dart';
import '../../tasks/domain/task_date_range.dart';
import '../../tasks/presentation/task_providers.dart';
import '../../tasks/presentation/task_delete_action.dart';
import '../../tasks/presentation/widgets/task_components.dart';

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  bool _week = false;
  static const _capturePopup = bool.fromEnvironment(
    'FLY_CAPTURE_CALENDAR_POPUP',
  );

  @override
  void initState() {
    super.initState();
    if (_capturePopup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openQuickAdd(DateTime.now());
      });
    }
  }

  Future<void> _openQuickAdd(DateTime day) async {
    final normalized = DateTime(day.year, day.month, day.day);
    ref.read(selectedTaskIdProvider.notifier).state = null;
    ref.read(selectedDateProvider.notifier).state = normalized;
    final title = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.16),
      builder: (dialogContext) => _CalendarQuickAddDialog(day: normalized),
    );
    if (!mounted || title == null || title.trim().isEmpty) return;
    final task = await ref
        .read(taskRepositoryProvider)
        .createTask(title: title.trim(), dueDate: normalized);
    ref.read(selectedTaskIdProvider.notifier).state = task.id;
  }

  void _changeMonth(DateTime value) {
    ref.read(calendarMonthProvider.notifier).state = value;
    ref.read(selectedDateProvider.notifier).state = null;
    ref.read(selectedTaskIdProvider.notifier).state = null;
  }

  void _goToToday() {
    final now = DateTime.now();
    _changeMonth(
      _week
          ? DateTime(now.year, now.month, now.day)
          : DateTime(now.year, now.month),
    );
  }

  Future<void> _handleMore(String action, DateTime month) async {
    if (action == 'today') {
      _goToToday();
      return;
    }
    if (action != 'jumpToDate') return;
    final initial = ref.read(selectedDateProvider) ?? month;
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(month.year - 10),
      lastDate: DateTime(month.year + 10, 12, 31),
      initialDate: initial,
    );
    if (picked == null || !mounted) return;
    ref.read(calendarMonthProvider.notifier).state = DateTime(
      picked.year,
      picked.month,
    );
    await _openQuickAdd(picked);
  }

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(calendarMonthProvider);
    final selectedDate = ref.watch(selectedDateProvider);
    final tasks = ref.watch(allTasksProvider);
    final today = ref.watch(localTodayProvider);
    final first = _week ? month : DateTime(month.year, month.month);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final days = List.generate(
      _week ? 7 : 42,
      (index) => gridStart.add(Duration(days: index)),
    );

    return Listener(
      key: const ValueKey('calendar-scroll-surface'),
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
        final direction = event.scrollDelta.dy > 0 ? 1 : -1;
        _changeMonth(
          _week
              ? month.add(Duration(days: 7 * direction))
              : DateTime(month.year, month.month + direction),
        );
      },
      child: SafeArea(
        child: Material(
          color: context.flyColors.canvas,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              FlySpacing.lg,
              FlySpacing.md,
              FlySpacing.lg,
              FlySpacing.lg,
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 42,
                  child: Row(
                    children: [
                      Text(
                        context.l10n.t('calendar'),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(width: FlySpacing.md),
                      Text(
                        context.l10n.monthLabel(month),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: context.l10n.t('addTask'),
                        onPressed: () {
                          final now = DateTime.now();
                          final selectedInMonth =
                              selectedDate != null &&
                              selectedDate.year == month.year &&
                              selectedDate.month == month.month;
                          final visibleToday =
                              now.year == month.year &&
                              now.month == month.month;
                          _openQuickAdd(
                            selectedInMonth
                                ? selectedDate
                                : visibleToday
                                ? now
                                : DateTime(month.year, month.month),
                          );
                        },
                        icon: const Icon(Icons.add, size: 20),
                      ),
                      PopupMenuButton<String>(
                        tooltip: context.l10n.t('viewMode'),
                        onSelected: (value) => setState(() {
                          _week = value == 'week';
                          if (_week) _changeMonth(selectedDate ?? today);
                        }),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'month',
                            child: Row(
                              children: [
                                Icon(
                                  _week
                                      ? Icons.calendar_month_outlined
                                      : Icons.check,
                                  size: 17,
                                ),
                                const SizedBox(width: FlySpacing.xs),
                                Text(context.l10n.t('monthView')),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'week',
                            child: Text(
                              context.l10n.isZh ? '周视图' : 'Week view',
                            ),
                          ),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: FlySpacing.sm,
                            vertical: FlySpacing.xs,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _week
                                    ? (context.l10n.isZh ? '周' : 'Week')
                                    : context.l10n.t('month'),
                              ),
                              const Icon(Icons.arrow_drop_down, size: 18),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: _week
                            ? (context.l10n.isZh ? '上一周' : 'Previous week')
                            : context.l10n.t('previousMonth'),
                        onPressed: () => _changeMonth(
                          _week
                              ? DateTime(month.year, month.month, month.day - 7)
                              : DateTime(month.year, month.month - 1),
                        ),
                        icon: const Icon(Icons.chevron_left, size: 20),
                      ),
                      TextButton(
                        onPressed: _goToToday,
                        child: Text(context.l10n.t('today')),
                      ),
                      IconButton(
                        tooltip: _week
                            ? (context.l10n.isZh ? '下一周' : 'Next week')
                            : context.l10n.t('nextMonth'),
                        onPressed: () => _changeMonth(
                          _week
                              ? DateTime(month.year, month.month, month.day + 7)
                              : DateTime(month.year, month.month + 1),
                        ),
                        icon: const Icon(Icons.chevron_right, size: 20),
                      ),
                      PopupMenuButton<String>(
                        tooltip: context.l10n.t('more'),
                        onSelected: (action) => _handleMore(action, month),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'today',
                            child: Text(context.l10n.t('today')),
                          ),
                          PopupMenuItem(
                            value: 'jumpToDate',
                            child: Text(context.l10n.t('jumpToDate')),
                          ),
                        ],
                        icon: const Icon(Icons.more_horiz, size: 20),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: FlySpacing.xs),
                _WeekHeader(
                  labels: [
                    ...context.l10n.weekdays.skip(1),
                    context.l10n.weekdays.first,
                  ],
                ),
                Expanded(
                  child: tasks.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                    error: (error, stack) => Center(
                      child: Text(
                        context.l10n.error(context.l10n.t('calendar'), error),
                      ),
                    ),
                    data: (items) => LayoutBuilder(
                      builder: (context, constraints) {
                        final ratio =
                            (constraints.maxWidth / 7) /
                            (constraints.maxHeight / (_week ? 1 : 6));
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: Theme.of(context).dividerColor,
                              ),
                              left: BorderSide(
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                          ),
                          child: AnimatedSwitcher(
                            duration: FlyMotion.standard,
                            child: GridView.builder(
                              key: ValueKey('$gridStart-$_week'),
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 7,
                                    childAspectRatio: ratio,
                                  ),
                              itemCount: days.length,
                              itemBuilder: (context, index) {
                                final day = days[index];
                                final dayTasks = items
                                    .where(
                                      (task) =>
                                          TaskDateRange.calendarDate(
                                            task,
                                            today,
                                          ) ==
                                          TaskDateRange.day(day),
                                    )
                                    .toList(growable: false);
                                return _DayCell(
                                  day: day,
                                  inMonth: day.month == month.month,
                                  selected:
                                      selectedDate != null &&
                                      _sameDay(day, selectedDate),
                                  tasks: dayTasks,
                                  onSelect: () => _openQuickAdd(day),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 26,
    child: Row(
      children: [
        for (final label in labels)
          Expanded(
            child: Center(
              child: Text(label, style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
      ],
    ),
  );
}

class _DayCell extends ConsumerWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.selected,
    required this.tasks,
    required this.onSelect,
  });

  final DateTime day;
  final bool inMonth;
  final bool selected;
  final List<FlyTask> tasks;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isToday = _sameDay(day, DateTime.now());
    final colors = context.flyColors;
    final base = inMonth
        ? (day.weekday >= 6 ? colors.surfaceMuted : colors.surface)
        : colors.canvas;

    return DragTarget<FlyTask>(
      onAcceptWithDetails: (details) => ref
          .read(taskRepositoryProvider)
          .moveTaskToDate(
            details.data.id,
            DateTime(day.year, day.month, day.day),
          ),
      builder: (context, candidates, rejected) => AnimatedContainer(
        duration: FlyMotion.fast,
        decoration: BoxDecoration(
          color: candidates.isNotEmpty
              ? colors.hover
              : selected
              ? colors.selected
              : base,
          border: Border(
            right: BorderSide(color: Theme.of(context).dividerColor),
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('calendar-day-${day.year}-${day.month}-${day.day}'),
            onTap: onSelect,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(5, 3, 5, 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 23,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 23,
                        height: 23,
                        alignment: Alignment.center,
                        decoration: isToday
                            ? BoxDecoration(
                                color: colors.accent,
                                shape: BoxShape.circle,
                              )
                            : null,
                        child: Text(
                          '${day.day}',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: isToday
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : inMonth
                                    ? null
                                    : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                              ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ScrollConfiguration(
                      behavior: const MaterialScrollBehavior().copyWith(
                        dragDevices: {
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.touch,
                          PointerDeviceKind.stylus,
                        },
                      ),
                      child: ListView(
                        padding: const EdgeInsets.only(top: 2),
                        primary: false,
                        physics: const ClampingScrollPhysics(),
                        children: [
                          for (final task in tasks) _CalendarTask(task: task),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarTask extends ConsumerWidget {
  const _CalendarTask({required this.task});

  final FlyTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedTaskIdProvider) == task.id;
    final colors = context.flyColors;
    final color = task.isCompleted
        ? colors.textSecondary
        : switch (task.priority) {
            TaskPriority.high => colors.danger,
            TaskPriority.medium => colors.warning,
            _ => colors.accent,
          };
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: color.withValues(alpha: selected ? 0.20 : 0.11),
        borderRadius: BorderRadius.circular(FlyRadius.xs),
        child: InkWell(
          onSecondaryTapDown: (details) => showTaskDeleteContextMenu(
            context,
            ref,
            task,
            details.globalPosition,
          ),
          onTap: () {
            ref.read(selectedTaskIdProvider.notifier).state = task.id;
            if (MediaQuery.sizeOf(context).width < FlyBreakpoints.expanded) {
              context.push('/task/${task.id}');
            }
          },
          borderRadius: BorderRadius.circular(FlyRadius.xs),
          child: SizedBox(
            height: 22,
            child: Row(
              children: [
                const SizedBox(width: 4),
                InkResponse(
                  onTap: () => ref
                      .read(taskRepositoryProvider)
                      .setCompleted(task.id, completed: !task.isCompleted),
                  radius: 12,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: task.isCompleted ? color : Colors.transparent,
                      border: Border.all(color: color),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: task.isCompleted
                        ? const Icon(Icons.check, size: 10, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                      decoration: task.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
    return LongPressDraggable<FlyTask>(
      data: task,
      feedback: FlyTaskDragFeedback(task: task),
      childWhenDragging: Opacity(opacity: 0.30, child: row),
      child: row,
    );
  }
}

class _CalendarQuickAddDialog extends StatefulWidget {
  const _CalendarQuickAddDialog({required this.day});

  final DateTime day;

  @override
  State<_CalendarQuickAddDialog> createState() =>
      _CalendarQuickAddDialogState();
}

class _CalendarQuickAddDialogState extends State<_CalendarQuickAddDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Dialog(
      key: const ValueKey('calendar-quick-add-dialog'),
      alignment: Alignment.center,
      insetPadding: const EdgeInsets.all(FlySpacing.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FlyRadius.lg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 410, minHeight: 230),
        child: Padding(
          padding: const EdgeInsets.all(FlySpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_month_outlined, size: 18),
                  const SizedBox(width: FlySpacing.xs),
                  Text(
                    context.l10n.fullDate(widget.day),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: context.l10n.t('close'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: FlySpacing.md),
              TextField(
                controller: _controller,
                autofocus: true,
                style: Theme.of(context).textTheme.titleMedium,
                decoration: InputDecoration(
                  hintText: context.l10n.t('calendarAdd'),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 76),
              const Divider(height: 1),
              const SizedBox(height: FlySpacing.sm),
              Row(
                children: [
                  const Icon(Icons.inbox_outlined, size: 17),
                  const SizedBox(width: 6),
                  Text(
                    context.l10n.t('inbox'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Text(
                    context.l10n.t('pressEnterToCreate'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
