import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/design_system/design_tokens.dart';
import '../../tasks/domain/task.dart';
import '../../tasks/presentation/task_providers.dart';

class MatrixPage extends ConsumerWidget {
  const MatrixPage({super.key});

  static const quadrants = [
    _Quadrant(
      value: MatrixQuadrant.importantUrgent,
      title: 'Do first',
      subtitle: 'Important · Urgent',
      hint: 'Resolve critical work',
      color: FlyColors.importantUrgent,
      importance: true,
      urgency: true,
    ),
    _Quadrant(
      value: MatrixQuadrant.importantNotUrgent,
      title: 'Schedule',
      subtitle: 'Important · Not urgent',
      hint: 'Protect time for progress',
      color: FlyColors.importantCalm,
      importance: true,
      urgency: false,
    ),
    _Quadrant(
      value: MatrixQuadrant.notImportantUrgent,
      title: 'Delegate',
      subtitle: 'Not important · Urgent',
      hint: 'Reduce reactive load',
      color: FlyColors.urgentLight,
      importance: false,
      urgency: true,
    ),
    _Quadrant(
      value: MatrixQuadrant.notImportantNotUrgent,
      title: 'Reconsider',
      subtitle: 'Not important · Not urgent',
      hint: 'Keep the backlog intentional',
      color: FlyColors.someday,
      importance: false,
      urgency: false,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(allTasksProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(FlySpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Eisenhower Matrix',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: FlySpacing.xs),
            Text(
              'Drag a task between quadrants. Importance and urgency are saved immediately.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: FlySpacing.lg),
            Expanded(
              child: tasks.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator.adaptive()),
                error: (error, stack) =>
                    Center(child: Text('Could not load matrix\n$error')),
                data: (items) => LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = [
                      for (final quadrant in quadrants)
                        _QuadrantCard(
                          quadrant: quadrant,
                          tasks: items
                              .where(
                                (task) =>
                                    !task.isCompleted &&
                                    task.quadrant == quadrant.value,
                              )
                              .toList(growable: false),
                        ),
                    ];
                    if (constraints.maxWidth < 700) {
                      return ListView.separated(
                        itemCount: cards.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: FlySpacing.sm),
                        itemBuilder: (context, index) =>
                            SizedBox(height: 260, child: cards[index]),
                      );
                    }
                    return GridView.count(
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      crossAxisSpacing: FlySpacing.sm,
                      mainAxisSpacing: FlySpacing.sm,
                      childAspectRatio:
                          (constraints.maxWidth / 2) /
                          (constraints.maxHeight / 2),
                      children: cards,
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
}

class _QuadrantCard extends ConsumerWidget {
  const _QuadrantCard({required this.quadrant, required this.tasks});

  final _Quadrant quadrant;
  final List<FlyTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DragTarget<FlyTask>(
      onAcceptWithDetails: (details) => ref
          .read(taskRepositoryProvider)
          .moveTaskToQuadrant(
            details.data.id,
            importance: quadrant.importance,
            urgency: quadrant.urgency,
          ),
      builder: (context, candidates, rejected) => AnimatedContainer(
        duration: FlyMotion.fast,
        decoration: BoxDecoration(
          color: candidates.isNotEmpty
              ? quadrant.color.withValues(alpha: 0.10)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(FlyRadius.lg),
          border: Border.all(
            color: candidates.isNotEmpty
                ? quadrant.color
                : Theme.of(context).dividerColor,
            width: candidates.isNotEmpty ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: quadrant.color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(FlyRadius.lg),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FlySpacing.md,
                FlySpacing.sm,
                FlySpacing.xs,
                FlySpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          quadrant.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          quadrant.subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: quadrant.color,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FlySpacing.xs,
                      vertical: FlySpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: quadrant.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(FlyRadius.lg),
                    ),
                    child: Text('${tasks.length}'),
                  ),
                  IconButton(
                    tooltip: 'Add to ${quadrant.title}',
                    onPressed: () => _showAddDialog(context, ref),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
            Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Text(
                        quadrant.hint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        FlySpacing.sm,
                        0,
                        FlySpacing.sm,
                        FlySpacing.sm,
                      ),
                      itemCount: tasks.length,
                      itemBuilder: (context, index) => _MatrixTask(
                        task: tasks[index],
                        color: quadrant.color,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add to ${quadrant.title}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Task title'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Add task'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.trim().isEmpty) return;
    await ref
        .read(taskRepositoryProvider)
        .createTask(
          title: title,
          importance: quadrant.importance,
          urgency: quadrant.urgency,
        );
  }
}

class _MatrixTask extends ConsumerWidget {
  const _MatrixTask({required this.task, required this.color});

  final FlyTask task;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = Container(
      margin: const EdgeInsets.only(bottom: FlySpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: FlySpacing.sm,
        vertical: FlySpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(FlyRadius.sm),
      ),
      child: Row(
        children: [
          Icon(Icons.drag_indicator, size: 16, color: color),
          const SizedBox(width: FlySpacing.xs),
          Expanded(
            child: Text(
              task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Checkbox(
            visualDensity: VisualDensity.compact,
            value: false,
            onChanged: (value) => ref
                .read(taskRepositoryProvider)
                .setCompleted(task.id, completed: value ?? false),
          ),
        ],
      ),
    );
    return LongPressDraggable<FlyTask>(
      data: task,
      feedback: Material(
        elevation: 5,
        borderRadius: BorderRadius.circular(FlyRadius.sm),
        child: SizedBox(
          width: 240,
          child: Padding(
            padding: const EdgeInsets.all(FlySpacing.sm),
            child: Text(task.title),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.30, child: card),
      child: GestureDetector(
        onTap: () {
          ref.read(selectedTaskIdProvider.notifier).state = task.id;
          if (MediaQuery.sizeOf(context).width < FlyBreakpoints.expanded) {
            context.push('/task/${task.id}');
          }
        },
        child: card,
      ),
    );
  }
}

class _Quadrant {
  const _Quadrant({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.hint,
    required this.color,
    required this.importance,
    required this.urgency,
  });

  final MatrixQuadrant value;
  final String title;
  final String subtitle;
  final String hint;
  final Color color;
  final bool importance;
  final bool urgency;
}
