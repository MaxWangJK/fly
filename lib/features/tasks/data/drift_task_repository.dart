import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/checklist_item.dart';
import '../domain/task.dart';
import '../domain/task_date_range.dart';
import '../domain/task_list.dart';
import '../domain/task_reminder.dart';
import '../domain/task_repository.dart';
import 'task_date_query.dart';

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
      ..orderBy([
        (row) => OrderingTerm(expression: row.status.equals('completed')),
        (row) => OrderingTerm(expression: row.sortOrder),
      ]);
    return query.watch().map(
      (rows) => rows.map(_fromRecord).toList(growable: false),
    );
  }

  @override
  Stream<List<FlyTask>> watchAllTasks() =>
      _watchWhere((row) => const Constant(true));

  @override
  Stream<List<FlyTask>> watchCompletedTasks() =>
      _watchWhere((row) => row.status.equals('completed'));

  @override
  Stream<List<FlyTask>> watchDeletedTasks() {
    final query = _db.select(_db.tasks)
      ..where((row) => row.deletedAt.isNotNull())
      ..orderBy([
        (row) =>
            OrderingTerm(expression: row.deletedAt, mode: OrderingMode.desc),
      ]);
    return query.watch().map(
      (rows) => rows.map(_fromRecord).toList(growable: false),
    );
  }

  @override
  Stream<List<FlyTask>> watchInboxTasks() =>
      _watchWhere((row) => row.listId.equals('inbox'));

  @override
  Stream<List<FlyTask>> watchTodayTasks(DateTime day) {
    return _watchWhere((row) => taskTodayPredicate(row, day));
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
            (row.startDate.isNotNull() &
                row.dueDate.isNotNull() &
                row.startDate.isSmallerThanValue(end) &
                row.dueDate.isBiggerOrEqualValue(start)) |
            (row.startDate.isNull() &
                row.dueDate.isBiggerOrEqualValue(start) &
                row.dueDate.isSmallerThanValue(end)) |
            (row.dueDate.isNull() &
                row.startDate.isBiggerOrEqualValue(start) &
                row.startDate.isSmallerThanValue(end)),
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
  Future<FlyTaskList> createList(
    String name, {
    int colorValue = 0xFF4D6BD8,
  }) async {
    final value = name.trim();
    if (value.isEmpty) {
      throw ArgumentError.value(name, 'name', 'List name cannot be empty');
    }
    final maxExpression = _db.taskLists.sortOrder.max();
    final maxOrder =
        await (_db.selectOnly(_db.taskLists)..addColumns([maxExpression]))
            .map((row) => row.read(maxExpression))
            .getSingle();
    final now = DateTime.now();
    final list = FlyTaskList(
      id: _uuid.v4(),
      name: value,
      colorValue: colorValue,
      createdAt: now,
      updatedAt: now,
      sortOrder: (maxOrder ?? 0) + sortGap,
      version: 1,
    );
    await _db
        .into(_db.taskLists)
        .insert(
          TaskListsCompanion.insert(
            id: list.id,
            name: list.name,
            colorValue: Value(list.colorValue),
            createdAt: list.createdAt,
            updatedAt: list.updatedAt,
            sortOrder: list.sortOrder,
          ),
        );
    return list;
  }

  @override
  Future<void> renameList(String listId, String name) async {
    final value = name.trim();
    if (listId == 'inbox' || value.isEmpty) return;
    final current = await (_db.select(
      _db.taskLists,
    )..where((row) => row.id.equals(listId))).getSingle();
    await (_db.update(
      _db.taskLists,
    )..where((row) => row.id.equals(listId))).write(
      TaskListsCompanion(
        name: Value(value),
        updatedAt: Value(DateTime.now()),
        version: Value(current.version + 1),
      ),
    );
  }

  @override
  Future<void> deleteList(String listId) async {
    if (listId == 'inbox') return;
    final current = await (_db.select(
      _db.taskLists,
    )..where((row) => row.id.equals(listId))).getSingle();
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(
            _db.tasks,
          )..where((row) => row.listId.equals(listId) & row.deletedAt.isNull()))
          .write(TasksCompanion(listId: const Value('inbox')));
      await (_db.update(
        _db.taskLists,
      )..where((row) => row.id.equals(listId))).write(
        TaskListsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          version: Value(current.version + 1),
        ),
      );
    });
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
  Future<void> restoreTask(String taskId) async {
    final current = await _record(taskId);
    final now = DateTime.now();
    await _write(
      taskId,
      TasksCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ),
    );
  }

  @override
  Future<void> deleteTaskPermanently(String taskId) async {
    await (_db.delete(_db.tasks)..where((row) => row.id.equals(taskId))).go();
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
  Future<void> postponeOverdueTasks(List<String> ids, DateTime today) =>
      _db.transaction(() async {
        for (final id in ids.toSet()) {
          final record = await (_db.select(
            _db.tasks,
          )..where((r) => r.id.equals(id))).getSingleOrNull();
          if (record != null &&
              TaskDateRange.isOverdue(_fromRecord(record), today)) {
            await _write(
              id,
              TasksCompanion(
                dueDate: Value(TaskDateRange.day(today)),
                updatedAt: Value(DateTime.now()),
                version: Value(record.version + 1),
              ),
            );
          }
        }
      });

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
    final index = orderedTaskIds.indexOf(taskId);
    if (index < 0) return;

    final previous = index == 0
        ? null
        : await _record(orderedTaskIds[index - 1]);
    final next = index == orderedTaskIds.length - 1
        ? null
        : await _record(orderedTaskIds[index + 1]);
    final previousOrder = previous?.sortOrder;
    final nextOrder = next?.sortOrder;

    final int order;
    if (previousOrder == null && nextOrder == null) {
      order = sortGap;
    } else if (previousOrder == null) {
      order = nextOrder! - sortGap;
    } else if (nextOrder == null) {
      order = previousOrder + sortGap;
    } else if (nextOrder - previousOrder > 1) {
      order = previousOrder + ((nextOrder - previousOrder) ~/ 2);
    } else {
      await _rebalance(orderedTaskIds);
      return;
    }

    final current = await _record(taskId);
    await _write(
      taskId,
      TasksCompanion(
        sortOrder: Value(order),
        updatedAt: Value(DateTime.now()),
        version: Value(current.version + 1),
      ),
    );
  }

  Future<void> _rebalance(List<String> orderedTaskIds) {
    return _db.transaction(() async {
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
                        row.scope.equals('task') &
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
                  scope: const Value('task'),
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
  Future<void> seedDevelopmentData({DateTime? today}) async {
    final now = today ?? DateTime.now();
    final lists = <(String, String, int, int)>[
      ('welcome', '欢迎', 0xFF4D6BD8, 1024),
      ('work', '事务推进', 0xFF4D6BD8, 2048),
      ('personal', '生活随记', 0xFF7C5CFC, 3072),
      ('shopping', '采购备办', 0xFFE69A37, 4096),
      ('study', '成长积累', 0xFF3A86D8, 5120),
      ('fitness', '活力习惯', 0xFF3A9B68, 6144),
      ('wish', '未来愿景', 0xFFE05A67, 7168),
    ];
    for (final (id, name, color, order) in lists) {
      await _db
          .into(_db.taskLists)
          .insert(
            TaskListsCompanion.insert(
              id: id,
              name: name,
              colorValue: Value(color),
              createdAt: now,
              updatedAt: now,
              sortOrder: order,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }

    final seeded =
        await (_db.select(_db.tasks)
              ..where((row) => row.title.equals('确认菲律宾客户首柜数量'))
              ..limit(1))
            .getSingleOrNull();
    if (seeded != null) return;

    final day = DateTime(now.year, now.month, now.day);
    final samples =
        <
          ({
            String title,
            String description,
            String listId,
            int offset,
            bool importance,
            bool urgency,
          })
        >[
          (
            title: '确认菲律宾客户首柜数量',
            description: '核对 WPC 格栅与门板的装柜比例。',
            listId: 'work',
            offset: 0,
            importance: true,
            urgency: true,
          ),
          (
            title: '更新 WPC 报价单',
            description: '更新海运费与包装费用。',
            listId: 'work',
            offset: 0,
            importance: true,
            urgency: false,
          ),
          (
            title: '确认样品快递单号',
            description: '把 DHL 单号发送给 David。',
            listId: 'work',
            offset: 0,
            importance: false,
            urgency: true,
          ),
          (
            title: '准备 Ahmed 的 PI',
            description: '确认颜色、数量和付款条款。',
            listId: 'work',
            offset: 1,
            importance: true,
            urgency: false,
          ),
          (
            title: '安排越南客户视频会议',
            description: '演示 UV Marble Sheet 新花色。',
            listId: 'work',
            offset: 1,
            importance: false,
            urgency: false,
          ),
          (
            title: '跟工厂确认 WPC Door 交期',
            description: '确认原料到厂时间和首检日期。',
            listId: 'work',
            offset: 3,
            importance: false,
            urgency: true,
          ),
          (
            title: '整理 Saudi Arabia 清关资料',
            description: '核对 CI、PL 和 CO 信息。',
            listId: 'work',
            offset: 5,
            importance: true,
            urgency: false,
          ),
          (
            title: '复核 Manila 订单利润',
            description: '补录港杂费和拖车费。',
            listId: 'work',
            offset: 7,
            importance: false,
            urgency: false,
          ),
          (
            title: '准备下周开发客户名单',
            description: '筛选 Philippines 与 Thailand 建材进口商。',
            listId: 'work',
            offset: 10,
            importance: true,
            urgency: false,
          ),
          (
            title: '归档已发货订单文件',
            description: '整理 PI、CI、PL、CO 与转账凭证。',
            listId: 'work',
            offset: 14,
            importance: false,
            urgency: false,
          ),
          (
            title: '补发 Ali 的包装照片',
            description: '该客户昨天应跟进，今天优先处理。',
            listId: 'work',
            offset: -1,
            importance: true,
            urgency: true,
          ),
        ];

    for (final sample in samples) {
      await createTask(
        title: sample.title,
        description: sample.description,
        listId: sample.listId,
        dueDate: day.add(Duration(days: sample.offset)),
        importance: sample.importance,
        urgency: sample.urgency,
      );
    }
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
