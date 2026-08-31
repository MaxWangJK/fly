import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/design_system/design_tokens.dart';
import '../../tasks/domain/task.dart';
import '../../tasks/presentation/task_providers.dart';

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  final _quickAdd = TextEditingController();

  @override
  void dispose() {
    _quickAdd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(calendarMonthProvider);
    final selectedDate = ref.watch(selectedDateProvider);
    final tasks = ref.watch(monthTasksProvider(month));
    final first = DateTime(month.year, month.month);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final days = List.generate(
      42,
      (index) => gridStart.add(Duration(days: index)),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(FlySpacing.lg),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('MMMM y').format(month),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                OutlinedButton(
                  onPressed: () {
                    final now = DateTime.now();
                    ref.read(calendarMonthProvider.notifier).state = DateTime(
                      now.year,
                      now.month,
                    );
                    ref.read(selectedDateProvider.notifier).state = now;
                  },
                  child: const Text('Today'),
                ),
                const SizedBox(width: FlySpacing.xs),
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: () =>
                      ref.read(calendarMonthProvider.notifier).state = DateTime(
                        month.year,
                        month.month - 1,
                      ),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: () =>
                      ref.read(calendarMonthProvider.notifier).state = DateTime(
                        month.year,
                        month.month + 1,
                      ),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: FlySpacing.md),
            TextField(
              controller: _quickAdd,
              onSubmitted: (_) => _createTask(selectedDate),
              decoration: InputDecoration(
                hintText: 'Add to ${DateFormat('MMM d').format(selectedDate)}',
                prefixIcon: const Icon(Icons.add_circle_outline),
                suffixIcon: IconButton(
                  tooltip: 'Create calendar task',
                  onPressed: () => _createTask(selectedDate),
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            ),
            const SizedBox(height: FlySpacing.md),
            const _WeekHeader(),
            const SizedBox(height: FlySpacing.xs),
            Expanded(
              child: tasks.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator.adaptive()),
                error: (error, stack) =>
                    Center(child: Text('Could not load calendar\n$error')),
                data: (items) => LayoutBuilder(
                  builder: (context, constraints) {
                    final ratio =
                        (constraints.maxWidth / 7) /
                        (constraints.maxHeight / 6);
                    return GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        childAspectRatio: ratio,
                        crossAxisSpacing: FlySpacing.xxs,
                        mainAxisSpacing: FlySpacing.xxs,
                      ),
                      itemCount: days.length,
                      itemBuilder: (context, index) {
                        final day = days[index];
                        return _DayCell(
                          day: day,
                          inMonth: day.month == month.month,
                          selected: _sameDay(day, selectedDate),
                          tasks: items
                              .where(
                                (task) =>
                                    task.dueDate != null &&
                                    _sameDay(task.dueDate!, day),
                              )
                              .toList(growable: false),
                          onSelect: () =>
                              ref.read(selectedDateProvider.notifier).state =
                                  day,
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createTask(DateTime day) async {
    final title = _quickAdd.text.trim();
    if (title.isEmpty) return;
    await ref
        .read(taskRepositoryProvider)
        .createTask(
          title: title,
          dueDate: DateTime(day.year, day.month, day.day),
        );
    _quickAdd.clear();
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final label in const [
        'MON',
        'TUE',
        'WED',
        'THU',
        'FRI',
        'SAT',
        'SUN',
      ])
        Expanded(
          child: Center(
            child: Text(label, style: Theme.of(context).textTheme.labelSmall),
          ),
        ),
    ],
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
    return DragTarget<FlyTask>(
      onAcceptWithDetails: (details) {
        ref
            .read(taskRepositoryProvider)
            .moveTaskToDate(
              details.data.id,
              DateTime(day.year, day.month, day.day),
            );
      },
      builder: (context, candidates, rejected) => AnimatedContainer(
        duration: FlyMotion.fast,
        decoration: BoxDecoration(
          color: candidates.isNotEmpty
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(FlyRadius.sm),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(FlyRadius.sm),
          child: Padding(
            padding: const EdgeInsets.all(FlySpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: isToday
                        ? const BoxDecoration(
                            color: FlyColors.accent,
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Text(
                      '${day.day}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: isToday
                            ? Colors.white
                            : inMonth
                            ? null
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: FlySpacing.xxs),
                for (final task in tasks.take(3)) _CalendarTask(task: task),
                if (tasks.length > 3)
                  Text(
                    '+${tasks.length - 3} more',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
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
    final content = Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: task.isCompleted
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : FlyColors.accent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        task.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          decoration: task.isCompleted ? TextDecoration.lineThrough : null,
        ),
      ),
    );
    return LongPressDraggable<FlyTask>(
      data: task,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(FlyRadius.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Padding(
            padding: const EdgeInsets.all(FlySpacing.sm),
            child: Text(task.title),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: content),
      child: GestureDetector(
        onTap: () {
          ref.read(selectedTaskIdProvider.notifier).state = task.id;
          if (MediaQuery.sizeOf(context).width < FlyBreakpoints.expanded) {
            context.push('/task/${task.id}');
          }
        },
        child: content,
      ),
    );
  }
}

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
