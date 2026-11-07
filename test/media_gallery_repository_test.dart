import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/shared/data/workspace_folder_repository.dart';

void main() {
  test('gallery stays in the same library folder and excludes deleted files/videos', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = ManagedFileRepository(db);
    try {
      final folder = await WorkspaceFolderRepository(
        db,
        WorkspaceFolderKind.files,
      ).create('归档');
      for (final record in [
        ('one', 'one.jpg', null),
        ('two', 'two.png', null),
        ('heic', 'three.heic', null),
        ('deleted', 'deleted.jpg', null),
        ('video', 'demo.mov', null),
        ('other', 'other.jpg', folder),
      ]) {
        await repo.commit(
          ImportedFile(
            id: record.$1,
            name: record.$2,
            relativePath: 'files/${record.$2}',
            size: 1,
            sha256: record.$1,
          ),
          folderId: record.$3,
        );
      }
      await repo.remove('deleted');
      final gallery = await repo.imagesInLocation((await repo.find('one'))!);
      expect(gallery.map((f) => f.id), unorderedEquals(['one', 'two', 'heic']));
      expect(
        (await repo.imagesInLocation((await repo.find('other'))!))
            .map((f) => f.id),
        ['other'],
      );
      expect((await repo.find('video'))!.mimeType, 'video/quicktime');
    } finally {
      await db.close();
    }
  });

  test(
    'business galleries do not include another customer, order or library root',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = ManagedFileRepository(db);
      try {
        for (final row in [
          ('c1-a', 'customer', 'customer-one'),
          ('c1-b', 'customer', 'customer-one'),
          ('c2', 'customer', 'customer-two'),
          ('order', 'order', 'customer-one'),
          ('library', 'library', 'library'),
        ]) {
          await db
              .into(db.attachments)
              .insert(
                AttachmentsCompanion.insert(
                  id: row.$1,
                  ownerType: row.$2,
                  ownerId: row.$3,
                  fileName: '${row.$1}.jpg',
                  originalName: '${row.$1}.jpg',
                  relativePath: 'files/${row.$1}.jpg',
                  fileSize: 1,
                  mimeType: const Value('image/jpeg'),
                  createdAt: DateTime(2026),
                  updatedAt: DateTime(2026),
                ),
              );
        }
        expect(
          (await repo.imagesInLocation((await repo.find('c1-a'))!))
              .map((f) => f.id),
          unorderedEquals(['c1-a', 'c1-b']),
        );
      } finally {
        await db.close();
      }
    },
  );
}
