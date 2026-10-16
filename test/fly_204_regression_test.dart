import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/reviews/data/daily_review_repository.dart';
import 'package:fly/features/reviews/presentation/daily_review_page.dart';
import 'package:fly/features/reviews/presentation/review_providers.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/features/tasks/presentation/widgets/task_completion_feedback.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/design_system/app_theme.dart';

class _FailedReviewSave extends DailyReviewRepository {
  const _FailedReviewSave(super.db);
  @override
  Future<void> saveAnswer(String day, String field, String value) async {
    throw StateError('Synthetic offline save');
  }
}

void main() {
  test('synced review fields preserve unsaved local answers', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final session = ReviewSession(_FailedReviewSave(db), '2026-10-14', {});
    try {
      session.edit('q1', 'Pending local answer');
      await expectLater(session.flush(), throwsStateError);
      session.receive({'q1': 'Remote answer', 'q2': 'Phone answer'});
      expect(session.values['q1'], 'Pending local answer');
      expect(session.values['q2'], 'Phone answer');
    } finally {
      session.dispose();
      await db.close();
    }
  });

  testWidgets('open desktop review editor refreshes incoming synced answers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localTodayProvider.overrideWith((ref) => DateTime(2026, 10, 14)),
      ],
    );
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    try {
      await tester.runAsync(db.ensureBuiltInData);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: FlyTheme.light(),
            locale: const Locale('en'),
            supportedLocales: FlyLocalizations.supportedLocales,
            localizationsDelegates: const [
              FlyLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const Scaffold(body: DailyReviewPage()),
          ),
        ),
      );
      await settle();
      final q1 = find.byKey(const ValueKey('review-q1'));
      expect(tester.widget<TextField>(q1).controller!.text, isEmpty);
      final repository = DailyReviewRepository(db);
      await tester.runAsync(
        () => repository.saveAnswer('2026-10-14', 'q1', 'Written on phone'),
      );
      await settle();
      expect(tester.widget<TextField>(q1).controller!.text, 'Written on phone');
      await tester.enterText(q1, 'Desktop revision');
      await settle();
      final selection = tester.widget<TextField>(q1).controller!.selection;
      await tester.runAsync(
        () =>
            repository.saveAnswer('2026-10-14', 'q2', 'Another synced answer'),
      );
      await settle();
      expect(tester.widget<TextField>(q1).controller!.text, 'Desktop revision');
      expect(tester.widget<TextField>(q1).controller!.selection, selection);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('review-q2')))
            .controller!
            .text,
        'Another synced answer',
      );
      await tester.runAsync(
        () => repository.saveAnswer('2026-10-14', 'q1', ''),
      );
      await settle();
      expect(tester.widget<TextField>(q1).controller!.text, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await settle();
      await tester.runAsync(db.close);
    }
  });

  testWidgets(
    'task completion undo expires after four seconds and still works before expiry',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      await db.ensureBuiltInData();
      final task = await DriftTaskRepository(db)
          .createTask(title: 'Completion regression');
      Future<void> settle() async {
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => Center(
                    child: FilledButton(
                      onPressed: () =>
                          completeTaskWithFeedback(context, ref, task.id, true),
                      child: const Text('Complete'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Complete'));
        await settle();
        expect(find.text('任务已完成'), findsOneWidget);
        expect(tester.widget<SnackBar>(find.byType(SnackBar)).persist, isFalse);
        await tester.tap(find.text('撤销'));
        await settle();
        expect(
          (await tester.runAsync(
            () => DriftTaskRepository(db).watchTask(task.id).first,
          ))!.isCompleted,
          isFalse,
        );
        await tester.tap(find.text('Complete'));
        await settle();
        expect(find.text('撤销'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.text('撤销'), findsNothing);
        expect(
          (await tester.runAsync(
            () => DriftTaskRepository(db).watchTask(task.id).first,
          ))!.isCompleted,
          isTrue,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await tester.runAsync(db.close);
      }
    },
  );
}
