import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/fly_localizations.dart';
import '../../../shared/design_system/design_tokens.dart';
import '../../../shared/formatters/relative_date_formatter.dart';
import '../../tasks/domain/task.dart';
import '../../tasks/presentation/task_providers.dart';
import '../../tasks/presentation/task_delete_action.dart';
import '../../tasks/presentation/widgets/task_components.dart';

class MatrixPage extends ConsumerWidget {
  const MatrixPage({super.key});

  static const quadrants = [
    _Quadrant(
      value: MatrixQuadrant.importantUrgent,
      titleKey: 'q1',
      hintKey: 'q1Hint',
      color: FlyColors.importantUrgent,
      importance: true,
      urgency: true,
    ),
    _Quadrant(
      value: MatrixQuadrant.importantNotUrgent,
      titleKey: 'q2',
      hintKey: 'q2Hint',
      color: FlyColors.importantCalm,
      importance: true,
      urgency: false,
    ),
    _Quadrant(
      value: MatrixQuadrant.notImportantUrgent,
      titleKey: 'q3',
      hintKey: 'q3Hint',
      color: FlyColors.urgentLight,
      importance: false,
      urgency: true,
    ),
    _Quadrant(
      value: MatrixQuadrant.notImportantNotUrgent,
      titleKey: 'q4',
      hintKey: 'q4Hint',
      color: FlyColors.someday,
      importance: false,
      urgency: false,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(allTasksProvider);
    return SafeArea(
      child: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            FlySpacing.lg,
            FlySpacing.md,
            FlySpacing.lg,
            FlySpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  children: [
                    Text(
                      context.l10n.t('matrix'),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(width: FlySpacing.md),
                    Expanded(
                      child: Text(
                        context.l10n.t('matrixHint'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: tasks.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator.adaptive()),
                  error: (error, stack) => Center(
                    child: Text(
                      context.l10n.error(context.l10n.t('matrix'), error),
                    ),
                  ),
                  data: (items) => LayoutBuilder(
                    builder: (context, constraints) {
                      final cards = [
                        for (final quadrant in quadrants)
                          _QuadrantCard(
                            quadrant: quadrant,
                            tasks: items
                                .where(
                                  (task) => task.quadrant == quadrant.value,
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
                              SizedBox(height: 250, child: cards[index]),
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
      ),
    );
  }
}

class _QuadrantCard extends ConsumerStatefulWidget {
  const _QuadrantCard({required this.quadrant, required this.tasks});

  final _Quadrant quadrant;
  final List<FlyTask> tasks;

  @override
  ConsumerState<_QuadrantCard> createState() => _QuadrantCardState();
}

class _QuadrantCardState extends ConsumerState<_QuadrantCard> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  bool _adding = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _beginAdd() {
    setState(() => _adding = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  void _cancel() {
    _controller.clear();
    setState(() => _adding = false);
  }

  Future<void> _create() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    await ref
        .read(taskRepositoryProvider)
        .createTask(
          title: title,
          importance: widget.quadrant.importance,
          urgency: widget.quadrant.urgency,
        );
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final quadrant = widget.quadrant;
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
              ? quadrant.color.withValues(alpha: 0.08)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(FlyRadius.md),
          border: Border.all(
            color: candidates.isNotEmpty
                ? quadrant.color
                : Theme.of(context).dividerColor,
            width: candidates.isNotEmpty ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(height: 3, color: quadrant.color),
            SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.only(
                  left: FlySpacing.sm,
                  right: FlySpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.t(quadrant.titleKey),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: quadrant.color),
                          ),
                          Text(
                            context.l10n.t(quadrant.hintKey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${widget.tasks.length}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    IconButton(
                      tooltip: context.l10n.addTo(
                        context.l10n.t(quadrant.titleKey),
                      ),
                      onPressed: _adding ? _cancel : _beginAdd,
                      icon: Icon(_adding ? Icons.close : Icons.add, size: 19),
                    ),
                  ],
                ),
              ),
            ),
            if (_adding)
              Focus(
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    _cancel();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FlySpacing.sm,
                    0,
                    FlySpacing.sm,
                    FlySpacing.xs,
                  ),
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      onSubmitted: (_) => _create(),
                      decoration: InputDecoration(
                        hintText: context.l10n.t('inputTask'),
                        prefixIcon: const Icon(Icons.add, size: 16),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 30,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: widget.tasks.isEmpty
                  ? Center(
                      child: Text(
                        context.l10n.t(quadrant.hintKey),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(
                          FlySpacing.sm,
                          0,
                          FlySpacing.sm,
                          FlySpacing.sm,
                        ),
                        itemCount: widget.tasks.length,
                        itemBuilder: (context, index) => _MatrixTask(
                          task: widget.tasks[index],
                          color: quadrant.color,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatrixTask extends ConsumerWidget {
  const _MatrixTask({required this.task, required this.color});

  final FlyTask task;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedTaskIdProvider) == task.id;
    final row = FlyTaskRowSurface(
      task: task,
      compact: true,
      selected: selected,
      accent: color,
      onTap: () {
        ref.read(selectedTaskIdProvider.notifier).state = task.id;
        if (MediaQuery.sizeOf(context).width < FlyBreakpoints.expanded) {
          context.push('/task/${task.id}');
        }
      },
      onSecondaryTapDown: (details) =>
          showTaskDeleteContextMenu(context, ref, task, details.globalPosition),
      onCompleted: (value) => ref
          .read(taskRepositoryProvider)
          .setCompleted(task.id, completed: value),
      metadata: RelativeDateFormatter.createdAt(
        task.createdAt,
        isZh: context.l10n.isZh,
      ),
      trailing: const SizedBox(
        width: 22,
        child: Icon(Icons.drag_indicator, size: 14),
      ),
    );
    return Draggable<FlyTask>(
      data: task,
      feedback: FlyTaskDragFeedback(task: task),
      childWhenDragging: Opacity(opacity: 0.30, child: row),
      child: row,
    );
  }
}

class _Quadrant {
  const _Quadrant({
    required this.value,
    required this.titleKey,
    required this.hintKey,
    required this.color,
    required this.importance,
    required this.urgency,
  });

  final MatrixQuadrant value;
  final String titleKey;
  final String hintKey;
  final Color color;
  final bool importance;
  final bool urgency;
}
