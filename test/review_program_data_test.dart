import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/reviews/data/daily_review_repository.dart';
import 'package:fly/features/reviews/data/review_program_repository.dart';
import 'package:fly/features/reviews/domain/review_program.dart';
import 'package:fly/features/reviews/presentation/review_providers.dart';
import 'package:fly/features/sync/domain/automatic_sync_merge.dart';

void main() {
  test('programs preserve each other, clear independently and omit metadata-only history', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final basic = DailyReviewRepository(db);
    final guided = DailyReviewRepository(
      db,
      fields: GuidedReview.fields,
      historyFields: GuidedReview.visibleFields,
    );
    try {
      await basic.saveAnswer('2026-11-01', 'q1', 'Original basic answer');
      await guided.saveAnswer(
        '2026-11-01',
        GuidedReview.progress,
        'A real change',
      );
      await basic.saveAnswer('2026-11-01', 'q2', 'Another basic answer');
      expect(await basic.answers('2026-11-01'), {
        'q1': 'Original basic answer',
        'q2': 'Another basic answer',
      });
      expect(await guided.answers('2026-11-01'), {
        GuidedReview.progress: 'A real change',
      });
      await guided.saveAnswer('2026-10-31', GuidedReview.closed, 'true');
      expect(await basic.watchRecordedDays().first, ['2026-11-01']);
      expect(await guided.watchRecordedDays().first, ['2026-11-01']);
      await guided.saveAnswer('2026-11-01', GuidedReview.progress, '');
      expect(await guided.watchHistory().first, isEmpty);
      expect(
        (await basic.watchHistory().first).single.answers['q1'],
        'Original basic answer',
      );
      await expectLater(
        basic.saveAnswer('2026-11-01', GuidedReview.progress, 'wrong scope'),
        throwsArgumentError,
      );
      await expectLater(
        guided.saveAnswer('2026-11-01', 'q1', 'wrong scope'),
        throwsArgumentError,
      );
    } finally {
      await db.close();
    }
  });

  test('sessions in two programs refresh independently without discarding pending edits', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final basic = DailyReviewRepository(db);
    final guided = DailyReviewRepository(db, fields: GuidedReview.fields);
    final a = ReviewSession(basic, '2026-11-01', {});
    final b = ReviewSession(guided, '2026-11-01', {});
    try {
      a.edit('q1', 'Keep my old card');
      b.edit(GuidedReview.experiment, 'Try a different question');
      await Future.wait([a.flush(), b.flush()]);
      a.receive(await basic.answers(a.day));
      b.receive(await guided.answers(b.day));
      expect(a.values['q1'], 'Keep my old card');
      expect(b.values[GuidedReview.experiment], 'Try a different question');
      final raw = jsonDecode(
        (await db.select(db.dailyReviews).getSingle()).answersJson,
      ) as Map;
      expect(raw.keys, containsAll(['q1', GuidedReview.experiment]));
    } finally {
      a.dispose();
      b.dispose();
      await db.close();
    }
  });

  test('first visit has no choice; preference survives reconstruction and is local only', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final repository = ReviewProgramRepository(db);
      expect(await repository.load(), isNull);
      await repository.select(ReviewProgram.guided);
      expect(await ReviewProgramRepository(db).load(), ReviewProgram.guided);
      await repository.select(ReviewProgram.classic);
      expect(await repository.load(), ReviewProgram.classic);
      final outbox = await db
          .customSelect(
            "SELECT * FROM sync_outbox WHERE entity_type = 'app_settings'",
          )
          .get();
      expect(outbox, isEmpty);
    } finally {
      await db.close();
    }
  });

  test('one experiment creates one next-day task even across separate offline devices', () async {
    final ids = <String>[];
    for (var device = 0; device < 2; device++) {
      final db = AppDatabase(NativeDatabase.memory());
      final guided = DailyReviewRepository(db, fields: GuidedReview.fields);
      try {
        await db.ensureBuiltInData();
        await guided.saveAnswer(
          '2026-11-01',
          GuidedReview.experiment,
          'Ask for the delivery date\nOne clear question',
        );
        await guided.saveAnswer(
          '2026-11-01',
          GuidedReview.signal,
          'Revisit in the afternoon',
        );
        final actions = GuidedReviewActions(db);
        final id = await actions.createNextTask('2026-11-01');
        ids.add(id);
        expect(await actions.createNextTask('2026-11-01'), id);
        final task = await (db.select(
          db.tasks,
        )..where((r) => r.id.equals(id))).getSingle();
        expect(task.dueDate, DateTime(2026, 11, 2));
        expect(task.listId, 'inbox');
        expect(task.description, contains('Revisit in the afternoon'));
        await guided.saveAnswer(
          '2026-11-01',
          GuidedReview.experiment,
          'A revised reflection',
        );
        await actions.createNextTask('2026-11-01');
        expect(
          (await (db.select(
            db.tasks,
          )..where((r) => r.id.equals(id))).getSingle()).title,
          'Ask for the delivery date',
        );
      } finally {
        await db.close();
      }
    }
    expect(ids[0], ids[1]);
  });

  test('guided and basic questions converge through the existing sync merge policy', () {
    final clocks = <String, dynamic>{
      'answers_json/q1': [20, 'basic-device'],
    };
    final result = mergeRecordFields(
      before: {
        'answers_json': jsonEncode({'q1': 'Original basic answer'}),
      },
      payload: {
        'answers_json': jsonEncode({
          GuidedReview.progress: 'A guided observation',
        }),
      },
      fields: ['answers_json'],
      concurrentFields: {'answers_json'},
      clocks: clocks,
      incomingClocks: {
        'answers_json/${GuidedReview.progress}': [30, 'guided-device'],
      },
      mutationId: 'guided-device',
      nowMilliseconds: 40,
    );
    expect(jsonDecode(result['answers_json'] as String), {
      'q1': 'Original basic answer',
      GuidedReview.progress: 'A guided observation',
    });
  });
}
