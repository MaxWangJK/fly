import 'package:fly/features/tasks/domain/task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FlyTask task({required bool important, required bool urgent}) {
    final now = DateTime(2026, 8, 31);
    return FlyTask(
      id: 'task',
      title: 'Classify me',
      description: '',
      status: TaskStatus.open,
      priority: TaskPriority.none,
      importance: important,
      urgency: urgent,
      isAllDay: true,
      listId: 'inbox',
      createdAt: now,
      updatedAt: now,
      sortOrder: 1024,
      version: 1,
    );
  }

  test('maps importance and urgency to all four quadrants', () {
    expect(
      task(important: true, urgent: true).quadrant,
      MatrixQuadrant.importantUrgent,
    );
    expect(
      task(important: true, urgent: false).quadrant,
      MatrixQuadrant.importantNotUrgent,
    );
    expect(
      task(important: false, urgent: true).quadrant,
      MatrixQuadrant.notImportantUrgent,
    );
    expect(
      task(important: false, urgent: false).quadrant,
      MatrixQuadrant.notImportantNotUrgent,
    );
  });

  test('copyWith can explicitly clear nullable dates', () {
    final source = task(
      important: false,
      urgent: false,
    ).copyWith(dueDate: DateTime(2026, 9, 1));
    expect(source.copyWith(dueDate: null).dueDate, isNull);
  });
}
