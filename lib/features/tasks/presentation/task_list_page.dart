import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/design_system/design_tokens.dart';
import '../domain/task.dart';
import 'task_providers.dart';

enum TaskCollection { today, inbox, upcoming, custom }

class TaskListPage extends ConsumerStatefulWidget {
  const TaskListPage({
    required this.title,
    required this.collection,
    this.listId,
    super.key,
  });

  final String title;
  final TaskCollection collection;
  final String? listId;

  @override
  ConsumerState<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends ConsumerState<TaskListPage> {
  final _quickAddController = TextEditingController();

  @override
  void dispose() {
    _quickAddController.dispose();
    super.dispose();
  }

  AsyncValue<List<FlyTask>> _tasks() => switch (widget.collection) {
    TaskCollection.today => ref.watch(todayTasksProvider),
    TaskCollection.inbox => ref.watch(inboxTasksProvider),
    TaskCollection.upcoming => ref.watch(upcomingTasksProvider),
    TaskCollection.custom => ref.watch(
      listTasksProvider(widget.listId ?? 'inbox'),
    ),
  };

  Future<void> _addTask() async {
    final title = _quickAddController.text.trim();
    if (title.isEmpty) return;
    final now = DateTime.now();
    final dueDate = switch (widget.collection) {
      TaskCollection.today => DateTime(now.year, now.month, now.day),
      _ => null,
    };
    await ref
        .read(taskRepositoryProvider)
        .createTask(
          title: title,
          listId: widget.listId ?? 'inbox',
          dueDate: dueDate,
        );
    _quickAddController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks();
    final customName = widget.collection == TaskCollection.custom
        ? ref
              .watch(taskListsProvider)
              .valueOrNull
              ?.where((list) => list.id == widget.listId)
              .firstOrNull
              ?.name
        : null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          FlySpacing.lg,
          FlySpacing.lg,
          FlySpacing.lg,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ListHeader(title: customName ?? widget.title, tasks: tasks),
            const SizedBox(height: FlySpacing.lg),
            _QuickAdd(controller: _quickAddController, onSubmitted: _addTask),
            const SizedBox(height: FlySpacing.md),
            Expanded(
              child: tasks.when(
                data: (items) => items.isEmpty
                    ? const _EmptyTasks()
                    : _TaskRows(tasks: items),
                loading: () =>
                    const Center(child: CircularProgressIndicator.adaptive()),
                error: (error, stack) => _ErrorState(error: error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.title, required this.tasks});

  final String title;
  final AsyncValue<List<FlyTask>> tasks;

  @override
  Widget build(BuildContext context) {
    final count = tasks.valueOrNull?.where((task) => !task.isCompleted).length;
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
        ),
        if (count != null)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: FlySpacing.sm,
              vertical: FlySpacing.xs,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(FlyRadius.lg),
            ),
            child: Text(
              '$count open',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
      ],
    );
  }
}

class _QuickAdd extends StatelessWidget {
  const _QuickAdd({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onSubmitted: (_) => onSubmitted(),
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        hintText: 'Add a task and press Enter',
        prefixIcon: const Icon(Icons.add_circle_outline),
        suffixIcon: IconButton(
          tooltip: 'Create task',
          onPressed: onSubmitted,
          icon: const Icon(Icons.arrow_forward),
        ),
      ),
    );
  }
}

class _TaskRows extends ConsumerWidget {
  const _TaskRows({required this.tasks});

  final List<FlyTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: tasks.length,
      proxyDecorator: (child, index, animation) => Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(FlyRadius.md),
        child: child,
      ),
      onReorderItem: (oldIndex, newIndex) async {
        final reordered = [...tasks];
        final moved = reordered.removeAt(oldIndex);
        reordered.insert(newIndex, moved);
        await ref
            .read(taskRepositoryProvider)
            .reorderTask(
              moved.id,
              reordered.map((task) => task.id).toList(growable: false),
            );
      },
      itemBuilder: (context, index) {
        final task = tasks[index];
        return Padding(
          key: ValueKey(task.id),
          padding: const EdgeInsets.only(bottom: FlySpacing.xs),
          child: _TaskRow(task: task, index: index),
        );
      },
    );
  }
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.task, required this.index});

  final FlyTask task;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedTaskIdProvider) == task.id;
    final date = task.dueDate;
    final overdue =
        date != null &&
        !task.isCompleted &&
        date.isBefore(
          DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day,
          ),
        );
    return Card(
      color: selected
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(FlyRadius.md),
        onTap: () {
          ref.read(selectedTaskIdProvider.notifier).state = task.id;
          if (MediaQuery.sizeOf(context).width < FlyBreakpoints.expanded) {
            context.push('/task/${task.id}');
          }
        },
        child: SizedBox(
          height: FlyMetrics.taskRowHeight,
          child: Row(
            children: [
              const SizedBox(width: FlySpacing.sm),
              Checkbox(
                value: task.isCompleted,
                onChanged: (value) => ref
                    .read(taskRepositoryProvider)
                    .setCompleted(task.id, completed: value ?? false),
              ),
              const SizedBox(width: FlySpacing.xs),
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    decoration: task.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                    color: task.isCompleted
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : null,
                  ),
                ),
              ),
              if (task.priority != TaskPriority.none)
                Icon(
                  Icons.flag,
                  size: 17,
                  color: task.priority == TaskPriority.high
                      ? FlyColors.danger
                      : FlyColors.warning,
                ),
              if (date != null) ...[
                const SizedBox(width: FlySpacing.sm),
                Text(
                  DateFormat('MMM d').format(date),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: overdue ? FlyColors.danger : null),
                ),
              ],
              const SizedBox(width: FlySpacing.sm),
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(FlySpacing.sm),
                  child: Icon(Icons.drag_indicator, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyTasks extends StatelessWidget {
  const _EmptyTasks();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: FlySpacing.md),
            Text('Clear runway', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: FlySpacing.xs),
            Text(
              'Add a task above. It will stay on this device and appear across every Fly view.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Center(
    child: Text('Could not load tasks\n$error', textAlign: TextAlign.center),
  );
}
