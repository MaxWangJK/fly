import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/design_system/fly_color_scheme.dart';
import '../data/drift_task_repository.dart';
import '../domain/checklist_item.dart';
import '../domain/task.dart';
import '../domain/task_date_range.dart';
import '../domain/task_list.dart';
import '../domain/task_reminder.dart';
import '../domain/task_repository.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => DriftTaskRepository(ref.watch(databaseProvider)),
);

final selectedTaskIdProvider = StateProvider<String?>((ref) => null);
final selectedDateProvider = StateProvider<DateTime?>((ref) => null);
final calendarMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final flyPaletteProvider = StateProvider<FlyPaletteId>(
  (ref) => FlyPaletteId.flyDefault,
);
final localeProvider = StateProvider<Locale>((ref) => const Locale('zh', 'CN'));

final allTasksProvider = StreamProvider<List<FlyTask>>(
  (ref) => ref.watch(taskRepositoryProvider).watchAllTasks(),
);
final completedTasksProvider = StreamProvider<List<FlyTask>>(
  (ref) => ref.watch(taskRepositoryProvider).watchCompletedTasks(),
);
final deletedTasksProvider = StreamProvider<List<FlyTask>>(
  (ref) => ref.watch(taskRepositoryProvider).watchDeletedTasks(),
);
final inboxTasksProvider = StreamProvider<List<FlyTask>>(
  (ref) => ref.watch(taskRepositoryProvider).watchInboxTasks(),
);
final todayTasksProvider = StreamProvider.autoDispose<List<FlyTask>>(
  (ref) => ref
      .watch(taskRepositoryProvider)
      .watchTodayTasks(ref.watch(localTodayProvider)),
);
final todayWorkspaceTasksProvider =
    Provider.autoDispose<AsyncValue<List<FlyTask>>>((ref) {
      final day = ref.watch(localTodayProvider);
      return ref
          .watch(allTasksProvider)
          .whenData(
            (tasks) => tasks
                .where(
                  (task) =>
                      TaskDateRange.isToday(task, day) ||
                      TaskDateRange.isOverdue(task, day),
                )
                .toList(),
          );
    });
final localTodayProvider = StateProvider.autoDispose<DateTime>((ref) {
  DateTime day() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  var current = day();
  final timer = Timer.periodic(const Duration(minutes: 1), (_) {
    final next = day();
    if (next != current) {
      current = next;
      ref.controller.state = next;
    }
  });
  ref.onDispose(timer.cancel);
  return current;
});
final upcomingTasksProvider = StreamProvider<List<FlyTask>>((ref) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = start.add(const Duration(days: 8));
  return ref.watch(taskRepositoryProvider).watchTasksForRange(start, end);
});
final listTasksProvider = StreamProvider.family<List<FlyTask>, String>(
  (ref, listId) => ref.watch(taskRepositoryProvider).watchTasksForList(listId),
);
final taskProvider = StreamProvider.family<FlyTask?, String>(
  (ref, taskId) => ref.watch(taskRepositoryProvider).watchTask(taskId),
);
final taskListsProvider = StreamProvider<List<FlyTaskList>>(
  (ref) => ref.watch(taskRepositoryProvider).watchLists(),
);
final taskTagsProvider = StreamProvider.family<List<String>, String>(
  (ref, taskId) => ref.watch(taskRepositoryProvider).watchTags(taskId),
);
final checklistProvider = StreamProvider.family<List<FlyChecklistItem>, String>(
  (ref, taskId) => ref.watch(taskRepositoryProvider).watchChecklist(taskId),
);
final reminderProvider = StreamProvider.family<FlyReminder?, String>(
  (ref, taskId) => ref.watch(taskRepositoryProvider).watchReminder(taskId),
);
final monthTasksProvider = StreamProvider.family<List<FlyTask>, DateTime>((
  ref,
  month,
) {
  final gridStart = DateTime(month.year, month.month, 1);
  final sundayOffset = gridStart.weekday % 7;
  final start = gridStart.subtract(Duration(days: sundayOffset));
  final end = start.add(const Duration(days: 42));
  return ref.watch(taskRepositoryProvider).watchTasksForRange(start, end);
});
