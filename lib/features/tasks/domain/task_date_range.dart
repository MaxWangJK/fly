import 'task.dart';

/// Inclusive local calendar days; a single endpoint represents one day only.
class TaskDateRange {
  /// V11 calendar is a single-day projection, not an interval rendering.
  static DateTime? calendarDate(FlyTask task, DateTime today) {
    if (task.isDeleted) return null;
    if (task.isCompleted || task.completedAt != null) {
      return day(task.completedAt ?? task.updatedAt);
    }
    if (task.startDate != null && task.dueDate != null) {
      if (isToday(task, today)) return day(today);
      return day(
        day(task.startDate!).isAfter(day(today))
            ? task.startDate!
            : task.dueDate!,
      );
    }
    final date = task.startDate ?? task.dueDate;
    return date == null ? null : day(date);
  }

  static DateTime day(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static bool contains(FlyTask task, DateTime date) {
    final start = task.startDate ?? task.dueDate;
    final end = task.dueDate ?? task.startDate;
    if (task.isDeleted || start == null || end == null) return false;
    final target = day(date);
    return !target.isBefore(day(start)) && !target.isAfter(day(end));
  }

  static bool isOpen(FlyTask task) =>
      !task.isDeleted && !task.isCompleted && task.completedAt == null;
  static bool isToday(FlyTask task, DateTime date) =>
      isOpen(task) && contains(task, date);
  static bool isOverdue(FlyTask task, DateTime date) =>
      isOpen(task) &&
      task.dueDate != null &&
      day(task.dueDate!).isBefore(day(date));
}
