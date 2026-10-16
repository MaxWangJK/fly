import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/shared/design_system/app_theme.dart';
import 'package:fly/features/dashboard/data/dashboard_focus_repository.dart';
import 'package:fly/features/dashboard/domain/dashboard_focus.dart';
import 'package:fly/features/knowledge/data/fly_book_codec.dart';
import 'package:fly/features/knowledge/data/fly_book_repository.dart';
import 'package:fly/features/knowledge/domain/fly_book.dart';
import 'package:fly/features/knowledge/presentation/fly_book_document.dart';
import 'package:fly/features/knowledge/presentation/fly_book_providers.dart';
import 'package:fly/features/knowledge/presentation/fly_book_workspace.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/design_system/fly_color_scheme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

final contentKey = List.generate(32, (i) => i + 1);
final signingSeed = List.generate(32, (i) => 255 - i);
FlyBook fixture({int version = 1, String? css, String? html}) => FlyBook(
  id: 'test-book',
  title: '外贸实践书',
  author: 'Fly',
  version: version,
  description: '按章节学习并留下下一步。',
  css: css ?? 'body{color:#333}',
  chapters: [
    FlyBookChapter(
      id: 'intro',
      title: '第一章',
      html: html ?? '<h1>第一章</h1><p>这是受保护的内容。</p>',
    ),
    const FlyBookChapter(id: 'next', title: '第二章', html: '<h1>第二章</h1>'),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<int> publicKey;
  setUpAll(
    () async => publicKey = (await (await Ed25519().newKeyPairFromSeed(
      signingSeed,
    )).extractPublicKey()).bytes,
  );

  test(
    'signed encrypted envelope hides HTML and rejects tampering/wrong keys',
    () async {
      final codec = FlyBookCodec();
      final bytes = await codec.encode(
        fixture(),
        contentKey: contentKey,
        signingSeed: signingSeed,
      );
      expect(ascii.decode(bytes.take(8).toList()), 'FLYBOOK1');
      expect(
        utf8.decode(bytes, allowMalformed: true),
        isNot(contains('受保护的内容')),
      );
      expect(
        (await codec.decode(
          bytes,
          contentKey: contentKey,
          publicKey: publicKey,
        )).chapters.length,
        2,
      );
      final altered = Uint8List.fromList(bytes)..[40] ^= 1;
      await expectLater(
        codec.decode(altered, contentKey: contentKey, publicKey: publicKey),
        throwsFormatException,
      );
      await expectLater(
        codec.decode(
          bytes,
          contentKey: List.filled(32, 0),
          publicKey: publicKey,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      await expectLater(
        codec.decode(
          bytes.sublist(0, bytes.length - 1),
          contentKey: contentKey,
          publicKey: publicKey,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'no publisher code, remote styles, file URLs or duplicate chapters',
    () async {
      final codec = FlyBookCodec();
      for (final book in [
        fixture(html: '<script>alert(1)</script>'),
        fixture(html: '<img src="file:///secret.png">'),
        fixture(css: 'body{background:url(https://example.com/tracker)}'),
        fixture(html: '<p onclick="alert(1)">x</p>'),
      ]) {
        await expectLater(
          codec.encode(book, contentKey: contentKey, signingSeed: signingSeed),
          throwsFormatException,
        );
      }
      final json = fixture().toJson();
      json['chapters'] = [
        fixture().chapters.first.toJson(),
        fixture().chapters.first.toJson(),
      ];
      expect(() => FlyBook.fromJson(json), throwsFormatException);
      final page = FlyBookDocument.render(
        fixture(),
        fixture().chapters.first,
        position: .4,
      );
      expect(page, contains("connect-src 'none'"));
      expect(page, contains('event.preventDefault()'));
      expect(page, contains('type:\'progress\''));
    },
  );

  test('imports keep only ciphertext and preserve previous book on invalid updates', () async {
    final root = await Directory.systemTemp.createTemp('fly-book-repo-');
    addTearDown(() => root.delete(recursive: true));
    final library = FlyBookLibrary(
      rootPath: root.path,
      contentKey: contentKey,
      publicKey: publicKey,
    );
    final source = File('${root.path}/source.fly');
    Future<void> write(int version) async => source.writeAsBytes(
      await FlyBookCodec().encode(
        fixture(version: version),
        contentKey: contentKey,
        signingSeed: signingSeed,
      ),
    );
    await write(1);
    await library.importFile(source.path);
    final stored = File('${library.directory}/test-book.fly');
    final previous = await stored.readAsBytes();
    await expectLater(library.importFile(source.path), throwsFormatException);
    await source.writeAsBytes([1, 2, 3]);
    await expectLater(library.importFile(source.path), throwsFormatException);
    expect(await stored.readAsBytes(), previous);
    await write(2);
    await library.importFile(source.path);
    expect((await library.load()).single.version, 2);
    expect(
      (await Directory(
        library.directory,
      ).list().toList()).map((e) => e.path.split(Platform.pathSeparator).last),
      ['test-book.fly'],
    );
  });

  test('progress resumes backwards without losing furthest/history and survives restart', () async {
    final root = await Directory.systemTemp.createTemp('fly-reading-state-');
    addTearDown(() => root.delete(recursive: true));
    var db = AppDatabase(NativeDatabase(File('${root.path}/state.db')));
    var repo = FlyReadingRepository(db);
    await repo.record('test-book', 'intro', .8);
    await repo.record('test-book', 'intro', .25);
    await repo.record('test-book', 'next', 1);
    await db.close();
    db = AppDatabase(NativeDatabase(File('${root.path}/state.db')));
    addTearDown(db.close);
    repo = FlyReadingRepository(db);
    final state = await repo.load();
    expect(state.chapter('test-book', 'intro')?.position, .25);
    expect(state.chapter('test-book', 'intro')?.furthest, .8);
    expect(state.last('test-book')?.chapterId, 'next');
    expect(state.progress(fixture()), closeTo(.9, .0001));
    await expectLater(
      repo.record('test-book', 'intro', double.nan),
      throwsFormatException,
    );
  });

  test(
    'motto is independent of mission and shares existing persisted history',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = DashboardFocusRepository(db);
      final day = DateTime(2026, 10, 14);
      await repo.save(
        type: DashboardFocusType.mainMission,
        content: '长期目标',
        day: day,
      );
      await repo.save(
        type: DashboardFocusType.motto,
        content: '先做重要的事',
        day: day,
      );
      await repo.save(
        type: DashboardFocusType.motto,
        content: '每天前进一步',
        day: day,
      );
      expect((await repo.read(day)).motto, '每天前进一步');
      expect((await repo.read(day)).mainMission, '长期目标');
      expect((await repo.history()).single.type, DashboardFocusType.motto);
    },
  );

  testWidgets(
    'book workspace has two levels, no note/search and persistent chapter progress',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      ValueChanged<double>? report;
      String? document;
      final container = ProviderContainer(
        overrides: [
          flyBooksProvider.overrideWith((ref) async => [fixture()]),
          flyReadingRepositoryProvider.overrideWithValue(
            FlyReadingRepository(db),
          ),
          flyBookPageBuilderProvider.overrideWithValue((
            html,
            onProgress,
            onLink,
            key,
          ) {
            document = html;
            report = onProgress;
            return ColoredBox(
              key: key,
              color: Colors.white,
              child: const Center(child: Text('Native reader adapter')),
            );
          }),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('zh', 'CN'),
            theme: FlyTheme.light(FlyPaletteId.flyDefault),
            supportedLocales: FlyLocalizations.supportedLocales,
            localizationsDelegates: const [
              FlyLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const Scaffold(body: FlyBookWorkspace()),
          ),
        ),
      );
      await tester.runAsync(
        () => container.read(flyReadingStateProvider.future),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('book-import')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('我的笔记'), findsNothing);
      expect(
        find.byKey(const ValueKey('book-chapter-test-book-intro')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('book-continue-test-book')));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(document, contains('这是受保护的内容'));
      report!(.62);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(
        (await tester.runAsync(() => FlyReadingRepository(db).load()))
            ?.chapter('test-book', 'intro')
            ?.position,
        .62,
      );
      await tester.tap(find.byTooltip('标记本章已读'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(
        (await tester.runAsync(() => FlyReadingRepository(db).load()))
            ?.chapter('test-book', 'intro')
            ?.furthest,
        1,
      );
      await tester.tap(find.byKey(const ValueKey('book-reading-history')));
      await tester.pumpAndSettle();
      expect(find.text('阅读历史'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
