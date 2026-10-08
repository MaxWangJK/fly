import 'task.dart';

/// Keep open tasks first, then rank priority from high to none.
/// Callers can retain their own ordering within the same priority group.
int compareTaskPriority(FlyTask first, FlyTask second) {
  if (first.isCompleted != second.isCompleted) {
    return first.isCompleted ? 1 : -1;
  }
  return second.priority.index.compareTo(first.priority.index);
}
