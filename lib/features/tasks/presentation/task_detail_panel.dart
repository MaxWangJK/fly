import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../shared/design_system/design_tokens.dart';
import '../domain/task.dart';
import 'task_providers.dart';

class TaskDetailPanel extends ConsumerWidget {
  const TaskDetailPanel({required this.taskId, super.key});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(taskProvider(taskId));
    return task.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (error, stack) =>
          Center(child: Text('Could not load task\n$error')),
      data: (value) => value == null
          ? const _MissingTask()
          : _TaskEditor(key: ValueKey(value.id), task: value),
    );
  }
}

class _TaskEditor extends ConsumerStatefulWidget {
  const _TaskEditor({required this.task, super.key});

  final FlyTask task;

  @override
  ConsumerState<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends ConsumerState<_TaskEditor> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  final _tag = TextEditingController();
  final _checklist = TextEditingController();
  late FlyTask _draft;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.task;
    _title = TextEditingController(text: _draft.title);
    _description = TextEditingController(text: _draft.description);
  }

  @override
  void didUpdateWidget(covariant _TaskEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.task.version != oldWidget.task.version && !_saving) {
      _draft = widget.task;
      _title.text = widget.task.title;
      _description.text = widget.task.description;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _tag.dispose();
    _checklist.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    await ref
        .read(taskRepositoryProvider)
        .saveTask(
          _draft.copyWith(title: title, description: _description.text.trim()),
        );
    if (mounted) setState(() => _saving = false);
  }

  Future<DateTime?> _pickDate(DateTime? initial) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 10),
      initialDate: initial ?? now,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lists = ref.watch(taskListsProvider).valueOrNull ?? const [];
    final tags = ref.watch(taskTagsProvider(_draft.id)).valueOrNull ?? const [];
    final checklist =
        ref.watch(checklistProvider(_draft.id)).valueOrNull ?? const [];
    final reminder = ref.watch(reminderProvider(_draft.id)).valueOrNull;

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FlySpacing.lg),
          children: [
            Row(
              children: [
                Text('Task', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  tooltip: 'Close details',
                  onPressed: () =>
                      ref.read(selectedTaskIdProvider.notifier).state = null,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: FlySpacing.md),
            TextField(
              controller: _title,
              style: Theme.of(context).textTheme.titleMedium,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: FlySpacing.sm),
            TextField(
              controller: _description,
              minLines: 3,
              maxLines: 7,
              decoration: const InputDecoration(
                labelText: 'Notes',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: FlySpacing.lg),
            _Section(
              title: 'Plan',
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _draft.listId,
                  decoration: const InputDecoration(
                    labelText: 'List',
                    prefixIcon: Icon(Icons.list),
                  ),
                  items: [
                    for (final list in lists)
                      DropdownMenuItem(value: list.id, child: Text(list.name)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _draft = _draft.copyWith(listId: value));
                    }
                  },
                ),
                const SizedBox(height: FlySpacing.sm),
                DropdownButtonFormField<TaskPriority>(
                  initialValue: _draft.priority,
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                  items: [
                    for (final priority in TaskPriority.values)
                      DropdownMenuItem(
                        value: priority,
                        child: Text(_priorityLabel(priority)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _draft = _draft.copyWith(priority: value));
                    }
                  },
                ),
                const SizedBox(height: FlySpacing.sm),
                _DateField(
                  label: 'Start',
                  value: _draft.startDate,
                  onTap: () async {
                    final value = await _pickDate(_draft.startDate);
                    if (value != null && mounted) {
                      setState(
                        () => _draft = _draft.copyWith(startDate: value),
                      );
                    }
                  },
                  onClear: () =>
                      setState(() => _draft = _draft.copyWith(startDate: null)),
                ),
                const SizedBox(height: FlySpacing.sm),
                _DateField(
                  label: 'Due',
                  value: _draft.dueDate,
                  onTap: () async {
                    final value = await _pickDate(_draft.dueDate);
                    if (value != null && mounted) {
                      setState(() => _draft = _draft.copyWith(dueDate: value));
                    }
                  },
                  onClear: () =>
                      setState(() => _draft = _draft.copyWith(dueDate: null)),
                ),
                const SizedBox(height: FlySpacing.sm),
                DropdownButtonFormField<String?>(
                  initialValue: _draft.recurrenceRule,
                  decoration: const InputDecoration(
                    labelText: 'Repeat',
                    prefixIcon: Icon(Icons.repeat),
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Never')),
                    DropdownMenuItem(value: 'FREQ=DAILY', child: Text('Daily')),
                    DropdownMenuItem(
                      value: 'FREQ=WEEKLY',
                      child: Text('Weekly'),
                    ),
                    DropdownMenuItem(
                      value: 'FREQ=MONTHLY',
                      child: Text('Monthly'),
                    ),
                  ],
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(recurrenceRule: value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FlySpacing.lg),
            _Section(
              title: 'Matrix',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Important'),
                  subtitle: const Text('Meaningful impact or strategic value'),
                  value: _draft.importance,
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(importance: value),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Urgent'),
                  subtitle: const Text('Needs attention soon'),
                  value: _draft.urgency,
                  onChanged: (value) =>
                      setState(() => _draft = _draft.copyWith(urgency: value)),
                ),
              ],
            ),
            const SizedBox(height: FlySpacing.lg),
            _Section(
              title: 'Tags',
              children: [
                Wrap(
                  spacing: FlySpacing.xs,
                  runSpacing: FlySpacing.xs,
                  children: [
                    for (final tag in tags)
                      InputChip(
                        label: Text(tag),
                        onDeleted: () => ref
                            .read(taskRepositoryProvider)
                            .setTags(
                              _draft.id,
                              tags.where((value) => value != tag),
                            ),
                      ),
                  ],
                ),
                const SizedBox(height: FlySpacing.xs),
                TextField(
                  controller: _tag,
                  decoration: const InputDecoration(
                    hintText: 'Add tag',
                    prefixIcon: Icon(Icons.tag),
                  ),
                  onSubmitted: (value) async {
                    await ref.read(taskRepositoryProvider).setTags(_draft.id, [
                      ...tags,
                      value,
                    ]);
                    _tag.clear();
                  },
                ),
              ],
            ),
            const SizedBox(height: FlySpacing.lg),
            _Section(
              title: 'Checklist',
              children: [
                for (final item in checklist)
                  Row(
                    children: [
                      Checkbox(
                        value: item.isCompleted,
                        onChanged: (value) => ref
                            .read(taskRepositoryProvider)
                            .toggleChecklistItem(
                              item.id,
                              completed: value ?? false,
                            ),
                      ),
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            decoration: item.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove checklist item',
                        onPressed: () => ref
                            .read(taskRepositoryProvider)
                            .deleteChecklistItem(item.id),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                TextField(
                  controller: _checklist,
                  decoration: const InputDecoration(
                    hintText: 'Add checklist item',
                    prefixIcon: Icon(Icons.add_task),
                  ),
                  onSubmitted: (value) async {
                    await ref
                        .read(taskRepositoryProvider)
                        .addChecklistItem(_draft.id, value);
                    _checklist.clear();
                  },
                ),
              ],
            ),
            const SizedBox(height: FlySpacing.lg),
            _Section(
              title: 'Reminder',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_outlined),
                  title: Text(
                    reminder == null
                        ? 'No reminder'
                        : DateFormat('MMM d, HH:mm').format(reminder.remindAt),
                  ),
                  trailing: reminder == null
                      ? TextButton(
                          onPressed: () {
                            final base = _draft.dueDate ?? DateTime.now();
                            ref
                                .read(taskRepositoryProvider)
                                .setReminder(
                                  _draft.id,
                                  base.add(const Duration(hours: 1)),
                                );
                          },
                          child: const Text('Add'),
                        )
                      : IconButton(
                          tooltip: 'Clear reminder',
                          onPressed: () => ref
                              .read(taskRepositoryProvider)
                              .clearReminder(_draft.id),
                          icon: const Icon(Icons.close),
                        ),
                ),
              ],
            ),
            const SizedBox(height: FlySpacing.xl),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Save changes'),
            ),
            const SizedBox(height: FlySpacing.sm),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: FlyColors.danger),
              onPressed: () async {
                await ref.read(taskRepositoryProvider).deleteTask(_draft.id);
                ref.read(selectedTaskIdProvider.notifier).state = null;
                if (context.mounted && Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete task'),
            ),
          ],
        ),
      ),
    );
  }

  static String _priorityLabel(TaskPriority priority) => switch (priority) {
    TaskPriority.none => 'No priority',
    TaskPriority.low => 'Low',
    TaskPriority.medium => 'Medium',
    TaskPriority.high => 'High',
  };
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: FlySpacing.sm),
      ...children,
    ],
  );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: FlySpacing.sm),
    shape: RoundedRectangleBorder(
      side: BorderSide(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(FlyRadius.md),
    ),
    leading: const Icon(Icons.event_outlined),
    title: Text(label),
    subtitle: Text(
      value == null ? 'Not set' : DateFormat('EEE, MMM d, y').format(value!),
    ),
    onTap: onTap,
    trailing: value == null
        ? const Icon(Icons.chevron_right)
        : IconButton(
            tooltip: 'Clear $label date',
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 18),
          ),
  );
}

class _MissingTask extends StatelessWidget {
  const _MissingTask();

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('This task was deleted or is unavailable.'));
}
