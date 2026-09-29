import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/reviews/data/daily_review_repository.dart';
import 'package:fly/features/reviews/presentation/review_providers.dart';
import 'package:fly/features/reviews/presentation/daily_review_page.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/features/notes/data/note_repository.dart';
import 'package:fly/shared/notifications/notification_service.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/design_system/app_theme.dart';

void main() {
  test(
    'review fields serialize independently; failed latest input retries',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = _FailingRepository(db);
      final session = ReviewSession(repo, '2026-09-10', {});
      try {
        session.edit('q1', 'first');
        session.edit('q1', 'latest');
        session.edit('q2', 'value');
        await session.flush();
        expect(await repo.answers(session.day), {
          'q1': 'latest',
          'q2': 'value',
        });
        repo.fail = true;
        session.edit('q1', 'unsaved');
        await expectLater(session.flush(), throwsStateError);
        expect(session.values['q1'], 'unsaved');
        expect((await repo.answers(session.day))['q1'], 'latest');
        repo.fail = false;
        await session.flush();
        expect((await repo.answers(session.day))['q1'], 'unsaved');
        await repo.saveAnswer('2026-09-09', 'q1', 'yesterday');
        expect((await repo.answers(session.day))['q2'], 'value');
        await expectLater(
          repo.saveAnswer('2026-02-30', 'q1', ''),
          throwsArgumentError,
        );
      } finally {
        session.dispose();
        await db.close();
      }
    },
  );
  test('review summary shares inclusive dates and excludes completed/deleted open items', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await db.ensureBuiltInData();
      final day = DateTime(2026, 9, 10);
      for (final id in ['range', 'overdue', 'completed', 'deleted']) {
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: id,
                title: id,
                createdAt: day,
                updatedAt: day,
                sortOrder: 0,
                startDate: Value(day.subtract(const Duration(days: 2))),
                dueDate: Value(
                  id == 'overdue' ? day.subtract(const Duration(days: 1)) : day,
                ),
                completedAt: Value(id == 'completed' ? day : null),
                deletedAt: Value(id == 'deleted' ? day : null),
              ),
            );
      }
      final summary = await DailyReviewRepository(db).summary('2026-09-10');
      expect(summary['completed'], 1);
      expect(summary['open'], 1);
      expect(summary['overdue'], 1);
      expect(summary['followed'], 0);
    } finally {
      await db.close();
    }
  });
  test(
    'schema 12 upgrades without changing note and review survives reopen',
    () async {
      final dir = await Directory.systemTemp.createTemp('fly-review-test-');
      final file = File('${dir.path}/test.db');
      var db = AppDatabase(NativeDatabase(file));
      try {
        final note = await NoteRepository(db).create('preserved');
        await db.customStatement('DROP TABLE daily_reviews');
        await db.customStatement('PRAGMA user_version=12');
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        expect((await NoteRepository(db).get(note))!.title, 'preserved');
        await DailyReviewRepository(db).saveAnswer('2026-09-10', 'q9', 'saved');
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        expect(await DailyReviewRepository(db).answers('2026-09-10'), {
          'q9': 'saved',
        });
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test('review reminder defaults off, honors time, once a day even after time change', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final gateway = _Gateway();
    var now = DateTime(2026, 9, 10, 19);
    final service = NotificationService(db, gateway, now: () => now);
    try {
      final settings = await service.loadSettings();
      expect(settings.reviewEnabled, false);
      expect(await service.checkAndDeliver(), 0);
      await service.saveSettings(settings.copyWith(reviewEnabled: true));
      expect(await service.checkAndDeliver(), 0);
      now = DateTime(2026, 9, 10, 20);
      expect(await service.checkAndDeliver(), 1);
      await service.saveSettings(
        settings.copyWith(reviewEnabled: true, reviewMinute: 1100),
      );
      expect(await service.checkAndDeliver(), 0);
      expect(gateway.payloads, ['review:2026-09-10']);
      now = DateTime(2026, 9, 11, 20);
      expect(await service.checkAndDeliver(), 1);
    } finally {
      await db.close();
    }
  });
  testWidgets('review auto saves and switches days in a narrow layout', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureBuiltInData();
    await DailyReviewRepository(db).saveAnswer('2026-09-09', 'q1', 'Earlier');
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localTodayProvider.overrideWith((ref) => DateTime(2026, 9, 10)),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: FlyTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: const [FlyLocalizationsDelegate()],
          home: const Scaffold(
            body: SizedBox(width: 400, child: DailyReviewPage()),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('review-q1')),
      'Completed sample',
    );
    await tester.runAsync(
      () => container.read(reviewSessionProvider('2026-09-10')).value!.flush(),
    );
    await tester.pump();
    expect(
      (await tester.runAsync(
        () => DailyReviewRepository(db).answers('2026-09-10'),
      ))!['q1'],
      'Completed sample',
    );
    await tester.tap(find.text('Previous day'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    expect(find.text('Completed sample'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}

class _FailingRepository extends DailyReviewRepository {
  _FailingRepository(super.db);
  bool fail = false;
  @override
  Future<void> saveAnswer(String day, String field, String value) async {
    if (fail) throw StateError('test disk error');
    await super.saveAnswer(day, field, value);
  }
}

class _Gateway implements NotificationGateway {
  final payloads = <String>[];
  @override
  Future<void> initialize() async {}
  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    payloads.add(payload);
  }
}
