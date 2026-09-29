import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/notes/data/note_repository.dart';
import 'package:fly/features/notes/domain/note_block.dart';
import 'package:fly/shared/data/workspace_folder_repository.dart';

void main() {
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureBuiltInData();
  });
  tearDown(() async {
    await db.close();
  });
  for (final kind in WorkspaceFolderKind.values) {
    test(
      'V9 $kind folders: nested, cycle protection, soft delete batch and restore',
      () async {
        final repo = WorkspaceFolderRepository(db, kind);
        final root = await repo.create('产品');
        final child = await repo.create('墙板', parentId: root);
        final leaf = await repo.create('WPC', parentId: child);
        final alreadyDeleted = await repo.create('旧资料', parentId: root);
        await repo.remove(alreadyDeleted);
        await expectLater(repo.move(root, leaf), throwsStateError);
        await expectLater(repo.create('墙板', parentId: root), throwsStateError);
        await repo.remove(root);
        expect(await repo.watch().first, isEmpty);
        await repo.restore(root);
        expect(
          (await repo.watch().first).map((r) => r.id),
          unorderedEquals([root, child, leaf]),
        );
        expect(
          (await repo.all())
              .firstWhere((r) => r.id == alreadyDeleted)
              .deletedAt,
          isNotNull,
        );
        await repo.rename(leaf, '新 WPC');
        await repo.move(leaf, null);
        expect(
          (await repo.all()).firstWhere((r) => r.id == leaf).parentId,
          isNull,
        );
      },
    );
  }
  test('V9 note block persistence, order, optimistic conflict and unknown preservation', () async {
    final repo = NoteRepository(db);
    final id = await repo.create('客户开发方法');
    final blocks = [
      NoteBlock(id: 'a', type: 'heading1', content: {'text': '客户开发'}),
      NoteBlock(
        id: 'b',
        type: 'checklist',
        content: {'text': '发送报价', 'checked': true},
      ),
      NoteBlock(
        id: 'c',
        type: 'table',
        content: {
          'rows': [
            ['产品', '市场'],
            ['WPC', '菲律宾'],
          ],
        },
      ),
      const NoteBlock.encoded(
        id: 'future',
        type: 'futureBlock',
        contentJson: '{"opaque":[1,2,3]}',
      ),
    ];
    expect(
      await repo.save(id, title: '方法', blocks: blocks, expectedRevision: 1),
      2,
    );
    expect((await repo.blocks(id)).map((b) => b.id), ['a', 'b', 'c', 'future']);
    await expectLater(
      repo.save(id, title: '冲突', blocks: [], expectedRevision: 1),
      throwsA(isA<NoteConflict>()),
    );
    expect((await repo.get(id))!.title, '方法');
    await repo.save(
      id,
      title: '方法',
      blocks: blocks.reversed.toList(),
      expectedRevision: 2,
    );
    expect((await repo.blocks(id)).first.contentJson, '{"opaque":[1,2,3]}');
    await repo.favorite(id, true);
    expect(await repo.watch(favorites: true).first, hasLength(1));
    await repo.remove(id);
    expect(await repo.watch(recent: true).first, isEmpty);
    await repo.restore(id);
    expect(await repo.blocks(id), hasLength(4));
  });
  test('V9 Markdown prefixes and block validation', () {
    for (final prefix in ['# ', '## ', '### ', '- ', '1. ', '[] ', '- [ ] ']) {
      expect(NoteBlock.shortcut(prefix), isNotNull);
    }
    // V11 keeps existing quote blocks readable but does not create them with
    // the legacy Markdown shortcut.
    expect(NoteBlock.shortcut('> '), isNull);
    expect(NoteBlock.shortcut('hello # '), isNull);
    expect(
      () => NoteBlock(
        id: 'x',
        type: 'checklist',
        content: {'text': 'a', 'checked': 'false'},
      ).validate(),
      throwsArgumentError,
    );
    expect(
      () => NoteBlock(
        id: 'x',
        type: 'table',
        content: {
          'rows': [
            ['a'],
            ['b', 'c'],
          ],
        },
      ).validate(),
      throwsArgumentError,
    );
  });
  test('V9 managed import hashes, duplicates, moves, independent tags and recycling', () async {
    final root = await Directory.systemTemp.createTemp('fly-v9-files-');
    try {
      final source = File(p.join(root.path, 'source.pdf'));
      await source.writeAsBytes(List.generate(10000, (i) => i % 256));
      final storage = ManagedFileStorage(p.join(root.path, 'FlyData'));
      final files = ManagedFileRepository(db);
      final folders = WorkspaceFolderRepository(db, WorkspaceFolderKind.files);
      final folder = await folders.create('价格表');
      var progress = 0;
      final a = await storage.import(
        source.path,
        folderId: folder,
        progress: (copied, total) {
          progress = copied;
        },
      );
      expect(progress, 10000);
      expect(a.sha256, hasLength(64));
      await files.commit(a, folderId: folder);
      final b = await storage.import(source.path, folderId: folder);
      await expectLater(
        files.commit(b, folderId: folder),
        throwsA(isA<DuplicateManagedFile>()),
      );
      expect(
        await files.commit(
          b,
          folderId: folder,
          duplicateAction: DuplicateFileAction.skip,
        ),
        isNull,
      );
      await storage.discard(b);
      final c = await storage.import(source.path, folderId: folder);
      await files.commit(
        c,
        folderId: folder,
        duplicateAction: DuplicateFileAction.replace,
      );
      expect((await files.find(a.id))!.deletedAt, isNotNull);
      expect(await File(storage.absolute(a.relativePath)).exists(), isTrue);
      final tag = await files.createTag('WPC');
      expect(await files.createTag('wpc'), tag);
      await files.setTag(c.id, tag, true);
      expect(await files.watchLinks().first, hasLength(1));
      await files.move(c.id, null);
      expect((await files.find(c.id))!.folderId, isNull);
      await files.remove(c.id);
      await files.restore(c.id);
      expect((await files.find(c.id))!.deletedAt, isNull);
      expect(() => storage.absolute('../escape.txt'), throwsArgumentError);
      expect(() => storage.absolute(source.path), throwsArgumentError);
    } finally {
      await root.delete(recursive: true);
    }
  });
  test('V9 cancellation cleans partial files before and after copy', () async {
    final root = await Directory.systemTemp.createTemp('fly-v9-cancel-');
    try {
      final source = File(p.join(root.path, 'source.bin'));
      await source.writeAsBytes(List.filled(256000, 2));
      final storage = ManagedFileStorage(p.join(root.path, 'FlyData'));
      final early = ImportCancellation()..cancel();
      await expectLater(
        storage.import(source.path, cancellation: early),
        throwsA(isA<ImportCancelled>()),
      );
      final late = ImportCancellation();
      await expectLater(
        storage.import(
          source.path,
          cancellation: late,
          progress: (count, total) {
            if (count == total) late.cancel();
          },
        ),
        throwsA(isA<ImportCancelled>()),
      );
      expect(
        (await Directory(
          storage.root,
        ).list(recursive: true).toList()).whereType<File>(),
        isEmpty,
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
  test(
    'V9 schema 10 migration preserves task and original customer attachment',
    () async {
      final root = await Directory.systemTemp.createTemp('fly-v9-migrate-');
      final file = File(p.join(root.path, 'old.db'));
      final previous = drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      AppDatabase? old;
      AppDatabase? reopened;
      try {
        old = AppDatabase(NativeDatabase(file));
        await old.ensureBuiltInData();
        final now = DateTime.now();
        await old
            .into(old.tasks)
            .insert(
              TasksCompanion.insert(
                id: 'legacy-task',
                title: '原有任务',
                sortOrder: 0,
                createdAt: now,
                updatedAt: now,
              ),
            );
        await old
            .into(old.attachments)
            .insert(
              AttachmentsCompanion.insert(
                id: 'legacy-file',
                ownerType: 'customer',
                ownerId: 'Jack',
                fileName: 'x.pdf',
                originalName: '报价单.pdf',
                relativePath: 'attachments/customers/Jack/x.pdf',
                fileSize: 10,
                createdAt: now,
                updatedAt: now,
              ),
            );
        for (final table in [
          'note_blocks',
          'workspace_notes',
          'note_folders',
          'file_tag_links',
          'file_tags',
        ]) {
          await old.customStatement('DROP TABLE $table');
        }
        for (final index in ['idx_files_folder', 'idx_files_hash']) {
          await old.customStatement('DROP INDEX $index');
        }
        for (final column in [
          'folder_id',
          'display_name',
          'sha256',
          'thumbnail_relative_path',
          'last_opened_at',
          'deletion_batch',
        ]) {
          await old.customStatement(
            'ALTER TABLE attachments DROP COLUMN $column',
          );
        }
        await old.customStatement('DROP TABLE file_folders');
        await old.customStatement('PRAGMA user_version=10');
        await old.close();
        old = null;
        reopened = AppDatabase(NativeDatabase(file));
        final attachment = await reopened
            .select(reopened.attachments)
            .getSingle();
        expect(attachment.displayName, '报价单.pdf');
        expect(attachment.ownerType, 'customer');
        expect(attachment.relativePath, 'attachments/customers/Jack/x.pdf');
        expect(
          (await reopened.select(reopened.tasks).getSingle()).title,
          '原有任务',
        );
        expect(await reopened.select(reopened.noteBlocks).get(), isEmpty);
      } finally {
        await old?.close();
        await reopened?.close();
        drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous;
        await root.delete(recursive: true);
      }
    },
  );
}
