import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../tasks/data/drift_task_repository.dart';
import '../domain/review_program.dart';
import 'daily_review_repository.dart';

class ReviewProgramRepository {
  const ReviewProgramRepository(this.db);
  final AppDatabase db;
  static const preferenceKey = 'reviews.program.v1';

  Future<ReviewProgram?> load() async {
    final row = await (db.select(
      db.appSettings,
    )..where((r) => r.key.equals(preferenceKey))).getSingleOrNull();
    return ReviewProgram.values.where((p) => p.name == row?.value).firstOrNull;
  }

  Future<void> select(ReviewProgram program) => db
      .into(db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: preferenceKey,
          value: program.name,
          updatedAt: DateTime.now(),
        ),
      );
}

/// A stable ID also coalesces offline creation on different devices. The task
/// and reference commit together. Existing tasks, including trash, stay intact.
class GuidedReviewActions {
  const GuidedReviewActions(this.db);
  final AppDatabase db;
  Future<String> createNextTask(String day) => db.transaction(() async {
    final repository = DailyReviewRepository(db, fields: GuidedReview.fields);
    final answers = await repository.answers(day);
    final existing = answers[GuidedReview.taskId];
    if (existing != null && existing.isNotEmpty) return existing;
    final experiment = answers[GuidedReview.experiment]?.trim() ?? '';
    if (experiment.isEmpty) throw StateError('Write an experiment first');
    final date = DailyReviewRepository.date(day);
    final firstLine = experiment.split('\n').first;
    final title = String.fromCharCodes(firstLine.runes.take(140));
    final signal = answers[GuidedReview.signal]?.trim() ?? '';
    final id = const Uuid().v5(
      '4586716c-8ec7-43eb-b81a-4e104fb68683',
      'experiment:$day',
    );
    final task = await (db.select(
      db.tasks,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (task == null) {
      final max = db.tasks.sortOrder.max();
      final order = await (db.selectOnly(
        db.tasks,
      )..addColumns([max])).map((r) => r.read(max)).getSingle();
      final now = DateTime.now();
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: id,
              title: title,
              description: Value('$experiment\n\n$signal\n\nFly · $day'),
              dueDate: Value(DateTime(date.year, date.month, date.day + 1)),
              sortOrder: (order ?? 0) + DriftTaskRepository.sortGap,
              createdAt: now,
              updatedAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    await repository.saveAnswer(day, GuidedReview.taskId, id);
    return id;
  });
}
