import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/checklist_item.dart';
import '../domain/task.dart';
import '../domain/task_list.dart';
import '../domain/task_reminder.dart';
import '../domain/task_repository.dart';

class DriftTaskRepository implements TaskRepository {
  DriftTaskRepository(this._db, {this._uuid = const Uuid()});

  static const sortGap = 1024;

  final AppDatabase _db;
  final Uuid _uuid;

  Stream<List<FlyTask>> _watchWhere(
    Expression<bool> Function($TasksTable row) predicate,
  ) {
    final query = _db.select(_db.tasks)
      ..where((row) => row.deletedAt.isNull() & predicate(row))
      ..orderBy([(row) => OrderingTerm(expression: row.sortOrder)]);
    return query.watch().map(
      (rows) => rows.map(_fromRecord).toList(growable: false),
    );
  }

  @override
  Stream<List<FlyTask>> watchAllTasks() =>
      _watchWhere((row) => const Constant(true));

  @override
  Stream<List<FlyTask>> watchInboxTasks() =>
      _watchWhere((row) => row.listId.equals('inbox'));

  @override
  Stream<List<FlyTask>> watchTodayTasks(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    return _watchWhere(
      (row) =>
          row.dueDate.isBiggerOrEqualValue(start) &
          row.dueDate.isSmallerThanValue(start.add(const Duration(days: 1))),
    );
  }

  @override
  Stream<List<FlyTask>> watchUpcomingTasks(DateTime from) {
    final start = DateTime(
      from.year,
      from.month,
      from.day,
    ).add(const Duration(days: 1));
    return _watchWhere((row) => row.dueDate.isBiggerOrEqualValue(start));
  }

  @override
  Stream<List<FlyTask>> watchTasksForList(String listId) =>
      _watchWhere((row) => row.listId.equals(listId));

  @override
  Stream<List<FlyTask>> watchTasksForRange(DateTime start, DateTime end) =>
      _watchWhere(
        (row) =>
            row.dueDate.isBiggerOrEqualValue(start) &
            row.dueDate.isSmallerThanValue(end),
      );

  @override
  Stream<FlyTask?> watchTask(String id) {
    final query = _db.select(_db.tasks)
      ..where((row) => row.id.equals(id) & row.deletedAt.isNull());
    return query.watchSingleOrNull().map(
      (row) => row == null ? null : _fromRecord(row),
    );
  }

