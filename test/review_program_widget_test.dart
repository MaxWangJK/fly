import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/reviews/data/daily_review_repository.dart';
import 'package:fly/features/reviews/data/review_program_repository.dart';
import 'package:fly/features/reviews/domain/review_program.dart';
import 'package:fly/features/reviews/presentation/review_home_page.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/design_system/app_theme.dart';

void main() {
  for (final scenario in [
    (const Size(390, 844), true, false, 1.0),
    (const Size(1100, 850), false, false, 1.0),
    (const Size(360, 780), true, true, 1.3),
    (const Size(844, 390), true, false, 1.0),
  ]) {
    testWidgets(
      'program preview, trial and preserved basic cards at ${scenario.$1}',
      (tester) async {
        final size = scenario.$1, zh = scenario.$2;
        debugDefaultTargetPlatformOverride =
            size.width < 600 || size.height < 500
            ? TargetPlatform.android
            : TargetPlatform.windows;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scenario.$4;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final db = AppDatabase(NativeDatabase.memory());
        final basic = DailyReviewRepository(db);
        final guided = DailyReviewRepository(db, fields: GuidedReview.fields);
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            localTodayProvider.overrideWith((ref) => DateTime(2026, 11, 1)),
          ],
        );
        final router = GoRouter(
          initialLocation: '/tasks/review',
          routes: [
            GoRoute(
              path: '/tasks/review',
              builder: (_, _) => const Scaffold(body: ReviewHomePage()),
            ),
          ],
        );
        final boundary = GlobalKey();
        Future<void> settle() async {
          for (var i = 0; i < 8; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 15)),
            );
            await tester.pump(const Duration(milliseconds: 40));
          }
        }

        Future<void> tap(Finder finder) async {
          FocusManager.instance.primaryFocus?.unfocus();
          await settle();
          await tester.ensureVisible(finder);
          await settle();
          await tester.tap(finder);
          await settle();
        }

        Future<void> capture(String name) async {
          await tester.runAsync(() async {
            final picture =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            try {
              final bytes = await picture.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('build/review-compass-$name-${size.width.toInt()}.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              picture.dispose();
            }
          });
        }

        try {
          await tester.runAsync(() async {
            await db.ensureBuiltInData();
            await basic.saveAnswer(
              '2026-11-01',
              'q1',
              'My original basic answer',
            );
            if (size.width == 390) {
              await guided.saveAnswer(
                '2026-10-31',
                GuidedReview.experiment,
                'Yesterday experiment',
              );
              await guided.saveAnswer(
                '2026-10-25',
                GuidedReview.progress,
                'Outside this seven-day window',
              );
              await guided.saveAnswer(
                '2026-11-05',
                GuidedReview.progress,
                'Future entry',
              );
            }
            for (final font in {
              'Ahem': 'C:/Windows/Fonts/msyh.ttc',
              'Microsoft YaHei UI': 'C:/Windows/Fonts/msyh.ttc',
              'MaterialIcons': 'D:/ProgramData/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            }.entries) {
              final file = File(font.value);
              if (await file.exists()) {
                await (FontLoader(font.key)..addFont(
                      Future.value(
                        ByteData.sublistView(await file.readAsBytes()),
                      ),
                    ))
                    .load();
              }
            }
          });
          Widget app() => UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(
              key: boundary,
              child: MaterialApp.router(
                routerConfig: router,
                debugShowCheckedModeBanner: false,
                theme: scenario.$3 ? FlyTheme.dark() : FlyTheme.light(),
                locale: Locale(zh ? 'zh' : 'en'),
                supportedLocales: FlyLocalizations.supportedLocales,
                localizationsDelegates: const [
                  FlyLocalizationsDelegate(),
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
              ),
            ),
          );
          await tester.pumpWidget(app());
          await settle();
          expect(
            find.byKey(const ValueKey('review-program-classic')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('review-program-guided')),
            findsOneWidget,
          );
          await capture('choices');
          await tap(find.byKey(const ValueKey('review-preview-guided')));
          expect(find.byType(TextField), findsNothing);
          await capture('preview');
          expect(
            await tester.runAsync(() => guided.answers('2026-11-01')),
            isEmpty,
          );
          expect(
            await tester.runAsync(() => ReviewProgramRepository(db).load()),
            isNull,
          );
          await tap(find.text(zh ? '七日校准' : '7 days').first);
          await capture('week-preview');
          await tap(find.byKey(const ValueKey('guided-preview-start')));
          expect(
            await tester.runAsync(() => ReviewProgramRepository(db).load()),
            ReviewProgram.guided,
          );
          final progress = find.byKey(
            ValueKey('review-${GuidedReview.progress}'),
          );
          await tester.ensureVisible(progress);
          await settle();
          await tester.enterText(progress, 'One useful step today');
          final experiment = find.byKey(
            ValueKey('review-${GuidedReview.experiment}'),
          );
          await tester.ensureVisible(experiment);
          await settle();
          await tester.enterText(experiment, 'Ask one clear question');
          await settle();
          await tap(find.byKey(const ValueKey('guided-create-task')));
          final saved = (await tester.runAsync(
            () => guided.answers('2026-11-01'),
          ))!;
          expect(saved[GuidedReview.experiment], 'Ask one clear question');
          expect(saved[GuidedReview.taskId], isNotEmpty);
          if (size.width == 390) {
            await tap(find.text('有帮助'));
            await tap(find.text('七日校准').first);
            expect(find.text('2 天留下观察 · 2 个小实验 · 1 次结果回看'), findsOneWidget);
            expect(find.text('Future entry'), findsNothing);
            expect(find.text('Outside this seven-day window'), findsNothing);
            final keep = find.byKey(ValueKey('review-${GuidedReview.keep}'));
            await tester.ensureVisible(keep);
            await settle();
            await tester.enterText(keep, 'Keep asking clear questions');
            await tap(find.text('每日航向').first);
            final checkpoint = (await tester.runAsync(
              () => guided.answers('2026-11-01'),
            ))!;
            expect(
              checkpoint[GuidedReview.keep],
              'Keep asking clear questions',
            );
            expect(checkpoint[GuidedReview.revisitDay], '2026-10-31');
          }
          await tap(find.byKey(const ValueKey('guided-close')));
          expect(
            find.byKey(const ValueKey('guided-history-2026-11-01')),
            findsOneWidget,
          );
          expect(find.byType(TextField), findsNothing);
          await capture('daily-card');
          await tap(find.text(zh ? '航向历史' : 'History').first);
          await tap(
            find.descendant(
              of: find.byKey(const ValueKey('guided-history-2026-11-01')),
              matching: find.text(zh ? '打开这一天' : 'Open this day'),
            ),
          );
          await tap(find.text(zh ? '继续编辑' : 'Continue editing').first);
          await tap(
            find.byKey(ValueKey('review-answer-${GuidedReview.progress}')),
          );
          expect(progress, findsOneWidget);
          await tap(find.byKey(const ValueKey('review-choose-program')));
          await tap(find.byKey(const ValueKey('review-start-classic')));
          expect(
            find.byKey(const ValueKey('review-today-card-2026-11-01')),
            findsOneWidget,
          );
          expect(find.text('My original basic answer'), findsOneWidget);
          expect(
            (await tester.runAsync(() => basic.answers('2026-11-01')))!['q1'],
            'My original basic answer',
          );
          expect(
            (await tester.runAsync(
              () => guided.answers('2026-11-01'),
            ))![GuidedReview.experiment],
            'Ask one clear question',
          );
          await capture('classic-preserved');
          await tester.pumpWidget(const SizedBox.shrink());
          await settle();
          await tester.pumpWidget(app());
          await settle();
          expect(
            find.byKey(const ValueKey('review-program-classic')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('review-today-card-2026-11-01')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          router.dispose();
          container.dispose();
          await settle();
          await tester.runAsync(db.close);
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
