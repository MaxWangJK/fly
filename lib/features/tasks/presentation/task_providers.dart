import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../data/drift_task_repository.dart';
import '../domain/checklist_item.dart';
import '../domain/task.dart';
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
final selectedDateProvider = StateProvider<DateTime>(
  (ref) => DateTime.now(),
);
final calendarMonthProvider = StateProvider<DateTime>(
  (ref) {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  },
);
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

final allTasksProvider = StreamProvider<List<FlyTask>>(
  (ref) => ref.watch(taskRepositoryProvider).watchAllTasks(),
);
final inboxTasksProvider = StreamProvider<List<FlyTask>>(
  (ref) => ref.watch(taskRepositoryProvider).watchInboxTasks(),
);
final todayTasksProvider = StreamProvider<List<FlyTask>>(
  (ref) => ref.watch(taskRepositoryProvider).watchTodayTasks(DateTime.now()),
);
final upcomingTasksProvider = StreamProvider<List<FlyTask>>(
  (ref) => ref.watch(taskRepositoryProvider).watchUpcomingTasks(DateTime.now()),
);
final listTasksProvider =
    StreamProvider.family<List<FlyTask>, String>((ref, listId) {
  return ref.watch(taskRepositoryProvider).watchTasksForList(listId);
});
final taskProvider = StreamProvider.family<FlyTask?, String>((ref, taskId) {
  return ref.watch(taskRepositoryProvider).watchTask(taskId);
});
final taskListsProvider = StreamProvider<List<FlyTaskList>>(
  (ref) => ref.watch(taskRepositoryProvider).watchLists(),
);
final taskTagsProvider =
    StreamProvider.family<List<String>, String>((ref, taskId) {
  return ref.watch(taskRepositoryProvider).watchTags(taskId);
});
final checklistProvider =
    StreamProvider.family<List<FlyChecklistItem>, String>((ref, taskId) {
  return ref.watch(taskRepositoryProvider).watchChecklist(taskId);
});
final reminderProvider =
    StreamProvider.family<FlyReminder?, String>((ref, taskId) {
  return ref.watch(taskRepositoryProvider).watchReminder(taskId);
});

final monthTasksProvider =
    StreamProvider.family<List<FlyTask>, DateTime>((ref, month) {
  final start = DateTime(month.year, month.month);
  final end = DateTime(month.year, month.month + 1);
  return ref.watch(taskRepositoryProvider).watchTasksForRange(start, end);
});
