import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/notes/data/note_repository.dart';
import 'package:fly/features/notes/domain/note_block.dart';
import 'package:fly/features/notes/presentation/note_edit_session.dart';

class DelayedNotes extends NoteRepository {
  DelayedNotes(super.db);
  final entered = Completer<void>();
  final proceed = Completer<void>();
  var calls = 0;
  @override
  Future<int> save(
    String id, {
    required String title,
    required List<NoteBlock> blocks,
    required int expectedRevision,
  }) async {
    if (calls++ == 0) {
      entered.complete();
      await proceed.future;
    }
    return super.save(
      id,
      title: title,
      blocks: blocks,
      expectedRevision: expectedRevision,
    );
  }
}

class UnwritableDrafts extends NoteRepository {
  UnwritableDrafts(super.db);
  @override
  Future<void> writeDraft(String id, NoteDraft draft) async =>
      throw const FileSystemException('Simulated disk full');
}

void main() {
  test('Failed draft write must not be reported as safe to close', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = UnwritableDrafts(db);
    final id = await repo.create('原始内容');
    final session = NoteEditSession(
      repository: repo,
      id: id,
      title: '原始内容',
      blocks: await repo.blocks(id),
      revision: 1,
      delay: const Duration(days: 1),
    );
    try {
      session.edit(title: '尚未落盘');
      await expectLater(session.flush(), throwsA(isA<FileSystemException>()));
      expect(session.draftProtected, false);
      expect(session.dirty, true);
      expect((await repo.get(id))!.title, '原始内容');
    } finally {
      session.dispose();
      await db.close();
    }
  });
  test(
    'Draft survives database close and reopen with original note intact',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fly-draft-restart-',
      );
      final file = File('${directory.path}/test.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      try {
        var repo = NoteRepository(db);
        final id = await repo.create('原文');
        final blocks = await repo.blocks(id);
        await repo.save(id, title: '新版本', blocks: blocks, expectedRevision: 1);
        final session = NoteEditSession(
          repository: repo,
          id: id,
          title: '原文',
          blocks: blocks,
          revision: 1,
          delay: const Duration(days: 1),
        );
        session.edit(title: '必须恢复的草稿');
        await expectLater(session.flush(), throwsA(isA<NoteConflict>()));
        expect(session.draftProtected, true);
        session.dispose();
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        repo = NoteRepository(db);
        final draft = await repo.readDraft(id);
        expect(draft!.title, '必须恢复的草稿');
        final copy = await repo.recoverCopy(id, draft);
        expect((await repo.get(id))!.title, '新版本');
        expect((await repo.get(copy))!.title, contains('必须恢复的草稿'));
        expect(await repo.readDraft(id), isNull);
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'Typing during save is serialized and the newest draft is persisted',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = DelayedNotes(db);
      final id = await repo.create('初始');
      final session = NoteEditSession(
        repository: repo,
        id: id,
        title: '初始',
        blocks: await repo.blocks(id),
        revision: 1,
        delay: const Duration(days: 1),
      );
      try {
        session.edit(title: '第一次');
        final saving = session.flush();
        await repo.entered.future;
        session.edit(title: '继续输入');
        repo.proceed.complete();
        await saving;
        expect((await repo.get(id))!.title, '继续输入');
        expect(repo.calls, 2);
        expect(session.dirty, false);
        expect(session.error, isNull);
        expect(await repo.readDraft(id), isNull);
      } finally {
        session.dispose();
        await db.close();
      }
    },
  );

  test(
    'Revision conflict keeps draft and does not overwrite remote changes',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = NoteRepository(db);
      final id = await repo.create('初始');
      final blocks = await repo.blocks(id);
      final session = NoteEditSession(
        repository: repo,
        id: id,
        title: '初始',
        blocks: blocks,
        revision: 1,
        delay: const Duration(days: 1),
      );
      try {
        await repo.save(
          id,
          title: '其它窗口更新',
          blocks: blocks,
          expectedRevision: 1,
        );
        session.edit(title: '本地草稿');
        await expectLater(session.flush(), throwsA(isA<NoteConflict>()));
        expect(session.title, '本地草稿');
        expect(session.dirty, true);
        expect((await repo.get(id))!.title, '其它窗口更新');
        final persisted = await repo.readDraft(id);
        expect(persisted!.title, '本地草稿');
        final reopened = NoteEditSession(
          repository: repo,
          id: id,
          title: '其它窗口更新',
          blocks: blocks,
          revision: 2,
          delay: const Duration(days: 1),
        );
        reopened.restore(persisted, currentRevision: 2);
        try {
          await expectLater(reopened.flush(), throwsA(isA<NoteConflict>()));
          final copyId = await reopened.recoverCopy();
          expect((await repo.get(copyId))!.title, contains('本地草稿'));
          expect((await repo.get(id))!.title, '其它窗口更新');
          expect(await repo.readDraft(id), isNull);
          expect((await repo.blocks(copyId)).first.id, isNot(blocks.first.id));
        } finally {
          reopened.dispose();
        }
        await expectLater(session.flush(), throwsA(isA<NoteConflict>()));
      } finally {
        session.dispose();
        await db.close();
      }
    },
  );
}
