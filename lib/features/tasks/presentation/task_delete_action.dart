import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/design_system/destructive_action.dart';
import '../../../l10n/fly_localizations.dart';
import '../domain/task_date_range.dart';
import '../domain/task.dart';
import 'task_providers.dart';

Future<void> showTaskDeleteContextMenu(
  BuildContext context,
  WidgetRef ref,
  FlyTask task,
  Offset position,
) async {
  final selected = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    items: [
      if (TaskDateRange.isOverdue(task, DateTime.now()))
        PopupMenuItem(
          value: 'postpone',
          child: Text(context.l10n.t('postponeToday')),
        ),
      PopupMenuItem(
        value: 'delete',
        child: Text(
          context.l10n.t('deleteTask'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    ],
  );
  if (selected == null || !context.mounted) return;
  if (selected == 'postpone') {
    await ref.read(taskRepositoryProvider).postponeOverdueTasks([
      task.id,
    ], DateTime.now());
    return;
  }
  await deleteTaskWithConfirmation(context, ref, task);
}

Future<bool> deleteTaskWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  FlyTask task,
) async {
  final confirmed = await confirmFlyDestructiveAction(
    context,
    title: context.l10n.t('deleteTask'),
    message: task.title,
    confirmLabel: context.l10n.t('deleteTask'),
  );
  if (!confirmed || !context.mounted) return false;
  await ref.read(taskRepositoryProvider).deleteTask(task.id);
  if (ref.read(selectedTaskIdProvider) == task.id) {
    ref.read(selectedTaskIdProvider.notifier).state = null;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.isZh ? '已移动到已删除' : 'Moved to trash')),
    );
  }
  return true;
}
