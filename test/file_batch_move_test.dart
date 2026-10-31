import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/files/data/file_batch_actions.dart';
import 'package:fly/features/files/data/file_browser_query.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/shared/data/workspace_folder_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late Directory root;
  late ManagedFileRepository files;
  late WorkspaceFolderRepository folders;
  late ManagedFileStorage storage;
  late FileBatchActions actions;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureBuiltInData();
    root = await Directory.systemTemp.createTemp('fly-batch-move-');
    files = ManagedFileRepository(db);
    folders = WorkspaceFolderRepository(db, WorkspaceFolderKind.files);
    storage = ManagedFileStorage(root.path);
    actions = FileBatchActions(db, storage);
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  Future<void> add(String id, String? folderId) => files.commit(
    ImportedFile(
      id: id,
      relativePath: 'files/$id/photo.jpg',
      name: 'photo.jpg',
      size: 3,
      sha256: id,
    ),
    folderId: folderId,
  );

  test('dozens of mixed-location files move without replacing same-name items or bytes', () async {
    final source = await folders.create('Source');
    final target = await folders.create('Target');
    final nested = await folders.create('Photos', parentId: target);
    final ids = {
      for (var i = 0; i < 25; i++) 'image-$i',
      'root-file',
      'already',
    };
    for (final id in ids) {
      await add(
        id,
        id == 'already'
            ? nested
            : id == 'root-file'
            ? null
            : source,
      );
    }
    final physical = File(storage.absolute('files/image-0/photo.jpg'));
    await physical.parent.create(recursive: true);
    await physical.writeAsBytes([1, 2, 3]);
    final tag = await files.createTag('Sample');
    await files.setTag('image-0', tag, true);
    final original = (await files.find('image-0'))!;
    final existing = (await files.find('already'))!;
    await db.customStatement('DELETE FROM sync_outbox');
    final progress = <(int, int)>[];
    final result = await actions.move(
      ids,
      nested,
      progress: (a, b) => progress.add((a, b)),
    );
    expect(result.errors, isEmpty);
    expect(result.completed, ids.difference({'already'}));
    expect(result.unchanged, {'already'});
    expect(progress, [for (var i = 1; i <= ids.length; i++) (i, ids.length)]);
    expect((await files.find('already'))!.updatedAt, existing.updatedAt);
    expect(await SyncOutboxRepository(db).pendingRecordCount(), 26);
    final moved = (await files.find('image-0'))!;
    expect(moved.relativePath, original.relativePath);
    expect(moved.sha256, original.sha256);
    expect(moved.ownerId, original.ownerId);
    expect(await files.watchLinks().first, hasLength(1));
    expect(await physical.readAsBytes(), [1, 2, 3]);
    expect(
      await FileBrowserQuery(db)
          .watch(collection: FileCollection.folder, folderId: nested)
          .first,
      hasLength(27),
    );
    final pending = await SyncOutboxRepository(db).pendingCount();
    final repeated = await actions.move(ids, nested);
    expect(repeated.completed, isEmpty);
    expect(repeated.unchanged, ids);
    expect(await SyncOutboxRepository(db).pendingCount(), pending);
    final returned = await actions.move(ids, null);
    expect(returned.completed, ids);
    expect(returned.errors, isEmpty);
    expect(
      await FileBrowserQuery(db).watch(collection: FileCollection.folder).first,
      hasLength(27),
    );
    expect(await physical.readAsBytes(), [1, 2, 3]);
  });

  test(
    'partial failures preserve each protected owner and deleted file',
    () async {
      final target = await folders.create('Target');
      await add('ordinary', null);
      await add('deleted', null);
      await files.remove('deleted');
      const owners = ['customer', 'order', 'payment', 'cost', 'task', 'note'];
      for (final owner in owners) {
        await add(owner, null);
        await (db.update(
          db.attachments,
        )..where((f) => f.id.equals(owner))).write(
          AttachmentsCompanion(
            ownerType: Value(owner),
            ownerId: Value('record-$owner'),
          ),
        );
      }
      final progress = <(int, int)>[];
      final result = await actions.move(
        {'ordinary', 'deleted', 'missing', ...owners},
        target,
        progress: (a, b) => progress.add((a, b)),
      );
      expect(result.completed, {'ordinary'});
      expect(result.unchanged, isEmpty);
      expect(
        result.errors.keys,
        unorderedEquals(['deleted', 'missing', ...owners]),
      );
      expect(progress.last, (9, 9));
      for (final owner in owners) {
        final record = (await files.find(owner))!;
        expect(record.ownerType, owner);
        expect(record.ownerId, 'record-$owner');
        expect(record.folderId, isNull);
        expect(record.deletedAt, isNull);
      }
      expect((await files.find('deleted'))!.deletedAt, isNotNull);
      expect((await files.find('ordinary'))!.folderId, target);
    },
  );

  test(
    'empty selection and invalid or deleted destinations change nothing',
    () async {
      await add('a', null);
      await add('b', null);
      final target = await folders.create('Deleted target');
      await folders.remove(target);
      await db.customStatement('DELETE FROM sync_outbox');
      await expectLater(actions.move({}, null), throwsStateError);
      await expectLater(
        actions.move({'a', 'b'}, 'missing-folder'),
        throwsStateError,
      );
      await expectLater(actions.move({'a', 'b'}, target), throwsStateError);
      expect((await files.find('a'))!.folderId, isNull);
      expect((await files.find('b'))!.folderId, isNull);
      expect(await SyncOutboxRepository(db).pendingCount(), 0);
    },
  );
}
