import 'task.dart';

int compareTaskCreatedNewestFirst(FlyTask first, FlyTask second) {
  final created = second.createdAt.compareTo(first.createdAt);
  return created != 0 ? created : second.id.compareTo(first.id);
}

/// Keep open tasks first, then rank priority from high to none.
/// Callers can retain their own ordering within the same priority group.
int compareTaskPriority(FlyTask first, FlyTask second) {
  if (first.isCompleted != second.isCompleted) {
    return first.isCompleted ? 1 : -1;
  }
  return second.priority.index.compareTo(first.priority.index);
}
