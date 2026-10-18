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
import 'package:fly/features/files/data/file_browser_query.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/files/presentation/mobile_file_browser.dart';
import 'package:fly/features/reviews/data/daily_review_repository.dart';
import 'package:fly/features/reviews/presentation/daily_review_page.dart';
import 'package:fly/features/reviews/presentation/review_providers.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/data/workspace_folder_repository.dart';
import 'package:fly/shared/design_system/app_theme.dart';

void main() {
  test(
    'customer additions use one ordinary synced folder and remain recoverable',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await db.ensureBuiltInData();
        final folders = WorkspaceFolderRepository(
          db,
          WorkspaceFolderKind.files,
        );
        final root = await folders.ensureCustomerFilesRoot('客户文件');
        expect(await folders.ensureCustomerFilesRoot('Customer files'), root);
        expect((await folders.all()).where((f) => f.id == root), hasLength(1));
        await ManagedFileRepository(db).commit(
          const ImportedFile(
            id: 'new-document',
            relativePath: 'files/customer.pdf',
            name: 'customer.pdf',
            size: 4,
            sha256: 'test',
          ),
          folderId: root,
        );
        expect(
          (await FileBrowserQuery(db)
                  .watch(collection: FileCollection.customers)
                  .first)
              .map((e) => e.file.id),
          contains('new-document'),
        );
        expect(
          (await FileBrowserQuery(db)
                  .watch(collection: FileCollection.folder, folderId: root)
                  .first)
              .map((e) => e.file.id),
          contains('new-document'),
        );
        await folders.remove(root);
        await expectLater(
          folders.ensureCustomerFilesRoot('客户文件'),
          throwsStateError,
        );
        await folders.restore(root);
        expect(await folders.ensureCustomerFilesRoot('客户文件'), root);
      } finally {
        await db.close();
      }
    },
  );

  for (final scenario in [(300.0, 2), (360.0, 3), (430.0, 3), (844.0, 6)]) {
    testWidgets('folder grid adapts to ${scenario.$1} logical pixels', (
      tester,
    ) async {
      tester.view.physicalSize = Size(scenario.$1, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: CustomScrollView(
              slivers: [
                MobileFileFoldersSliver(
                  list: false,
                  folders: [
                    for (var i = 0; i < 8; i++)
                      MobileFileFolder(
                        id: '$i',
                        name: 'Folder $i',
                        onOpen: () {},
                        onLongPress: () {},
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = tester.getTopLeft(
        find.byKey(const ValueKey('mobile-file-folder-0')),
      );
      final lastInRow = tester.getTopLeft(
        find.byKey(ValueKey('mobile-file-folder-${scenario.$2 - 1}')),
      );
      final next = tester.getTopLeft(
        find.byKey(ValueKey('mobile-file-folder-${scenario.$2}')),
      );
      expect(lastInRow.dy, first.dy);
      expect(next.dy, greaterThan(first.dy));
      expect(tester.takeException(), isNull);
    });
  }

  for (final scenario in [
    (const Size(390, 844), false, 1.0),
    (const Size(1100, 850), false, 1.0),
    (const Size(360, 780), true, 1.3),
  ]) {
    final size = scenario.$1;
    testWidgets('review becomes a card and reopens answers at $size', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = size.width < 600
          ? TargetPlatform.android
          : TargetPlatform.windows;
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scenario.$3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final db = AppDatabase(NativeDatabase.memory());
      final repository = DailyReviewRepository(db);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          localTodayProvider.overrideWith((ref) => DateTime(2026, 10, 17)),
        ],
      );
      final boundary = GlobalKey();
      final router = GoRouter(
        initialLocation: '/tasks/review',
        routes: [
          GoRoute(
            path: '/tasks/review',
            builder: (_, _) => const Scaffold(body: DailyReviewPage()),
          ),
        ],
      );
      Future<void> settle() async {
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
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
            await File('build/fly206-$name-${size.width.toInt()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            picture.dispose();
          }
        });
      }

      try {
        await tester.runAsync(() async {
          await db.ensureBuiltInData();
          for (var i = 1; i <= 11; i++) {
            await repository.saveAnswer(
              '2026-10-17',
              'q$i',
              'Completed answer $i',
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
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(
              key: boundary,
              child: MaterialApp.router(
                debugShowCheckedModeBanner: false,
                routerConfig: router,
                theme: scenario.$2 ? FlyTheme.dark() : FlyTheme.light(),
                locale: const Locale('en'),
                supportedLocales: FlyLocalizations.supportedLocales,
                localizationsDelegates: const [
                  FlyLocalizationsDelegate(),
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
              ),
            ),
          ),
        );
        await settle();
        expect(
          find.byKey(const ValueKey('review-today-card-2026-10-17')),
          findsOneWidget,
        );
        expect(find.byType(TextField), findsNothing);
        await capture('review-card');
        final q1 = find.byKey(const ValueKey('review-q1'));
        final answer1 = find.byKey(const ValueKey('review-answer-q1'));
        await tester.ensureVisible(answer1);
        await tester.tap(answer1);
        await settle();
        expect(tester.widget<TextField>(q1).focusNode!.hasFocus, isTrue);
        await tester.enterText(q1, 'Revised answer\nStill supports paragraphs');
        await settle();
        expect(q1, findsOneWidget);
        await capture('review-editing');
        await tester.ensureVisible(
          find.byKey(const ValueKey('review-done-q1')),
        );
        await tester.tap(find.byKey(const ValueKey('review-done-q1')));
        await settle();
        expect(q1, findsNothing);
        expect(
          find.text('Revised answer\nStill supports paragraphs'),
          findsOneWidget,
        );
        await tester.runAsync(
          () => container
              .read(reviewSessionProvider('2026-10-17'))
              .value!
              .flush(),
        );
        expect(
          (await tester.runAsync(
            () => repository.answers('2026-10-17'),
          ))!['q1'],
          'Revised answer\nStill supports paragraphs',
        );
        await tester.runAsync(
          () => repository.saveAnswer(
            '2026-10-17',
            'q2',
            'Synced from another device',
          ),
        );
        await settle();
        expect(find.text('Synced from another device'), findsOneWidget);
        expect(find.byKey(const ValueKey('review-q2')), findsNothing);
        await tester.tap(answer1);
        await settle();
        await tester.enterText(q1, '');
        await settle();
        await tester.tap(find.text('Daily review').first);
        await settle();
        expect(q1, findsOneWidget);
        await tester.enterText(q1, 'Final answer');
        await settle();
        await tester.tap(find.text('Daily review').first);
        await settle();
        expect(q1, findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Final answer'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        container.dispose();
        await settle();
        await tester.runAsync(db.close);
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