  @override
  Stream<List<FlyTaskList>> watchLists() {
    final query = _db.select(_db.taskLists)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([(row) => OrderingTerm(expression: row.sortOrder)]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => FlyTaskList(
              id: row.id,
              name: row.name,
              colorValue: row.colorValue,
              createdAt: row.createdAt,
              updatedAt: row.updatedAt,
              deletedAt: row.deletedAt,
              sortOrder: row.sortOrder,
              version: row.version,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Stream<List<String>> watchTags(String taskId) {
    final query =
        _db.select(_db.tags).join([
            innerJoin(_db.taskTags, _db.taskTags.tagId.equalsExp(_db.tags.id)),
          ])
          ..where(
            _db.taskTags.taskId.equals(taskId) & _db.tags.deletedAt.isNull(),
          )
          ..orderBy([OrderingTerm(expression: _db.tags.name)]);
    return query.watch().map(
      (rows) => rows
          .map((row) => row.readTable(_db.tags).name)
          .toList(growable: false),
    );
  }

  @override
  Stream<List<FlyChecklistItem>> watchChecklist(String taskId) {
    final query = _db.select(_db.checklistItems)
      ..where((row) => row.taskId.equals(taskId) & row.deletedAt.isNull())
      ..orderBy([(row) => OrderingTerm(expression: row.sortOrder)]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => FlyChecklistItem(
              id: row.id,
              taskId: row.taskId,
              title: row.title,
              isCompleted: row.isCompleted,
              sortOrder: row.sortOrder,
              createdAt: row.createdAt,
              updatedAt: row.updatedAt,
              completedAt: row.completedAt,
              deletedAt: row.deletedAt,
              version: row.version,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Stream<FlyReminder?> watchReminder(String taskId) {
    final query = _db.select(_db.reminders)
      ..where(
        (row) =>
            row.taskId.equals(taskId) &
            row.deletedAt.isNull() &
            row.isEnabled.equals(true),
      )
      ..limit(1);
    return query.watchSingleOrNull().map(
      (row) => row == null
          ? null
          : FlyReminder(
              id: row.id,
              taskId: row.taskId,
              remindAt: row.remindAt,
              isEnabled: row.isEnabled,
            ),
    );
  }

  @override
  Future<FlyTask> createTask({
    required String title,
    String description = '',
    String listId = 'inbox',
    DateTime? dueDate,
    bool importance = false,
    bool urgency = false,
  }) async {
    final value = title.trim();
    if (value.isEmpty) {
      throw ArgumentError.value(title, 'title', 'Task title cannot be empty');
    }
    final maxExpression = _db.tasks.sortOrder.max();
    final maxOrder =
        await (_db.selectOnly(_db.tasks)..addColumns([maxExpression]))
            .map((row) => row.read(maxExpression))
            .getSingle();
    final now = DateTime.now();
    final task = FlyTask(
      id: _uuid.v4(),
      title: value,
      description: description.trim(),
      status: TaskStatus.open,
      priority: TaskPriority.none,
      importance: importance,
      urgency: urgency,
      dueDate: dueDate,
      isAllDay: true,
      listId: listId,
      createdAt: now,
      updatedAt: now,
      sortOrder: (maxOrder ?? 0) + sortGap,
      version: 1,
    );
    await _db.into(_db.tasks).insert(_toCompanion(task));
    return task;
  }

  @override
  Future<void> saveTask(FlyTask task) async {
    final next = task.copyWith(
      updatedAt: DateTime.now(),
      version: task.version + 1,
    );
    await (_db.update(
      _db.tasks,
    )..where((row) => row.id.equals(task.id))).write(_toCompanion(next));
  }

  Future<TaskRecord> _record(String id) =>
      (_db.select(_db.tasks)..where((row) => row.id.equals(id))).getSingle();

  Future<void> _write(String id, TasksCompanion change) async {
    await (_db.update(
      _db.tasks,
    )..where((row) => row.id.equals(id))).write(change);
  }

  Future<void> _touch(String id) async {
    final current = await _record(id);
    await _write(
      id,
      TasksCompanion(
        updatedAt: Value(DateTime.now()),
        version: Value(current.version + 1),
      ),
    );
  }

  @override
  Future<void> setCompleted(String taskId, {required bool completed}) async {
    final current = await _record(taskId);
    final now = DateTime.now();
    await _write(
      taskId,
      TasksCompanion(
        status: Value(completed ? 'completed' : 'open'),
        completedAt: Value(completed ? now : null),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ),
    );
  }

  @override
  Future<void> deleteTask(String taskId) async {
    final current = await _record(taskId);
    final now = DateTime.now();
    await _write(
      taskId,
      TasksCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ),
    );
  }

  @override
  Future<void> moveTaskToList(String taskId, String listId) async {
    final current = await _record(taskId);
    await _write(
      taskId,
      TasksCompanion(
        listId: Value(listId),
        updatedAt: Value(DateTime.now()),
        version: Value(current.version + 1),
      ),
    );
  }

  @override
  Future<void> moveTaskToDate(String taskId, DateTime dueDate) async {
    final current = await _record(taskId);
    await _write(
      taskId,
      TasksCompanion(
        dueDate: Value(dueDate),
        isAllDay: const Value(true),
        updatedAt: Value(DateTime.now()),
        version: Value(current.version + 1),
      ),
    );
  }

  @override
  Future<void> moveTaskToQuadrant(
    String taskId, {
    required bool importance,
    required bool urgency,
  }) async {
    final current = await _record(taskId);
    await _write(
      taskId,
      TasksCompanion(
        importance: Value(importance),
        urgency: Value(urgency),
        updatedAt: Value(DateTime.now()),
        version: Value(current.version + 1),
      ),
    );
  }

  @override
  Future<void> reorderTask(String taskId, List<String> orderedTaskIds) async {
    if (!orderedTaskIds.contains(taskId)) return;
    await _db.transaction(() async {
      for (var index = 0; index < orderedTaskIds.length; index++) {
        final id = orderedTaskIds[index];
        final current = await _record(id);
        await _write(
          id,
          TasksCompanion(
            sortOrder: Value((index + 1) * sortGap),
            updatedAt: Value(DateTime.now()),
            version: Value(current.version + 1),
          ),
        );
      }
    });
  }

  @override
  Future<void> setTags(String taskId, Iterable<String> names) async {
    final values = names
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.delete(
        _db.taskTags,
      )..where((row) => row.taskId.equals(taskId))).go();
      for (final name in values) {
        final existing =
            await (_db.select(_db.tags)
                  ..where(
                    (row) =>
                        row.name.lower().equals(name.toLowerCase()) &
                        row.deletedAt.isNull(),
                  )
                  ..limit(1))
                .getSingleOrNull();
        final id = existing?.id ?? _uuid.v4();
        if (existing == null) {
          await _db
              .into(_db.tags)
              .insert(
                TagsCompanion.insert(
                  id: id,
                  name: name,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        }
        await _db
            .into(_db.taskTags)
            .insert(
              TaskTagsCompanion.insert(taskId: taskId, tagId: id),
              mode: InsertMode.insertOrIgnore,
            );
      }
    });
    await _touch(taskId);
  }

  @override
  Future<void> addChecklistItem(String taskId, String title) async {
    final value = title.trim();
    if (value.isEmpty) return;
    final maxExpression = _db.checklistItems.sortOrder.max();
    final maxOrder =
        await (_db.selectOnly(_db.checklistItems)
              ..addColumns([maxExpression])
              ..where(_db.checklistItems.taskId.equals(taskId)))
            .map((row) => row.read(maxExpression))
            .getSingle();
    final now = DateTime.now();
    await _db
        .into(_db.checklistItems)
        .insert(
          ChecklistItemsCompanion.insert(
            id: _uuid.v4(),
            taskId: taskId,
            title: value,
            sortOrder: (maxOrder ?? 0) + sortGap,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _touch(taskId);
  }

  @override
  Future<void> toggleChecklistItem(
    String itemId, {
    required bool completed,
  }) async {
    final item = await (_db.select(
      _db.checklistItems,
    )..where((row) => row.id.equals(itemId))).getSingle();
    final now = DateTime.now();
    await (_db.update(
      _db.checklistItems,
    )..where((row) => row.id.equals(itemId))).write(
      ChecklistItemsCompanion(
        isCompleted: Value(completed),
        completedAt: Value(completed ? now : null),
        updatedAt: Value(now),
        version: Value(item.version + 1),
      ),
    );
    await _touch(item.taskId);
  }

  @override
  Future<void> deleteChecklistItem(String itemId) async {
    final item = await (_db.select(
      _db.checklistItems,
    )..where((row) => row.id.equals(itemId))).getSingle();
    final now = DateTime.now();
    await (_db.update(
      _db.checklistItems,
    )..where((row) => row.id.equals(itemId))).write(
      ChecklistItemsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(item.version + 1),
      ),
    );
    await _touch(item.taskId);
  }

  @override
  Future<void> setReminder(String taskId, DateTime remindAt) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(
            _db.reminders,
          )..where((row) => row.taskId.equals(taskId) & row.deletedAt.isNull()))
          .write(RemindersCompanion(deletedAt: Value(now)));
      await _db
          .into(_db.reminders)
          .insert(
            RemindersCompanion.insert(
              id: _uuid.v4(),
              taskId: taskId,
              remindAt: remindAt,
              createdAt: now,
              updatedAt: now,
            ),
          );
    });
    await _touch(taskId);
  }

  @override
  Future<void> clearReminder(String taskId) async {
    final now = DateTime.now();
    await (_db.update(_db.reminders)
          ..where((row) => row.taskId.equals(taskId) & row.deletedAt.isNull()))
        .write(RemindersCompanion(deletedAt: Value(now)));
    await _touch(taskId);
  }

  @override
  Future<void> seedDevelopmentData() async {
    final countExpression = _db.tasks.id.count();
    final count =
        await (_db.selectOnly(_db.tasks)..addColumns([countExpression]))
            .map((row) => row.read(countExpression))
            .getSingle();
    if (count != 0) return;
    final today = DateTime.now();
    await createTask(
      title: 'Prepare weekly report',
      dueDate: DateTime(today.year, today.month, today.day),
      importance: true,
      urgency: true,
    );
    await createTask(
      title: 'Follow up client',
      dueDate: DateTime(today.year, today.month, today.day + 1),
      urgency: true,
    );
    await createTask(
      title: 'Book flight',
      dueDate: DateTime(today.year, today.month, today.day + 5),
      importance: true,
    );
    await createTask(title: 'Learn Flutter');
  }

  FlyTask _fromRecord(TaskRecord row) => FlyTask(
    id: row.id,
    title: row.title,
    description: row.description,
    status: TaskStatus.values.byName(row.status),
    priority: TaskPriority.values.byName(row.priority),
    importance: row.importance,
    urgency: row.urgency,
    startDate: row.startDate,
    dueDate: row.dueDate,
    isAllDay: row.isAllDay,
    listId: row.listId,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    completedAt: row.completedAt,
    deletedAt: row.deletedAt,
    sortOrder: row.sortOrder,
    version: row.version,
    recurrenceRule: row.recurrenceRule,
    recurrenceEndAt: row.recurrenceEndAt,
  );

  TasksCompanion _toCompanion(FlyTask task) => TasksCompanion(
    id: Value(task.id),
    title: Value(task.title),
    description: Value(task.description),
    status: Value(task.status.name),
    priority: Value(task.priority.name),
    importance: Value(task.importance),
    urgency: Value(task.urgency),
    startDate: Value(task.startDate),
    dueDate: Value(task.dueDate),
    isAllDay: Value(task.isAllDay),
    listId: Value(task.listId),
    createdAt: Value(task.createdAt),
    updatedAt: Value(task.updatedAt),
    completedAt: Value(task.completedAt),
    deletedAt: Value(task.deletedAt),
    sortOrder: Value(task.sortOrder),
    version: Value(task.version),
    recurrenceRule: Value(task.recurrenceRule),
    recurrenceEndAt: Value(task.recurrenceEndAt),
  );
}
