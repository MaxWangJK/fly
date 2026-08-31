import 'package:drift/drift.dart';

@DataClassName('TaskListRecord')
class TaskLists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFF4267E8))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get sortOrder => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TaskRecord')
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 500)();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('open'))();
  TextColumn get priority => text().withDefault(const Constant('none'))();
  BoolColumn get importance => boolean().withDefault(const Constant(false))();
  BoolColumn get urgency => boolean().withDefault(const Constant(false))();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  BoolColumn get isAllDay => boolean().withDefault(const Constant(true))();
  TextColumn get listId =>
      text().withDefault(const Constant('inbox')).references(TaskLists, #id)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get sortOrder => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get recurrenceRule => text().nullable()();
  DateTimeColumn get recurrenceEndAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TagRecord')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFF667085))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {name},
  ];
}

class TaskTags extends Table {
  TextColumn get taskId =>
      text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {taskId, tagId};
}

@DataClassName('ChecklistItemRecord')
class ChecklistItems extends Table {
  TextColumn get id => text()();
  TextColumn get taskId =>
      text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text().withLength(min: 1, max: 500)();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ReminderRecord')
class Reminders extends Table {
  TextColumn get id => text()();
  TextColumn get taskId =>
      text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get remindAt => dateTime()();
  TextColumn get kind => text().withDefault(const Constant('absolute'))();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
