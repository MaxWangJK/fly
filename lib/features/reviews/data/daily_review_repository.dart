import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

class ReviewHistoryEntry {
  const ReviewHistoryEntry({required this.day, required this.answers});

  final String day;
  final Map<String, String> answers;
}

class DailyReviewRepository {
  const DailyReviewRepository(
    this.db, {
    this.fields = classicFields,
    this.historyFields,
  });
  final AppDatabase db;
  static const classicFields = {
    'q1',
    'q2',
    'q3',
    'q4',
    'q5',
    'q6',
    'q7',
    'q8',
    'q9',
    'q10',
    'q11',
  };
  final Set<String> fields;
  final Set<String>? historyFields;
  Map<String, String> _answers(String json, {bool history = false}) =>
      Map<String, String>.fromEntries(
        Map<String, String>.from(jsonDecode(json) as Map).entries.where(
          (entry) =>
              (history ? historyFields ?? fields : fields).contains(entry.key),
        ),
      );
  static String key(DateTime date) {
    final d = date.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static DateTime date(String key) {
    final parsed = DateTime.parse(key);
    if (DailyReviewRepository.key(parsed) != key) {
      throw ArgumentError('Invalid review day');
    }
    return parsed;
  }

  Future<Map<String, String>> answers(String day) async {
    date(day);
    final row = await (db.select(
      db.dailyReviews,
    )..where((r) => r.dayKey.equals(day))).getSingleOrNull();
    if (row == null) return {};
    return _answers(row.answersJson);
  }

  Stream<Map<String, String>> watchAnswers(String day) {
    date(day);
    return (db.select(
      db.dailyReviews,
    )..where((r) => r.dayKey.equals(day))).watchSingleOrNull().map(
      (row) => row == null ? <String, String>{} : _answers(row.answersJson),
    );
  }

  Future<void> saveAnswer(String day, String field, String value) =>
      db.transaction(() async {
        date(day);
        if (!fields.contains(field) || value.length > 20000) {
          throw ArgumentError('Invalid review answer');
        }
        final row = await (db.select(
          db.dailyReviews,
        )..where((r) => r.dayKey.equals(day))).getSingleOrNull();
        final values = row == null
            ? <String, String>{}
            : Map<String, String>.from(jsonDecode(row.answersJson) as Map);
        values[field] = value;
        final now = DateTime.now();
        await db
            .into(db.dailyReviews)
            .insertOnConflictUpdate(
              DailyReviewsCompanion.insert(
                dayKey: day,
                answersJson: Value(jsonEncode(values)),
                revision: Value((row?.revision ?? 0) + 1),
                createdAt: row?.createdAt ?? now,
                updatedAt: now,
              ),
            );
      });

  Stream<List<String>> watchRecordedDays() => db
      .select(db.dailyReviews)
      .watch()
      .map(
        (rows) =>
            rows
                .where((row) {
                  final values = _answers(row.answersJson, history: true);
                  return values.values.any((value) => value.trim().isNotEmpty);
                })
                .map((row) => row.dayKey)
                .toList()
              ..sort(),
      );

  /// Only meaningful answers are projected into history. Empty fields never
  /// become visible cards, even when an older saved row still contains them.
  Stream<List<ReviewHistoryEntry>> watchHistory() {
    final query = db.select(db.dailyReviews)
      ..orderBy([(row) => OrderingTerm.desc(row.dayKey)]);
    return query.watch().map((rows) {
      final history = <ReviewHistoryEntry>[];
      for (final row in rows) {
        final values = _answers(row.answersJson, history: true);
        final visible = Map<String, String>.fromEntries(
          values.entries.where((entry) => entry.value.trim().isNotEmpty),
        );
        if (visible.isNotEmpty) {
          history.add(ReviewHistoryEntry(day: row.dayKey, answers: visible));
        }
      }
      return history;
    });
  }

  Future<Map<String, int>> summary(String day) async {
    final start = date(day);
    final end = DateTime(start.year, start.month, start.day + 1);
    final s = start.millisecondsSinceEpoch ~/ 1000;
    final e = end.millisecondsSinceEpoch ~/ 1000;
    Future<int> count(String sql) async =>
        (await db
                .customSelect(sql, variables: [Variable(s), Variable(e)])
                .getSingle())
            .read<int>('n');
    return {
      'completed': await count(
        'SELECT count(*) n FROM tasks WHERE deleted_at IS NULL AND completed_at >= ? AND completed_at < ?',
      ),
      'open': await count(
        "SELECT count(*) n FROM tasks WHERE deleted_at IS NULL AND completed_at IS NULL AND status <> 'completed' AND coalesce(start_date,due_date) < ?2 AND coalesce(due_date,start_date) >= ?1",
      ),
      'overdue': await count(
        "SELECT count(*) n FROM tasks WHERE deleted_at IS NULL AND completed_at IS NULL AND status <> 'completed' AND due_date < ?1 AND ?2 > ?1",
      ),
      'followed': await count(
        'SELECT count(DISTINCT f.customer_id) n FROM customer_follow_ups f JOIN customers c ON c.id=f.customer_id WHERE f.deleted_at IS NULL AND c.deleted_at IS NULL AND f.followed_up_at >= ? AND f.followed_up_at < ?',
      ),
      'customers': await count(
        'SELECT count(*) n FROM customers WHERE deleted_at IS NULL AND created_at >= ? AND created_at < ?',
      ),
      'orders': await count(
        'SELECT count(*) n FROM orders WHERE deleted_at IS NULL AND updated_at >= ? AND updated_at < ?',
      ),
    };
  }
}
