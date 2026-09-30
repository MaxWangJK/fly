import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/fly_localizations.dart';
import '../../../shared/design_system/design_tokens.dart';
import '../../../shared/design_system/workspace_empty_state.dart';
import '../../../shared/search/fuzzy_match.dart';
import '../domain/task.dart';
import '../domain/task_date_range.dart';
import '../domain/task_list.dart';
import 'task_providers.dart';
import 'task_delete_action.dart';
import 'widgets/task_components.dart';

enum TaskCollection { today, inbox, upcoming, custom, completed, trash }

class TaskListPage extends ConsumerStatefulWidget {
  const TaskListPage({required this.collection, this.listId, super.key});

  final TaskCollection collection;
  final String? listId;

  @override
  ConsumerState<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends ConsumerState<TaskListPage> {
  final _quickAddController = TextEditingController();
  final _searchController = TextEditingController();
  final _quickAddFocus = FocusNode();
  final _listFocus = FocusNode();
  final _scrollController = ScrollController();
  String _search = '';

  @override
  void dispose() {
    _quickAddController.dispose();
    _searchController.dispose();
    _quickAddFocus.dispose();
    _listFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  AsyncValue<List<FlyTask>> _tasks() => switch (widget.collection) {
    TaskCollection.today => ref.watch(todayWorkspaceTasksProvider),
    TaskCollection.inbox => ref.watch(inboxTasksProvider),
    TaskCollection.upcoming => ref.watch(upcomingTasksProvider),
    TaskCollection.custom => ref.watch(
      listTasksProvider(widget.listId ?? 'inbox'),
    ),
    TaskCollection.completed => ref.watch(completedTasksProvider),
    TaskCollection.trash => ref.watch(deletedTasksProvider),
  };

  bool get _canAdd =>
      widget.collection != TaskCollection.completed &&
      widget.collection != TaskCollection.trash;

  String _title(BuildContext context, List<FlyTaskList> lists) =>
      switch (widget.collection) {
        TaskCollection.today => context.l10n.t('today'),
        TaskCollection.inbox => context.l10n.t('inbox'),
        TaskCollection.upcoming => context.l10n.t('next7'),
        TaskCollection.completed => context.l10n.t('completed'),
        TaskCollection.trash => context.l10n.t('trash'),
        TaskCollection.custom =>
          lists.where((list) => list.id == widget.listId).firstOrNull?.name ??
              context.l10n.t('list'),
      };

  Future<void> _addTask() async {
    final title = _quickAddController.text.trim();
    if (title.isEmpty) return;
    final now = DateTime.now();
    final dueDate = switch (widget.collection) {
      TaskCollection.today => DateTime(now.year, now.month, now.day),
      TaskCollection.upcoming => DateTime(now.year, now.month, now.day),
      _ => null,
    };
    final task = await ref
        .read(taskRepositoryProvider)
        .createTask(
          title: title,
          listId: widget.listId ?? 'inbox',
          dueDate: dueDate,
        );
    _quickAddController.clear();
    ref.read(selectedTaskIdProvider.notifier).state = task.id;
    _quickAddFocus.requestFocus();
  }

  void _beginAdd() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _quickAddFocus.requestFocus(),
    );
  }

  void _cancelAdd() {
    _quickAddController.clear();
    _quickAddFocus.unfocus();
  }

