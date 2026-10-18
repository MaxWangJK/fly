import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'package:fly/shared/design_system/fly_color_scheme.dart';

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
  test('history omits blank fields and dates and stays newest first', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await db.ensureBuiltInData();
      final repository = DailyReviewRepository(db);
      await repository.saveAnswer('2026-09-08', 'q1', 'Earlier fact');
      await repository.saveAnswer('2026-09-09', 'q9', '  ');
      await repository.saveAnswer('2026-09-10', 'q1', 'Today fact');
      await repository.saveAnswer('2026-09-10', 'q8', '');
      final history = await repository.watchHistory().first;
      expect(history.map((entry) => entry.day), ['2026-09-10', '2026-09-08']);
      expect(history.first.answers, {'q1': 'Today fact'});
    } finally {
      await db.close();
    }
  });
  testWidgets('history cards show only answers and return to the editor', (
    tester,
  ) async {
    const capture = bool.fromEnvironment('FLY_CAPTURE_REVIEW');
    const paletteName = String.fromEnvironment(
      'FLY_VISUAL_PALETTE',
      defaultValue: 'flyDefault',
    );
    const dark = bool.fromEnvironment('FLY_VISUAL_DARK');
    const zh = bool.fromEnvironment('FLY_VISUAL_ZH');
    const captureWidth = int.fromEnvironment(
      'FLY_CAPTURE_REVIEW_WIDTH',
      defaultValue: 1100,
    );
    if (capture) await tester.runAsync(_loadCaptureFonts);
    tester.view.physicalSize = Size(captureWidth.toDouble(), 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureBuiltInData();
    final repository = DailyReviewRepository(db);
    await repository.saveAnswer('2026-09-09', 'q3', 'Older problem');
    await repository.saveAnswer(
      '2026-09-08',
      'q5',
      'Keep a clear follow-up rhythm',
    );
    await repository.saveAnswer(
      '2026-09-07',
      'q1',
      'Sent the revised quotation and confirmed the delivery window.',
    );
    await repository.saveAnswer(
      '2026-09-07',
      'q2',
      'The customer responded with a clearer target quantity.',
    );
    await repository.saveAnswer(
      '2026-09-06',
      'q8',
      'Call the factory about packaging details.',
    );
    await repository.saveAnswer(
      '2026-09-05',
      'q9',
      'A quieter day to organize open orders.',
    );
    await repository.saveAnswer('2026-09-10', 'q1', 'Today fact');
    await repository.saveAnswer('2026-09-10', 'q9', '');
    await repository.saveAnswer(
      '2026-09-04',
      'q1',
      List.filled(28, 'A longer note.').join(' '),
    );
    final captureKey = GlobalKey();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localTodayProvider.overrideWith((ref) => DateTime(2026, 9, 10)),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark
                ? FlyTheme.dark(FlyPaletteIdX.parse(paletteName))
                : FlyTheme.light(FlyPaletteIdX.parse(paletteName)),
            locale: zh ? const Locale('zh', 'CN') : const Locale('en'),
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
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('review-history-toggle')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('review-history-2026-09-10')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('review-history-2026-09-09')),
      findsOneWidget,
    );
    if (captureWidth >= 900) {
      final firstRowY = tester
          .getTopLeft(find.byKey(const ValueKey('review-history-2026-09-10')))
          .dy;
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('review-history-2026-09-08')))
            .dy,
        firstRowY,
      );
    }
    expect(find.text('Today fact'), findsOneWidget);
    expect(find.text('Older problem'), findsOneWidget);
    expect(find.text(zh ? '完成' : 'Done'), findsWidgets);
    expect(
      find.text(zh ? '今天完成了什么？' : 'What did I accomplish today?'),
      findsNothing,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('review-history-2026-09-04')))
          .height,
      greaterThan(
        tester
            .getSize(find.byKey(const ValueKey('review-history-2026-09-10')))
            .height,
      ),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('review-history-2026-09-04')))
          .width,
      greaterThan(
        tester
            .getSize(find.byKey(const ValueKey('review-history-2026-09-10')))
            .width,
      ),
    );
    expect(
      tester
          .widget<Text>(find.text(List.filled(28, 'A longer note.').join(' ')))
          .maxLines,
      7,
    );
    final factSurface = tester.widget<Container>(
      find.byKey(const ValueKey('review-history-section-2026-09-07-1')),
    );
    final problemSurface = tester.widget<Container>(
      find.byKey(const ValueKey('review-history-section-2026-09-09-2')),
    );
    expect(
      (factSurface.decoration! as BoxDecoration).color,
      isNot((problemSurface.decoration! as BoxDecoration).color),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('review-history-2026-09-10')),
        matching: find.text(zh ? '今日总结' : 'Daily summary'),
      ),
      findsNothing,
    );
    if (capture) {
      await tester.runAsync(
        () => _captureReview(
          captureKey,
          'artifacts/$paletteName/review-history${dark ? '-dark' : ''}.png',
        ),
      );
    }
    await tester.tap(find.byKey(const ValueKey('review-history-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-answer-q1')), findsOneWidget);
    expect(find.text('Today fact'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    for (var index = 0; index < 12; index++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
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

Future<void> _loadCaptureFonts() async {
  for (final (family, path) in [
    ('Microsoft YaHei UI', r'C:\Windows\Fonts\msyh.ttc'),
    (
      'MaterialIcons',
      r'D:\ProgramData\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    ),
  ]) {
    final bytes = await File(path).readAsBytes();
    await (FontLoader(
      family,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
}

Future<void> _captureReview(GlobalKey key, String path) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) throw StateError('Unable to encode $path');
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
}
