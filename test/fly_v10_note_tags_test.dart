import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/notes/data/note_repository.dart';
import 'package:fly/features/notes/data/note_tag_repository.dart';
import 'package:fly/shared/data/tag_garbage_collector.dart';
import 'package:fly/shared/search/global_search_service.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/features/notes/presentation/note_tags_editor.dart';

void main() {
  testWidgets('note tag footer adds with Enter and removes only its link', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final id = (await tester.runAsync(
      () => NoteRepository(db).create('标签测试'),
    ))!;
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 320, child: NoteTagsEditor(noteId: id)),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('note-tag-input')),
      '#Market',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.text('Market'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Remove tag from this note'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.text('Market'), findsNothing);
    final sharedTag = (await tester.runAsync(() async {
      final other = await NoteRepository(db).create('Source note');
      return NoteTagRepository(db).add(other, 'Research');
    }))!;
    await tester.enterText(find.byKey(const ValueKey('note-tag-input')), 'Res');
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('note-tag-suggestion-$sharedTag')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    expect(find.text('Research'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
  test(
    'note tags normalize, search, survive cleanup and restore, unlink safely',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final notes = NoteRepository(db);
        final tags = NoteTagRepository(db);
        final cleanup = TagCleanupService(db);
        final id = await notes.create('知识');
        final other = await notes.create('产品');
        final tag = await tags.add(id, ' #WPC   Guide ');
        expect(await tags.add(id, 'wpc guide'), tag);
        expect(await tags.watch(id).first, hasLength(1));
        await tags.add(other, 'WPC Guide');
        expect((await cleanup.referencesFor(tag)).noteReferences, 2);
        expect(await cleanup.collectCandidates([tag]), 0);
        await expectLater(cleanup.deleteTagDefinition(tag), throwsStateError);
        final results = await GlobalSearchService(db).search('WPC Guide');
        expect(
          results
              .where((r) => r.type == SearchResultType.workspaceNote)
              .map((r) => r.entityId),
          unorderedEquals([id, other]),
        );
        await notes.remove(id);
        await tags.remove(other, tag);
        expect(await cleanup.collectCandidates([tag]), 0);
        expect(await GlobalSearchService(db).search('WPC Guide'), isEmpty);
        await expectLater(tags.add(id, 'invalid'), throwsStateError);
        await notes.restore(id);
        expect((await tags.watch(id).first).single.name, 'WPC Guide');
        await tags.remove(id, tag);
        expect(await db.select(db.tags).get(), isEmpty);
        await expectLater(tags.add(id, '### '), throwsArgumentError);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'schema 11 migration retains existing note content and adds tag links',
    () async {
      final dir = await Directory.systemTemp.createTemp('fly-v10-tags-');
      final file = File('${dir.path}/test.db');
      var db = AppDatabase(NativeDatabase(file));
      try {
        final id = await NoteRepository(db).create('迁移前笔记');
        await db.customStatement('DROP TABLE note_tag_links');
        await db.customStatement('PRAGMA user_version = 11');
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        expect((await NoteRepository(db).get(id))!.title, '迁移前笔记');
        expect(await NoteRepository(db).blocks(id), hasLength(1));
        await NoteTagRepository(db).add(id, '迁移后标签');
        expect(await NoteTagRepository(db).watch(id).first, hasLength(1));
        expect(
          (await db.customSelect('PRAGMA foreign_key_check').get()),
          isEmpty,
        );
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
