import 'package:flutter_test/flutter_test.dart';
import 'package:fly/features/calendar/presentation/mobile_calendar_workspace.dart';
import 'package:fly/features/tasks/domain/task.dart';

void main() {
  final today = DateTime(2026, 10, 13);
  FlyTask event({DateTime? start, DateTime? end, bool allDay = false}) =>
      FlyTask(
        id: 'event',
        title: 'Event',
        description: '',
        status: TaskStatus.open,
        priority: TaskPriority.none,
        importance: false,
        urgency: false,
        isAllDay: allDay,
        listId: 'inbox',
        createdAt: today,
        updatedAt: today,
        sortOrder: 0,
        version: 1,
        startDate: start,
        dueDate: end,
      );
  test('timed event ending at midnight does not appear the next day', () {
    final task = event(
      start: DateTime(2026, 10, 13, 23),
      end: DateTime(2026, 10, 14),
    );
    expect(mobileTaskOccursOnDay(task, today), isTrue);
    expect(mobileTaskOccursOnDay(task, DateTime(2026, 10, 14)), isFalse);
  });
  test('timed event crossing midnight appears on both days', () {
    final task = event(
      start: DateTime(2026, 10, 13, 23),
      end: DateTime(2026, 10, 14, 1),
    );
    expect(mobileTaskOccursOnDay(task, today), isTrue);
    expect(mobileTaskOccursOnDay(task, DateTime(2026, 10, 14)), isTrue);
  });
  test('all-day range includes the final day and ignores deleted tasks', () {
    final task = event(start: today, end: DateTime(2026, 10, 15), allDay: true);
    expect(mobileTaskOccursOnDay(task, DateTime(2026, 10, 15)), isTrue);
    expect(mobileTaskOccursOnDay(task, DateTime(2026, 10, 16)), isFalse);
    expect(
      mobileTaskOccursOnDay(task.copyWith(deletedAt: today), today),
      isFalse,
    );
  });
  test(
    'single timed endpoint gets a one-hour slot; undated tasks stay out',
    () {
      expect(mobileTaskOccursOnDay(event(start: today), today), isTrue);
      expect(mobileTaskOccursOnDay(event(end: today), today), isTrue);
      expect(mobileTaskOccursOnDay(event(), today), isFalse);
    },
  );
}
