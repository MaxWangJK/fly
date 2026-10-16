import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/dashboard/data/dashboard_focus_repository.dart';
import 'package:fly/features/dashboard/domain/dashboard_focus.dart';
import 'package:fly/features/dashboard/presentation/dashboard_focus_board.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/features/knowledge/data/fly_book_repository.dart';
import 'package:fly/features/knowledge/domain/fly_book.dart';
import 'package:fly/features/knowledge/presentation/fly_book_document.dart';
import 'package:fly/features/knowledge/presentation/fly_book_providers.dart';
import 'package:fly/features/knowledge/presentation/fly_book_workspace.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/design_system/app_theme.dart';

void main() {
  testWidgets(
    'capture real book shelf, motto and publisher HTML with isolated data',
    (tester) async {
      if (!const bool.fromEnvironment('FLY_BOOK_CAPTURE')) return;
      await tester.runAsync(() async {
        for (final pair in [
          ('Microsoft YaHei UI', r'C:\Windows\Fonts\msyh.ttc'),
          ('Ahem', r'C:\Windows\Fonts\msyh.ttc'),
          (
            'MaterialIcons',
            r'D:\ProgramData\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
          ),
        ]) {
          await (FontLoader(pair.$1)..addFont(
                Future.value(
                  ByteData.sublistView(await File(pair.$2).readAsBytes()),
                ),
              ))
              .load();
        }
      });
      final book = (await tester.runAsync(() async {
        const root = 'book_sources/foreign_trade';
        final data = jsonDecode(
          await File('$root/book.json').readAsString(),
        ) as Map<String, dynamic>;
        final chapters = <FlyBookChapter>[];
        for (final item in data['chapters'] as List) {
          chapters.add(
            FlyBookChapter(
              id: item['id'] as String,
              title: item['title'] as String,
              html: await File('$root/${item['file']}').readAsString(),
            ),
          );
        }
        final assets = <String, Uint8List>{};
        await for (final entity in Directory('$root/assets').list()) {
          if (entity is File) {
            assets['assets/${entity.uri.pathSegments.last}'] = await entity
                .readAsBytes();
          }
        }
        final value = FlyBook(
          id: data['id'] as String,
          title: data['title'] as String,
          author: data['author'] as String,
          version: 1,
          description: data['description'] as String,
          css: await File('$root/styles/book.css').readAsString(),
          chapters: chapters,
          assets: assets,
        );
        FlyBookDocument.validate(value);
        await Directory('artifacts/fly20339').create(recursive: true);
        for (final id in ['reading-guide', 'first-contact']) {
          final chapter = value.chapters.firstWhere((c) => c.id == id);
          await File('artifacts/fly20339/$id.html')
              .writeAsString(FlyBookDocument.render(value, chapter));
        }
        return value;
      }))!;
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          flyBooksProvider.overrideWith((_) async => [book]),
          flyReadingRepositoryProvider.overrideWithValue(
            FlyReadingRepository(db),
          ),
        ],
      );
      addTearDown(container.dispose);
      final key = GlobalKey();
      Future<void> show(Widget child, Size size, String name) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: FlyTheme.light(),
              locale: const Locale('zh', 'CN'),
              supportedLocales: FlyLocalizations.supportedLocales,
              localizationsDelegates: const [
                FlyLocalizationsDelegate(),
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: Scaffold(
                body: RepaintBoundary(key: key, child: child),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          await File('artifacts/fly20339/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        });
      }

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await show(
        const FlyBookWorkspace(),
        const Size(1200, 900),
        'book-shelf-desktop',
      );
      await show(
        const FlyBookWorkspace(),
        const Size(500, 900),
        'book-shelf-narrow',
      );
      final day = DateTime(2026, 10, 14);
      await tester.runAsync(() async {
        final focus = DashboardFocusRepository(db);
        await focus.save(
          type: DashboardFocusType.motto,
          content: '把每一次认真，变成长期的力量。',
          day: day,
        );
        await focus.save(
          type: DashboardFocusType.mainMission,
          content: '建立可靠而长久的客户关系。',
          day: day,
        );
      });
      await show(
        SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: DashboardFocusBoard(day: day, onHistory: () {}),
        ),
        const Size(700, 900),
        'motto-focus',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