  KeyEventResult _handleKeys(KeyEvent event, List<FlyTask> tasks) {
    if (event is! KeyDownEvent || _quickAddFocus.hasFocus) {
      return KeyEventResult.ignored;
    }
    final selectedId = ref.read(selectedTaskIdProvider);
    final index = tasks.indexWhere((task) => task.id == selectedId);

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (tasks.isNotEmpty) {
        final next = index < 0 ? 0 : (index + 1).clamp(0, tasks.length - 1);
        ref.read(selectedTaskIdProvider.notifier).state = tasks[next].id;
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (tasks.isNotEmpty) {
        final next = index < 0 ? 0 : (index - 1).clamp(0, tasks.length - 1);
        ref.read(selectedTaskIdProvider.notifier).state = tasks[next].id;
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete &&
        index >= 0 &&
        widget.collection != TaskCollection.trash) {
      ref.read(taskRepositoryProvider).deleteTask(tasks[index].id);
      ref.read(selectedTaskIdProvider.notifier).state = null;
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && _canAdd) {
      _beginAdd();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      ref.read(selectedTaskIdProvider.notifier).state = null;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks();
    final visibleTasks = _search.trim().isEmpty
        ? tasks
        : tasks.whenData(
            (items) => items
                .where(
                  (task) => FuzzyMatch.matches(_search, [
                    task.title,
                    task.description,
                  ]),
                )
                .toList(),
          );
    final lists = ref.watch(taskListsProvider).valueOrNull ?? const [];
    final items = visibleTasks.valueOrNull ?? const <FlyTask>[];
    final title = _title(context, lists);

    return SafeArea(
      child: Focus(
        focusNode: _listFocus,
        autofocus: true,
        onKeyEvent: (_, event) => _handleKeys(event, items),
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surface,
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
                _ListHeader(
                  title: title,
                  tasks: visibleTasks,
                  collection: widget.collection,
                ),
                const SizedBox(height: FlySpacing.md),
                if (_canAdd) ...[
                  Focus(
                    onKeyEvent: (_, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.escape) {
                        _cancelAdd();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      key: const ValueKey('quick-add-input'),
                      controller: _quickAddController,
                      focusNode: _quickAddFocus,
                      onSubmitted: (_) => _addTask(),
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: context.l10n.t('inputTask'),
                        prefixIcon: const Icon(Icons.add, size: 19),
                      ),
                    ),
                  ),
                  const SizedBox(height: FlySpacing.xs),
                ],
                SizedBox(
                  height: 36,
                  child: TextField(
                    key: const ValueKey('task-search'),
                    controller: _searchController,
                    onChanged: (value) => setState(() => _search = value),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: context.l10n.isZh ? '搜索任务' : 'Search tasks',
                      prefixIcon: const Icon(Icons.search, size: 17),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(height: FlySpacing.xs),
                Expanded(
                  child: visibleTasks.when(
                    data: (data) => data.isEmpty
                        ? _search.trim().isNotEmpty
                              ? Center(
                                  child: Text(
                                    context.l10n.isZh
                                        ? '没有匹配的任务'
                                        : 'No matching tasks',
                                  ),
                                )
                              : _canAdd
                              ? WorkspaceEmptyState(
                                  icon: Icons.task_alt,
                                  title: context.l10n.t('emptyTitle'),
                                  actionLabel: context.l10n.t('addTask'),
                                  onCreate: _beginAdd,
                                )
                              : _EmptyTasks(collection: widget.collection)
                        : _TaskRows(
                            tasks: data,
                            lists: lists,
                            scrollController: _scrollController,
                            collection: widget.collection,
                          ),
                    loading: () => const Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                    error: (error, stack) => Center(
                      child: Text(
                        context.l10n.error(context.l10n.t('list'), error),
                        textAlign: TextAlign.center,
                      ),
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

class _ListHeader extends StatelessWidget {
  const _ListHeader({
    required this.title,
    required this.tasks,
    required this.collection,
  });

  final String title;
  final AsyncValue<List<FlyTask>> tasks;
  final TaskCollection collection;

  @override
  Widget build(BuildContext context) {
    final values = tasks.valueOrNull;
    final count = values == null
        ? null
        : collection == TaskCollection.completed ||
              collection == TaskCollection.trash
        ? values.length
        : values.where((task) => !task.isCompleted).length;
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          if (count != null)
            Text(
              collection == TaskCollection.completed ||
                      collection == TaskCollection.trash
                  ? context.l10n.taskCount(count)
                  : context.l10n.openCount(count),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _TaskRows extends ConsumerWidget {
  const _TaskRows({
    required this.tasks,
    required this.lists,
    required this.scrollController,
    required this.collection,
  });

  final List<FlyTask> tasks;
  final List<FlyTaskList> lists;
  final ScrollController scrollController;
  final TaskCollection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (collection == TaskCollection.today) {
      final day = ref.watch(localTodayProvider);
      final today = tasks.where((t) => TaskDateRange.isToday(t, day)).toList();
      final overdue =
          tasks.where((t) => TaskDateRange.isOverdue(t, day)).toList()
            ..sort((a, b) => b.dueDate!.compareTo(a.dueDate!));
      return ListView(
        controller: scrollController,
        children: [
          ListTile(
            dense: true,
            title: Text('${context.l10n.t('today')}  ${today.length}'),
          ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: today.length,
            onReorderItem: (oldIndex, newIndex) async {
              final reordered = [...today];
              final moved = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, moved);
              await ref
                  .read(taskRepositoryProvider)
                  .reorderTask(
                    moved.id,
                    reordered.map((task) => task.id).toList(),
                  );
            },
            itemBuilder: (_, index) => _TaskRow(
              key: ValueKey(today[index].id),
              task: today[index],
              index: index,
              lists: lists,
              collection: collection,
            ),
          ),
          if (overdue.isNotEmpty) ...[
            const Divider(),
            ListTile(
              dense: true,
              title: Text('${context.l10n.t('overdue')}  ${overdue.length}'),
              trailing: TextButton(
                onPressed: () =>
                    _postponeTasks(context, ref, overdue, confirm: true),
                child: Text(context.l10n.t('postponeAll')),
              ),
            ),
            for (final task in overdue)
              _TaskRow(
                reorderable: false,
                key: ValueKey(task.id),
                task: task,
                index: 0,
                lists: lists,
                collection: collection,
              ),
          ],
        ],
      );
    }
    Widget row(int index) {
      final task = tasks[index];
      return _TaskRow(
        key: ValueKey(task.id),
        task: task,
        index: index,
        lists: lists,
        collection: collection,
      );
    }

    final list = collection == TaskCollection.trash
        ? ListView.builder(
            controller: scrollController,
            itemCount: tasks.length,
            itemBuilder: (context, index) => row(index),
          )
        : ReorderableListView.builder(
            scrollController: scrollController,
            buildDefaultDragHandles: false,
            itemCount: tasks.length,
            proxyDecorator: (child, index, animation) => Material(
              elevation: FlyElevation.popup,
              color: Theme.of(context).colorScheme.surface,
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
            itemBuilder: (context, index) => row(index),
          );
    return Scrollbar(controller: scrollController, child: list);
  }
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({
    required this.task,
    required this.index,
    required this.lists,
    required this.collection,
    this.reorderable = true,
    super.key,
  });

  final FlyTask task;
  final bool reorderable;
  final int index;
  final List<FlyTaskList> lists;
  final TaskCollection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedTaskIdProvider) == task.id;
    final date = task.dueDate;
    final inTrash = collection == TaskCollection.trash;
    return FlyTaskRowSurface(
      task: task,
      selected: !inTrash && selected,
      disabled: inTrash,
      dateLabel: date == null ? null : context.l10n.shortDate(date),
      onTap: inTrash ? () {} : () => _open(context, ref),
      onCompleted: inTrash
          ? null
          : (value) => ref
                .read(taskRepositoryProvider)
                .setCompleted(task.id, completed: value),
      onSecondaryTapDown: (details) => inTrash
          ? _showTrashContextMenu(context, ref, details.globalPosition)
          : _showContextMenu(context, ref, details.globalPosition),
      trailing: inTrash
          ? IconButton(
              tooltip: context.l10n.t('restore'),
              onPressed: () =>
                  ref.read(taskRepositoryProvider).restoreTask(task.id),
              icon: const Icon(Icons.restore, size: 18),
            )
          : !reorderable
          ? null
          : ReorderableDragStartListener(
              index: index,
              child: const SizedBox(
                width: 30,
                child: Icon(Icons.drag_indicator, size: 17),
              ),
            ),
    );
  }

  void _open(BuildContext context, WidgetRef ref) {
    ref.read(selectedTaskIdProvider.notifier).state = task.id;
    if (MediaQuery.sizeOf(context).width < FlyBreakpoints.expanded) {
      context.push('/task/${task.id}');
    }
  }

  Future<void> _showContextMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) async {
    final repository = ref.read(taskRepositoryProvider);
    final entries = <PopupMenuEntry<String>>[
      PopupMenuItem(
        value: 'complete',
        child: Text(
          context.l10n.t(task.isCompleted ? 'uncomplete' : 'complete'),
        ),
      ),
      PopupMenuItem(value: 'edit', child: Text(context.l10n.t('edit'))),
      const PopupMenuDivider(),
      PopupMenuItem(value: 'date', child: Text(context.l10n.t('setDate'))),
      if (TaskDateRange.isOverdue(task, ref.read(localTodayProvider)))
        PopupMenuItem(
          value: 'postpone',
          child: Text(context.l10n.t('postponeToday')),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'delete',
        child: Text(
          context.l10n.t('delete'),
          style: const TextStyle(color: FlyColors.danger),
        ),
      ),
    ];
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: entries,
    );
    if (action == null || !context.mounted) return;
    if (action == 'complete') {
      await repository.setCompleted(task.id, completed: !task.isCompleted);
    } else if (action == 'edit') {
      _open(context, ref);
    } else if (action == 'delete') {
      await deleteTaskWithConfirmation(context, ref, task);
    } else if (action == 'postpone') {
      await _postponeTasks(context, ref, [task]);
    } else if (action == 'date') {
      final date = await showDatePicker(
        context: context,
        initialDate: task.dueDate ?? DateTime.now(),
        firstDate: DateTime(1900),
        lastDate: DateTime(2200),
      );
      if (date != null) await repository.moveTaskToDate(task.id, date);
    }
  }

  Future<void> _showTrashContextMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(value: 'restore', child: Text(context.l10n.t('restore'))),
        PopupMenuItem(
          value: 'deleteForever',
          child: Text(
            context.l10n.t('deleteForever'),
            style: const TextStyle(color: FlyColors.danger),
          ),
        ),
      ],
    );
    if (action == 'restore') {
      await ref.read(taskRepositoryProvider).restoreTask(task.id);
      return;
    }
    if (action != 'deleteForever' || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('deleteForeverTitle')),
        content: Text(context.l10n.t('deleteForeverBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.t('deleteForever')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(taskRepositoryProvider).deleteTaskPermanently(task.id);
    }
  }
}

Future<void> _postponeTasks(
  BuildContext context,
  WidgetRef ref,
  List<FlyTask> tasks, {
  bool confirm = false,
}) async {
  if (confirm) {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.l10n.t('postponeAll')),
        content: Text(
          context.l10n
              .t('postponeConfirm')
              .replaceAll('{count}', '${tasks.length}'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(context.l10n.t('confirm')),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
  }
  try {
    await ref
        .read(taskRepositoryProvider)
        .postponeOverdueTasks(
          tasks.map((t) => t.id).toList(),
          ref.read(localTodayProvider),
        );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _EmptyTasks extends StatelessWidget {
  const _EmptyTasks({required this.collection});

  final TaskCollection collection;

  @override
  Widget build(BuildContext context) {
    final (icon, titleKey, bodyKey) = switch (collection) {
      TaskCollection.completed => (
        Icons.task_alt,
        'emptyCompletedTitle',
        'emptyCompletedBody',
      ),
      TaskCollection.trash => (
        Icons.delete_outline,
        'emptyTrashTitle',
        'emptyTrashBody',
      ),
      _ => (Icons.check_circle_outline, 'emptyTitle', 'emptyBody'),
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: FlySpacing.sm),
            Text(
              context.l10n.t(titleKey),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FlySpacing.xs),
            Text(
              context.l10n.t(bodyKey),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
