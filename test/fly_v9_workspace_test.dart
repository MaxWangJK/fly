import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:drift/native.dart';
import 'package:fly/app/app.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/core/storage/data_root_providers.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/features/notes/data/note_repository.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/files/data/file_browser_query.dart';
import 'package:fly/shared/data/workspace_folder_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('FLY_V9_CAPTURE')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('v9-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('artifacts/v9-$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets(
    'Restored conflict can be saved as a new note without overwriting original',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      final repo = NoteRepository(db);
      late String id;
      await tester.runAsync(() async {
        await db.ensureBuiltInData();
        id = await repo.create('原始笔记');
        final blocks = await repo.blocks(id);
        await repo.save(id, title: '较新版本', blocks: blocks, expectedRevision: 1);
        await repo.writeDraft(
          id,
          NoteDraft(title: '未保存草稿', blocks: blocks, revision: 1),
        );
      });
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const FlyApp()),
      );
      await settle(tester);
      container.read(appRouterProvider).go('/notes?id=$id');
      await settle(tester);
      expect(find.text('另存为新笔记'), findsOneWidget);
      await tester.tap(find.text('另存为新笔记'));
      await settle(tester);
      expect(find.text('未保存草稿（草稿副本）'), findsWidgets);
      await tester.runAsync(() async {
        expect((await repo.get(id))!.title, '较新版本');
        expect(await repo.readDraft(id), isNull);
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await settle(tester);
      addTearDown(db.close);
    },
  );
  test(
    'Files direct children, recursive filter and file tag AND query',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final folders = WorkspaceFolderRepository(
          db,
          WorkspaceFolderKind.files,
        );
        final parent = await folders.create('产品');
        final child = await folders.create('墙板', parentId: parent);
        final repo = ManagedFileRepository(db);
        await repo.commit(
          const ImportedFile(
            id: 'file1',
            relativePath: 'files/test/price.pdf',
            name: 'WPC价格表.pdf',
            size: 12,
            sha256: 'abc',
          ),
          folderId: child,
        );
        final first = await repo.createTag('WPC');
        final second = await repo.createTag('2026');
        await repo.setTag('file1', first, true);
        final query = FileBrowserQuery(db);
        expect(
          await query
              .watch(collection: FileCollection.folder, folderId: parent)
              .first,
          isEmpty,
        );
        expect(
          (await query
                  .watch(
                    collection: FileCollection.folder,
                    folderId: parent,
                    descendants: true,
                  )
                  .first)
              .single
              .name,
          'WPC价格表.pdf',
        );
        expect(
          await query
              .watch(
                collection: FileCollection.recent,
                fileTags: {first, second},
              )
              .first,
          isEmpty,
        );
        await repo.setTag('file1', second, true);
        expect(
          (await query
                  .watch(
                    collection: FileCollection.recent,
                    fileTags: {first, second},
                    search: '2026',
                  )
                  .first)
              .length,
          1,
        );
        await repo.remove('file1');
        expect(
          await query.watch(collection: FileCollection.recent).first,
          isEmpty,
        );
        expect(
          (await query.watch(collection: FileCollection.deleted).first).length,
          1,
        );
      } finally {
        await db.close();
      }
    },
  );
  testWidgets('V9 primary navigation, note creation and narrow files view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase(NativeDatabase.memory());
    final root = Directory.systemTemp.path;
    if (const bool.fromEnvironment('FLY_V9_CAPTURE')) {
      await tester.runAsync(() async {
        for (final pair in [
          ('Microsoft YaHei UI', r'C:\Windows\Fonts\msyh.ttc'),
          ('Ahem', r'C:\Windows\Fonts\msyh.ttc'),
          (
            'MaterialIcons',
            r'D:\ProgramData\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
          ),
        ]) {
          final loader = FontLoader(pair.$1)
            ..addFont(
              File(pair.$2)
                  .readAsBytes()
                  .then((bytes) => ByteData.sublistView(bytes)),
            );
          await loader.load();
        }
      });
    }
    await tester.runAsync(db.ensureBuiltInData);
    await tester.runAsync(() async {
      final repo = ManagedFileRepository(db);
      await repo.commit(
        const ImportedFile(
          id: 'demo-price',
          relativePath: 'files/demo/WPC.pdf',
          name: 'WPC 产品价格表.pdf',
          size: 245760,
          sha256: 'demo-only',
        ),
      );
      final tag = await repo.createTag('价格资料');
      await repo.setTag('demo-price', tag, true);
    });
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        dataRootPathProvider.overrideWithValue(root),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const RepaintBoundary(
          key: ValueKey('v9-capture'),
          child: FlyApp(),
        ),
      ),
    );
    await settle(tester);
    debugPrint('V9 test: startup ready');
    await tester.tap(find.byKey(const ValueKey('primary-files')));
    await settle(tester);
    expect(find.text('我的文件'), findsWidgets);
    expect(find.text('客户文件'), findsOneWidget);
    await capture(tester, 'files');
    debugPrint('V9 test: files ready');
    await tester.tap(find.byKey(const ValueKey('primary-notes')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('new-note-title')),
      '外贸知识',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text('外贸知识'), findsWidgets);
    expect(find.byTooltip('块操作'), findsOneWidget);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('block-text-'),
      ),
      '先了解客户市场，再准备产品资料。',
    );
    await settle(tester);
    expect(find.text('先了解客户市场，再准备产品资料。'), findsOneWidget);
    await capture(tester, 'notes');
    debugPrint('V9 test: note created');
    expect(tester.takeException(), isNull);
    container.read(appRouterProvider).go('/files');
    await settle(tester);
    tester.view.physicalSize = const Size(440, 850);
    await settle(tester);
    expect(tester.takeException(), isNull);
    debugPrint('V9 test: narrow ready');
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await settle(tester);
    addTearDown(db.close);
  });
}
