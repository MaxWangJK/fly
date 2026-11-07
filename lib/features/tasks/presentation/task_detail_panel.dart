import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/fly_localizations.dart';
import '../../../shared/design_system/design_tokens.dart';
import '../../../shared/design_system/model_text_field.dart';
import '../domain/task.dart';
import 'task_providers.dart';

class TaskDetailPanel extends ConsumerWidget {
  const TaskDetailPanel({required this.taskId, super.key});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(taskProvider(taskId));
    return task.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (error, stack) => Center(
        child: Text(context.l10n.error(context.l10n.t('details'), error)),
      ),
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
  final _scrollController = ScrollController();
  Timer? _saveTimer;
  late FlyTask _draft;
  bool _dirty = false;
  bool _saving = false;
  bool _syncingText = false;
  bool _selectingRangeEnd = false;
  int _editRevision = 0;

  @override
  void initState() {
    super.initState();
    _draft = widget.task;
    _title = TextEditingController(text: _draft.title);
    _description = TextEditingController(text: _draft.description);
    _title.addListener(_textChanged);
    _description.addListener(_textChanged);
  }

  @override
  void didUpdateWidget(covariant _TaskEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.task.version <= _draft.version) return;
    if (_dirty || _saving) {
      _draft = _draft.copyWith(
        version: widget.task.version,
        updatedAt: widget.task.updatedAt,
      );
      return;
    }
    _draft = widget.task;
    _syncingText = true;
    _title.syncTextFromModel(widget.task.title);
    _description.syncTextFromModel(widget.task.description);
    _syncingText = false;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_dirty && _title.text.trim().isNotEmpty) {
      ref
          .read(taskRepositoryProvider)
          .saveTask(
            _draft.copyWith(
              title: _title.text.trim(),
              description: _description.text.trim(),
            ),
          );
    }
    _title
      ..removeListener(_textChanged)
      ..dispose();
    _description
      ..removeListener(_textChanged)
      ..dispose();
    _tag.dispose();
    _checklist.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _textChanged() {
    if (_syncingText) return;
    _queueSave();
  }

  void _change(FlyTask next) {
    setState(() => _draft = next);
    _queueSave();
  }

  void _queueSave() {
    _saveTimer?.cancel();
    _dirty = true;
    _editRevision++;
    if (mounted) setState(() {});
    _saveTimer = Timer(FlyMotion.autoSave, _saveNow);
  }

  Future<void> _saveNow() async {
    final title = _title.text.trim();
    if (!_dirty || title.isEmpty) return;
    if (_saving) {
      _saveTimer = Timer(FlyMotion.autoSave, _saveNow);
      return;
    }
    final revision = _editRevision;
    final next = _draft.copyWith(
      title: title,
      description: _description.text.trim(),
    );
    setState(() => _saving = true);
    try {
      await ref.read(taskRepositoryProvider).saveTask(next);
      if (!mounted) return;
      final savedAt = DateTime.now();
      if (_editRevision == revision) {
        _draft = next.copyWith(version: next.version + 1, updatedAt: savedAt);
        _dirty = false;
      } else {
        _draft = _draft.copyWith(version: next.version + 1, updatedAt: savedAt);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        if (_dirty) {
          _saveTimer?.cancel();
          _saveTimer = Timer(FlyMotion.autoSave, _saveNow);
        }
      }
    }
  }

  void _selectRangeDay(DateTime day) {
    final normalized = DateTime(day.year, day.month, day.day);
    if (!_selectingRangeEnd || _draft.startDate == null) {
      setState(() => _selectingRangeEnd = true);
      _change(_draft.copyWith(startDate: normalized, dueDate: null));
      return;
    }

    final start = DateTime(
      _draft.startDate!.year,
      _draft.startDate!.month,
      _draft.startDate!.day,
    );
    final first = normalized.isBefore(start) ? normalized : start;
    final last = normalized.isBefore(start) ? start : normalized;
    setState(() => _selectingRangeEnd = false);
    _change(_draft.copyWith(startDate: first, dueDate: last));
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final start = _draft.startDate ?? _draft.dueDate ?? now;
    final end = _draft.dueDate ?? start;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 10),
      initialDateRange: DateTimeRange(start: start, end: end),
      helpText: context.l10n.t('customDateRange'),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectingRangeEnd = false);
    _change(
      _draft.copyWith(
        startDate: DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        ),
        dueDate: DateTime(picked.end.year, picked.end.month, picked.end.day),
      ),
    );
  }

  void _clearDates() {
    setState(() => _selectingRangeEnd = false);
    _change(_draft.copyWith(startDate: null, dueDate: null));
  }

  @override
  Widget build(BuildContext context) {
    final lists = ref.watch(taskListsProvider).valueOrNull ?? const [];
    final tags = ref.watch(taskTagsProvider(_draft.id)).valueOrNull ?? const [];
    final checklist =
        ref.watch(checklistProvider(_draft.id)).valueOrNull ?? const [];
    final reminder = ref.watch(reminderProvider(_draft.id)).valueOrNull;
    final saveLabel = _saving
        ? context.l10n.t('saving')
        : _dirty
        ? context.l10n.t('waiting')
        : context.l10n.t('saved');

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(
              FlySpacing.lg,
              FlySpacing.md,
              FlySpacing.lg,
              FlySpacing.xl,
            ),
            children: [
              Row(
                children: [
                  const Spacer(),
                  AnimatedSwitcher(
                    duration: FlyMotion.fast,
                    child: Text(
                      saveLabel,
                      key: ValueKey(saveLabel),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _saving
                            ? FlyColors.accent
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: FlySpacing.xs),
                  IconButton(
                    tooltip: context.l10n.t('close'),
                    onPressed: () =>
                        ref.read(selectedTaskIdProvider.notifier).state = null,
                    icon: const Icon(Icons.close, size: 19),
                  ),
                ],
              ),
              const SizedBox(height: FlySpacing.xs),
              TextField(
                controller: _title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: context.l10n.t('taskContent'),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(height: FlySpacing.sm),
              TextField(
                controller: _description,
                minLines: 7,
                maxLines: 14,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: context.l10n.t('notesHint'),
                  contentPadding: const EdgeInsets.all(FlySpacing.sm),
                ),
              ),
              const SizedBox(height: FlySpacing.lg),
              _Section(
                title: context.l10n.t('list'),
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey('list-${_draft.listId}'),
                    initialValue: _draft.listId,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.list, size: 19),
                    ),
                    items: [
                      for (final list in lists)
                        DropdownMenuItem(
                          value: list.id,
                          child: Text(
                            list.id == 'inbox'
                                ? context.l10n.t('inbox')
                                : list.name,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _change(_draft.copyWith(listId: value));
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: FlySpacing.lg),
              _Section(
                title: context.l10n.t('priority'),
                children: [
                  _SingleChoiceRow<TaskPriority>(
                    value: _draft.priority,
                    options: [
                      for (final priority in TaskPriority.values)
                        _ChoiceOption(
                          priority,
                          _priorityLabel(context, priority),
                        ),
                    ],
                    onChanged: (value) =>
                        _change(_draft.copyWith(priority: value)),
                  ),
                ],
              ),
              const SizedBox(height: FlySpacing.lg),
              _Section(
                title: context.l10n.t('dates'),
                children: [
                  _WeekRangePicker(
                    start: _draft.startDate,
                    due: _draft.dueDate,
                    selectingEnd: _selectingRangeEnd,
                    onSelect: _selectRangeDay,
                    onCustom: _pickCustomRange,
                    onClear: _clearDates,
                  ),
                ],
              ),
              const SizedBox(height: FlySpacing.lg),
              _Section(
                title: context.l10n.t('repeat'),
                children: [
                  _SingleChoiceRow<String?>(
                    value: _draft.recurrenceRule,
                    options: [
                      _ChoiceOption(null, context.l10n.t('never')),
                      _ChoiceOption('FREQ=DAILY', context.l10n.t('daily')),
                      _ChoiceOption('FREQ=WEEKLY', context.l10n.t('weekly')),
                      _ChoiceOption('FREQ=MONTHLY', context.l10n.t('monthly')),
                    ],
                    onChanged: (value) =>
                        _change(_draft.copyWith(recurrenceRule: value)),
                  ),
                ],
              ),
              const SizedBox(height: FlySpacing.md),
              _InlineFlags(
                important: _draft.importance,
                urgent: _draft.urgency,
                onImportantChanged: (value) =>
                    _change(_draft.copyWith(importance: value)),
                onUrgentChanged: (value) =>
                    _change(_draft.copyWith(urgency: value)),
              ),
              const SizedBox(height: FlySpacing.lg),
              _Section(
                title: context.l10n.t('tags'),
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
                    decoration: InputDecoration(
                      hintText: context.l10n.t('addTag'),
                      prefixIcon: const Icon(Icons.tag, size: 19),
                    ),
                    onSubmitted: (value) async {
                      await ref.read(taskRepositoryProvider).setTags(
                        _draft.id,
                        [...tags, value],
                      );
                      _tag.clear();
                    },
                  ),
                ],
              ),
              const SizedBox(height: FlySpacing.lg),
              _Section(
                title: context.l10n.t('checklist'),
                children: [
                  for (final item in checklist)
                    SizedBox(
                      height: 38,
                      child: Row(
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
                            tooltip: context.l10n.t('delete'),
                            onPressed: () => ref
                                .read(taskRepositoryProvider)
                                .deleteChecklistItem(item.id),
                            icon: const Icon(Icons.close, size: 17),
                          ),
                        ],
                      ),
                    ),
                  TextField(
                    controller: _checklist,
                    decoration: InputDecoration(
                      hintText: context.l10n.t('addChecklist'),
                      prefixIcon: const Icon(Icons.add_task, size: 19),
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
                title: context.l10n.t('reminder'),
                children: [
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.notifications_outlined, size: 19),
                    title: Text(
                      reminder == null
                          ? context.l10n.t('noReminder')
                          : context.l10n.fullDate(reminder.remindAt),
                    ),
                    trailing: reminder == null
                        ? TextButton(
                            onPressed: () {
                              final base = _draft.dueDate ?? DateTime.now();
                              ref
                                  .read(taskRepositoryProvider)
                                  .setReminder(
                                    _draft.id,
                                    base.add(const Duration(hours: 9)),
                                  );
                            },
                            child: Text(context.l10n.t('addReminder')),
                          )
                        : IconButton(
                            tooltip: context.l10n.t('clear'),
                            onPressed: () => ref
                                .read(taskRepositoryProvider)
                                .clearReminder(_draft.id),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: FlySpacing.lg),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: FlyColors.danger,
                  ),
                  onPressed: () async {
                    await ref
                        .read(taskRepositoryProvider)
                        .deleteTask(_draft.id);
                    ref.read(selectedTaskIdProvider.notifier).state = null;
                    if (context.mounted && Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(context.l10n.t('deleteTask')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _priorityLabel(BuildContext context, TaskPriority priority) =>
      switch (priority) {
        TaskPriority.none => context.l10n.t('none'),
        TaskPriority.low => context.l10n.t('low'),
        TaskPriority.medium => context.l10n.t('medium'),
        TaskPriority.high => context.l10n.t('high'),
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
      Text(
        title,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: FlySpacing.xs),
      ...children,
    ],
  );
}

class _ChoiceOption<T> {
  const _ChoiceOption(this.value, this.label);

  final T value;
  final String label;
}

class _SingleChoiceRow<T> extends StatelessWidget {
  const _SingleChoiceRow({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<_ChoiceOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: FlySpacing.xs,
    runSpacing: FlySpacing.xs,
    children: [
      for (final option in options)
        _SquareChoice(
          label: option.label,
          selected: option.value == value,
          onTap: () => onChanged(option.value),
        ),
    ],
  );
}

class _SquareChoice extends StatelessWidget {
  const _SquareChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FlyRadius.sm),
      child: AnimatedContainer(
        duration: FlyMotion.fast,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: FlySpacing.sm),
        decoration: BoxDecoration(
          color: selected
              ? FlyColors.accent.withValues(alpha: 0.08)
              : Colors.transparent,
          border: Border.all(
            color: selected ? FlyColors.accent : Theme.of(context).dividerColor,
          ),
          borderRadius: BorderRadius.circular(FlyRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: selected ? FlyColors.accent : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? FlyColors.accent
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}

class _WeekRangePicker extends StatelessWidget {
  const _WeekRangePicker({
    required this.start,
    required this.due,
    required this.selectingEnd,
    required this.onSelect,
    required this.onCustom,
    required this.onClear,
  });

  final DateTime? start;
  final DateTime? due;
  final bool selectingEnd;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onCustom;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = List.generate(7, (index) => today.add(Duration(days: index)));
    final hasDate = start != null || due != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _summary(context),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: selectingEnd
                      ? FlyColors.accent
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (hasDate)
              IconButton(
                tooltip: context.l10n.t('clear'),
                visualDensity: VisualDensity.compact,
                onPressed: onClear,
                icon: const Icon(Icons.close, size: 16),
              ),
          ],
        ),
        const SizedBox(height: FlySpacing.xxs),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < days.length; index++) ...[
                _DateChip(
                  day: days[index],
                  label: index == 0
                      ? context.l10n.t('today')
                      : context.l10n.weekdays[days[index].weekday % 7],
                  selected:
                      _sameDayNullable(start, days[index]) ||
                      _sameDayNullable(due, days[index]),
                  inRange: _isInRange(days[index]),
                  onTap: () => onSelect(days[index]),
                ),
                const SizedBox(width: 6),
              ],
              _DateChip(
                icon: Icons.calendar_month_outlined,
                label: context.l10n.t('custom'),
                onTap: onCustom,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _summary(BuildContext context) {
    if (selectingEnd && start != null) {
      return context.l10n.selectEndDate(_shortDate(start!));
    }
    if (start == null && due == null) return context.l10n.t('dateRangeHint');
    if (start != null && due != null) {
      return '${context.l10n.t('start')} ${_shortDate(start!)}  ·  '
          '${context.l10n.t('due')} ${_shortDate(due!)}';
    }
    if (start != null) {
      return '${context.l10n.t('start')} ${_shortDate(start!)}';
    }
    return '${context.l10n.t('due')} ${_shortDate(due!)}';
  }

  bool _isInRange(DateTime day) {
    if (start == null || due == null) return false;
    final normalized = DateTime(day.year, day.month, day.day);
    final rangeStart = DateTime(start!.year, start!.month, start!.day);
    final rangeEnd = DateTime(due!.year, due!.month, due!.day);
    return !normalized.isBefore(rangeStart) && !normalized.isAfter(rangeEnd);
  }

  String _shortDate(DateTime day) => '${day.month}/${day.day}';
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.onTap,
    this.day,
    this.icon,
    this.selected = false,
    this.inRange = false,
  });

  final DateTime? day;
  final IconData? icon;
  final String label;
  final bool selected;
  final bool inRange;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: day == null
          ? const ValueKey('custom-date-range')
          : ValueKey('quick-date-${day!.year}-${day!.month}-${day!.day}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(FlyRadius.sm),
      child: AnimatedContainer(
        duration: FlyMotion.fast,
        width: 49,
        height: 52,
        decoration: BoxDecoration(
          color: selected
              ? FlyColors.accent
              : inRange
              ? FlyColors.accent.withValues(alpha: 0.10)
              : Colors.transparent,
          border: Border.all(
            color: selected ? FlyColors.accent : Theme.of(context).dividerColor,
          ),
          borderRadius: BorderRadius.circular(FlyRadius.sm),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null)
              Icon(icon, size: 17)
            else
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: selected ? Colors.white : null),
              ),
            const SizedBox(height: 2),
            Text(
              day == null
                  ? context.l10n.t('date')
                  : '${day!.month}/${day!.day}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InlineFlags extends StatelessWidget {
  const _InlineFlags({
    required this.important,
    required this.urgent,
    required this.onImportantChanged,
    required this.onUrgentChanged,
  });

  final bool important;
  final bool urgent;
  final ValueChanged<bool> onImportantChanged;
  final ValueChanged<bool> onUrgentChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: FlySpacing.lg,
    runSpacing: FlySpacing.xs,
    children: [
      _FlagCheckbox(
        label: context.l10n.t('important'),
        value: important,
        onChanged: onImportantChanged,
      ),
      _FlagCheckbox(
        label: context.l10n.t('urgent'),
        value: urgent,
        onChanged: onUrgentChanged,
      ),
    ],
  );
}

class _FlagCheckbox extends StatelessWidget {
  const _FlagCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    borderRadius: BorderRadius.circular(FlyRadius.sm),
    child: Padding(
      padding: const EdgeInsets.only(right: FlySpacing.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: value,
            onChanged: (next) => onChanged(next ?? false),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}

bool _sameDayNullable(DateTime? left, DateTime right) =>
    left != null &&
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

class _MissingTask extends StatelessWidget {
  const _MissingTask();

  @override
  Widget build(BuildContext context) =>
      Center(child: Text(context.l10n.t('unavailable')));
}
