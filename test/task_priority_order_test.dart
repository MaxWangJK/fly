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

  Future<FlyTask> create(String title, TaskPriority priority) async {
    final task = await repository.createTask(title: title, dueDate: day);
    await repository.saveTask(task.copyWith(priority: priority));
    return task;
  }

  test(
    'all task collections rank priority and keep completed tasks last',
    () async {
      final none = await create('None', TaskPriority.none);
      final low = await create('Low', TaskPriority.low);
      final medium = await create('Medium', TaskPriority.medium);
      final high = await create('High', TaskPriority.high);
      final completed = await create('Completed high', TaskPriority.high);
      await repository.setCompleted(completed.id, completed: true);
      final expected = [high.id, medium.id, low.id, none.id, completed.id];
      for (final stream in [
        repository.watchAllTasks(),
        repository.watchInboxTasks(),
        repository.watchTasksForList('inbox'),
        repository.watchTasksForRange(day, day.add(const Duration(days: 1))),
        repository.watchUpcomingTasks(day.subtract(const Duration(days: 1))),
      ]) {
        expect((await stream.first).map((task) => task.id), expected);
      }
      // Today intentionally excludes completed tasks.
      expect(
        (await repository.watchTodayTasks(day).first).map((task) => task.id),
        [high.id, medium.id, low.id, none.id],
      );
    },
  );

  test(
    'changing priority updates the live list without reopening it',
    () async {
      final first = await create('First', TaskPriority.low);
      final second = await create('Second', TaskPriority.medium);
      final updates = StreamIterator(repository.watchInboxTasks());
      try {
        expect(await updates.moveNext(), isTrue);
        expect(updates.current.map((task) => task.id), [second.id, first.id]);
        await repository.saveTask(first.copyWith(priority: TaskPriority.high));
        expect(await updates.moveNext(), isTrue);
        expect(updates.current.map((task) => task.id), [first.id, second.id]);
        final saved = (await repository.watchTask(first.id).first)!;
        await repository.saveTask(saved.copyWith(priority: TaskPriority.none));
        expect(await updates.moveNext(), isTrue);
        expect(updates.current.map((task) => task.id), [second.id, first.id]);
      } finally {
        await updates.cancel();
      }
    },
  );

  test('manual reorder only changes order within the same priority', () async {
    final low = await create('Low', TaskPriority.low);
    final firstHigh = await create('First high', TaskPriority.high);
    final secondHigh = await create('Second high', TaskPriority.high);
    await repository.reorderTask(secondHigh.id, [
      low.id,
      secondHigh.id,
      firstHigh.id,
    ]);
    expect((await repository.watchInboxTasks().first).map((task) => task.id), [
      secondHigh.id,
      firstHigh.id,
      low.id,
    ]);
    await repository.reorderTask(low.id, [low.id, secondHigh.id, firstHigh.id]);
    expect((await repository.watchInboxTasks().first).map((task) => task.id), [
      secondHigh.id,
      firstHigh.id,
      low.id,
    ]);
    expect(
      (await repository.watchTask(low.id).first)!.priority,
      TaskPriority.low,
    );
  });
}
