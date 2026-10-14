import 'dart:async';

import 'package:drift/native.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/features/tasks/domain/task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftTaskRepository repository;
  final day = DateTime(2026, 10, 8);
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.ensureBuiltInData();
    repository = DriftTaskRepository(database);
  });
  tearDown(() => database.close());
  Future<FlyTask> create(
    String title,
    int minute,
    TaskPriority priority,
  ) async {
    final task = await repository.createTask(title: title, dueDate: day);
    final value = task.copyWith(
      createdAt: day.add(Duration(minutes: minute)),
      priority: priority,
    );
    await repository.saveTask(value);
    return value;
  }

  test('task lists show newest-created first across priorities and completion states', () async {
    final olderHigh = await create('Older high', 1, TaskPriority.high);
    final newerLow = await create('Newer low', 2, TaskPriority.low);
    final newestCompleted = await create(
      'Newest completed',
      3,
      TaskPriority.none,
    );
    await repository.setCompleted(newestCompleted.id, completed: true);
    for (final stream in [
      repository.watchAllTasks(),
      repository.watchInboxTasks(),
      repository.watchTasksForList('inbox'),
      repository.watchTasksForRange(day, day.add(const Duration(days: 1))),
      repository.watchUpcomingTasks(day.subtract(const Duration(days: 1))),
    ]) {
      expect((await stream.first).map((t) => t.id), [
        newestCompleted.id,
        newerLow.id,
        olderHigh.id,
      ]);
    }
    expect((await repository.watchTodayTasks(day).first).map((t) => t.id), [
      newerLow.id,
      olderHigh.id,
    ]);
  });
  test(
    'editing older tasks does not move them ahead of newly created tasks',
    () async {
      final old = await create('Old', 1, TaskPriority.none);
      final recent = await create('Recent', 2, TaskPriority.low);
      final updates = StreamIterator(repository.watchInboxTasks());
      try {
        expect(await updates.moveNext(), isTrue);
        expect(updates.current.map((t) => t.id), [recent.id, old.id]);
        await repository.saveTask(
          old.copyWith(title: 'Edited old', priority: TaskPriority.high),
        );
        expect(await updates.moveNext(), isTrue);
        expect(updates.current.map((t) => t.id), [recent.id, old.id]);
        expect(updates.current.last.title, 'Edited old');
      } finally {
        await updates.cancel();
      }
    },
  );
  test('legacy manual order remains stored without changing automatic creation order', () async {
    final old = await create('Old', 1, TaskPriority.high);
    final recent = await create('Recent', 2, TaskPriority.high);
    await repository.reorderTask(old.id, [old.id, recent.id]);
    expect((await repository.watchInboxTasks().first).map((t) => t.id), [
      recent.id,
      old.id,
    ]);
    expect(
      (await repository.watchTask(old.id).first)!.sortOrder,
      lessThan((await repository.watchTask(recent.id).first)!.sortOrder),
    );
  });
}
