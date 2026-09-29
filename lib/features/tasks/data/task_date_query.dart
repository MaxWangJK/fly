import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/task_date_range.dart';

/// Local calendar-day intersection, with single-ended dates treated as one day.
/// A half-open day avoids precision assumptions and handles DST day lengths.
Expression<bool> taskTodayPredicate($TasksTable row, DateTime date) {
  final start = TaskDateRange.day(date);
  final next = DateTime(start.year, start.month, start.day + 1);
  final startsToday =
      row.startDate.isBiggerOrEqualValue(start) &
      row.startDate.isSmallerThanValue(next);
  final endsToday =
      row.dueDate.isBiggerOrEqualValue(start) &
      row.dueDate.isSmallerThanValue(next);
  return row.deletedAt.isNull() &
      row.completedAt.isNull() &
      row.status.equals('open') &
      ((row.startDate.isNotNull() &
              row.dueDate.isNotNull() &
              row.startDate.isSmallerThanValue(next) &
              row.dueDate.isBiggerOrEqualValue(start)) |
          (row.dueDate.isNull() & startsToday) |
          (row.startDate.isNull() & endsToday));
}
