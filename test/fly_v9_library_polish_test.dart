import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/files/data/file_folder_actions.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/files/data/thumbnail_cache.dart';
import 'package:fly/features/notes/data/note_repository.dart';
import 'package:fly/features/notes/domain/note_block.dart';
import 'package:fly/shared/data/workspace_folder_repository.dart';

class RecordingCache extends ThumbnailCache {
  RecordingCache() : super(ManagedFileStorage('unused-test-root'));
  final removed = <String>[];
  String? failId;
  @override
  Future<void> remove(AttachmentRecord file) async {
    removed.add(file.id);
    if (file.id == failId) throw const FileSystemException('Cache locked');
  }
}

void main() {
  test('Folder locations follow logical moves and deletion clears only subtree cache', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final folders = WorkspaceFolderRepository(db, WorkspaceFolderKind.files);
      final source = await folders.create('原目录');
      final destination = await folders.create('目标目录');
      final child = await folders.create('子目录', parentId: destination);
      final files = ManagedFileRepository(db);
      for (final (id, folder) in [
        ('moved', source),
        ('nested', child),
        ('outside', source),
      ]) {
        await files.commit(
          ImportedFile(
            id: id,
            relativePath: 'files/$folder/$id/example.png',
            name: '$id.png',
            size: 100,
            sha256: id,
          ),
          folderId: folder,
        );
      }
      final originalPath = (await files.find('moved'))!.relativePath;
      await files.move('moved', destination);
      final cache = RecordingCache()..failId = 'nested';
      final actions = FileFolderActions(db, folders, cache);
      final direct = await actions.directFiles(destination);
      expect(direct.single.id, 'moved');
      expect(direct.single.relativePath, originalPath);
      expect(await actions.remove(destination), 1);
      expect(cache.removed, unorderedEquals(['moved', 'nested']));
      expect((await files.find('outside'))!.deletedAt, isNull);
      expect((await files.find('moved'))!.deletedAt, isNotNull);
      expect(await actions.directFiles(destination), isEmpty);
      await folders.restore(destination);
      expect((await files.find('moved'))!.relativePath, originalPath);
      expect((await files.find('nested'))!.deletedAt, isNull);
    } finally {
      await db.close();
    }
  });

  test(
    'Note previews update, normalize whitespace and bound Unicode safely',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final repo = NoteRepository(db);
        final id = await repo.create('外贸知识');
        await repo.save(
          id,
          title: '外贸知识',
          expectedRevision: 1,
          blocks: [
            NoteBlock(
              id: 'a',
              type: 'paragraph',
              content: {'text': '客户\n  沟通方法'},
            ),
            NoteBlock(
              id: 'b',
              type: 'image',
              content: {'attachmentId': 'demo', 'caption': '产品示例'},
            ),
            NoteBlock(id: 'c', type: 'divider', content: {}),
            NoteBlock(id: 'd', type: 'paragraph', content: {'text': '第四块不读取'}),
          ],
        );
        expect(await repo.watchPreview(id).first, '客户 沟通方法 · 产品示例');
        await repo.save(
          id,
          title: '外贸知识',
          expectedRevision: 2,
          blocks: [
            NoteBlock(
              id: 'a',
              type: 'paragraph',
              content: {'text': '😀' * 200},
            ),
          ],
        );
        final preview = await repo.watchPreview(id).first;
        expect(preview.runes.length, 160);
        expect(preview, '😀' * 160);
      } finally {
        await db.close();
      }
    },
  );
}
