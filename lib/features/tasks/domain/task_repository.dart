import 'checklist_item.dart';
import 'task.dart';
import 'task_list.dart';
import 'task_reminder.dart';

abstract interface class TaskRepository {
  Stream<List<FlyTask>> watchAllTasks();
  Stream<List<FlyTask>> watchInboxTasks();
  Stream<List<FlyTask>> watchTodayTasks(DateTime day);
  Stream<List<FlyTask>> watchUpcomingTasks(DateTime from);
  Stream<List<FlyTask>> watchTasksForList(String listId);
  Stream<List<FlyTask>> watchTasksForRange(DateTime start, DateTime end);
  Stream<FlyTask?> watchTask(String id);
  Stream<List<FlyTaskList>> watchLists();
  Stream<List<String>> watchTags(String taskId);
  Stream<List<FlyChecklistItem>> watchChecklist(String taskId);
  Stream<FlyReminder?> watchReminder(String taskId);

  Future<FlyTask> createTask({
    required String title,
    String description,
    String listId,
    DateTime? dueDate,
    bool importance,
    bool urgency,
  });

  Future<void> saveTask(FlyTask task);
  Future<void> setCompleted(String taskId, {required bool completed});
  Future<void> deleteTask(String taskId);
  Future<void> moveTaskToList(String taskId, String listId);
  Future<void> moveTaskToDate(String taskId, DateTime dueDate);
  Future<void> moveTaskToQuadrant(
    String taskId, {
    required bool importance,
    required bool urgency,
  });
  Future<void> reorderTask(
    String taskId,
    List<String> orderedTaskIds,
  );

  Future<void> setTags(String taskId, Iterable<String> names);
  Future<void> addChecklistItem(String taskId, String title);
  Future<void> toggleChecklistItem(String itemId, {required bool completed});
  Future<void> deleteChecklistItem(String itemId);
  Future<void> setReminder(String taskId, DateTime remindAt);
  Future<void> clearReminder(String taskId);
  Future<void> seedDevelopmentData();
}
