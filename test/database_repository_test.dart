import 'package:drift/native.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/features/tasks/domain/task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftTaskRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.ensureBuiltInData();
    repository = DriftTaskRepository(database);
  });

  tearDown(() => database.close());

  test('built-in inbox is available', () async {
    final lists = await repository.watchLists().first;
    expect(lists.single.id, 'inbox');
    expect(lists.single.name, 'Inbox');
  });

  test('task CRUD is persisted and soft deletion hides the task', () async {
    final created = await repository.createTask(title: 'Write tests');
    expect((await repository.watchInboxTasks().first).single.id, created.id);

    await repository.saveTask(
      created.copyWith(
        title: 'Write durable tests',
        priority: TaskPriority.high,
      ),
    );
    final saved = await repository.watchTask(created.id).first;
    expect(saved?.title, 'Write durable tests');
    expect(saved?.priority, TaskPriority.high);
    expect(saved?.version, 2);

    await repository.setCompleted(created.id, completed: true);
    expect((await repository.watchTask(created.id).first)?.isCompleted, isTrue);

    await repository.deleteTask(created.id);
    expect(await repository.watchTask(created.id).first, isNull);
    expect(await repository.watchAllTasks().first, isEmpty);
  });

  test('calendar and matrix moves update the same task record', () async {
    final created = await repository.createTask(title: 'Move me');
    final date = DateTime(2026, 9, 14);

    await repository.moveTaskToDate(created.id, date);
    await repository.moveTaskToQuadrant(
      created.id,
      importance: true,
      urgency: false,
    );

    final month = await repository
        .watchTasksForRange(DateTime(2026, 9), DateTime(2026, 10))
        .first;
    expect(month.single.id, created.id);
    expect(month.single.dueDate, date);
    expect(month.single.quadrant, MatrixQuadrant.importantNotUrgent);
  });

  test('tags, checklist and reminders round-trip through SQLite', () async {
    final task = await repository.createTask(title: 'Rich details');
    await repository.setTags(task.id, ['focus', 'desktop']);
    await repository.addChecklistItem(task.id, 'First step');
    final reminderAt = DateTime(2026, 9, 1, 9);
    await repository.setReminder(task.id, reminderAt);

    expect(await repository.watchTags(task.id).first, ['desktop', 'focus']);
    final checklist = await repository.watchChecklist(task.id).first;
    expect(checklist.single.title, 'First step');

    await repository.toggleChecklistItem(checklist.single.id, completed: true);
    expect(
      (await repository.watchChecklist(task.id).first).single.isCompleted,
      isTrue,
    );
    expect(
      (await repository.watchReminder(task.id).first)?.remindAt,
      reminderAt,
    );

    await repository.clearReminder(task.id);
    expect(await repository.watchReminder(task.id).first, isNull);
  });

  test('reorder persists the requested task sequence', () async {
    final first = await repository.createTask(title: 'First');
    final second = await repository.createTask(title: 'Second');
    final third = await repository.createTask(title: 'Third');

    await repository.reorderTask(third.id, [third.id, first.id, second.id]);

    expect((await repository.watchAllTasks().first).map((task) => task.id), [
      third.id,
      first.id,
      second.id,
    ]);
  });

  test('custom list CRUD moves tasks back to inbox on deletion', () async {
    final list = await repository.createList('Work');
    final task = await repository.createTask(
      title: 'List task',
      listId: list.id,
    );

    await repository.renameList(list.id, 'Client work');
    expect(
      (await repository.watchLists().first)
          .singleWhere((value) => value.id == list.id)
          .name,
      'Client work',
    );

    await repository.deleteList(list.id);
    expect(
      (await repository.watchLists().first).where(
        (value) => value.id == list.id,
      ),
      isEmpty,
    );
    expect((await repository.watchInboxTasks().first).single.id, task.id);
  });

  test('completed tasks are visible and sorted after open tasks', () async {
    final completed = await repository.createTask(title: 'Completed');
    final open = await repository.createTask(title: 'Open');
    await repository.setCompleted(completed.id, completed: true);

    final tasks = await repository.watchAllTasks().first;
    expect(tasks.map((task) => task.id), [open.id, completed.id]);
    expect(tasks.last.isCompleted, isTrue);
  });

  test('trash supports reactive restore and permanent deletion', () async {
    final task = await repository.createTask(title: 'Recoverable task');

    await repository.deleteTask(task.id);
    expect((await repository.watchDeletedTasks().first).single.id, task.id);
    expect(await repository.watchTask(task.id).first, isNull);

    await repository.restoreTask(task.id);
    expect(await repository.watchDeletedTasks().first, isEmpty);
    expect((await repository.watchTask(task.id).first)?.id, task.id);

    await repository.deleteTask(task.id);
    await repository.deleteTaskPermanently(task.id);
    expect(await repository.watchDeletedTasks().first, isEmpty);
  });
}
