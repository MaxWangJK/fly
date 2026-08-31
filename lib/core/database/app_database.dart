import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [TaskLists, Tasks, Tags, TaskTags, ChecklistItems, Reminders],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'fly',
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async {
          await migrator.createAll();
          await customStatement(
            'CREATE INDEX idx_tasks_due_active '
            'ON tasks(due_date, deleted_at, status)',
          );
          await customStatement(
            'CREATE INDEX idx_tasks_list_sort_active '
            'ON tasks(list_id, deleted_at, status, sort_order)',
          );
          await customStatement(
            'CREATE INDEX idx_tasks_matrix_active '
            'ON tasks(importance, urgency, deleted_at, status)',
          );
          await customStatement(
            'CREATE INDEX idx_checklist_task_sort '
            'ON checklist_items(task_id, deleted_at, sort_order)',
          );
          await customStatement(
            'CREATE INDEX idx_reminders_task_active '
            'ON reminders(task_id, deleted_at, remind_at)',
          );
        },
        beforeOpen: (_) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA journal_mode = WAL');
        },
      );

  Future<void> ensureBuiltInData() async {
    final now = DateTime.now();
    await into(taskLists).insertOnConflictUpdate(
      TaskListsCompanion.insert(
        id: 'inbox',
        name: 'Inbox',
        createdAt: now,
        updatedAt: now,
        sortOrder: 1024,
      ),
    );
  }
}
