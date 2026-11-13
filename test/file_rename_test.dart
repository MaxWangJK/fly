import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/core/storage/data_root_providers.dart';
import 'package:fly/features/files/data/file_batch_actions.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/files/presentation/file_providers.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppDatabase db;
  late ProviderContainer container;
  late ManagedFileStorage storage;
  late ManagedFileRepository repo;
  late ImportedFile imported;
  late File source;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fly-rename-');
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureBuiltInData();
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        dataRootPathProvider.overrideWithValue(root.path),
      ],
    );
    storage = container.read(managedFileStorageProvider);
    repo = container.read(managedFileRepositoryProvider);
    source = await File(p.join(root.path, 'Original.pdf'))
        .writeAsString('Synthetic PDF bytes');
    imported = await storage.import(source.path);
    await repo.commit(imported);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
    await root.delete(recursive: true);
  });

  test(
    'rename changes the managed file and all opening and sharing names',
    () async {
      final original = (await repo.find(imported.id))!;
      await repo.rename(imported.id, 'Installation guide.pdf');
      final renamed = (await repo.find(imported.id))!;
      expect(
        await File(storage.absolute(imported.relativePath)).exists(),
        isFalse,
      );
      expect(p.basename(renamed.relativePath), 'Installation guide.pdf');
      expect(
        await File(storage.absolute(renamed.relativePath)).readAsString(),
        'Synthetic PDF bytes',
      );
      expect(renamed.fileName, 'Installation guide.pdf');
      expect(renamed.originalName, 'Installation guide.pdf');
      expect(renamed.displayName, 'Installation guide.pdf');
      expect(renamed.sha256, original.sha256);
      expect(renamed.fileSize, original.fileSize);
      expect(renamed.ownerId, original.ownerId);
      expect(await source.readAsString(), 'Synthetic PDF bytes');
      final share = await FileBatchActions(
        db,
        storage,
      ).prepareShare({renamed.id});
      try {
        expect(share.files.single.name, 'Installation guide.pdf');
        expect(
          await File(share.files.single.path).readAsString(),
          'Synthetic PDF bytes',
        );
      } finally {
        await share.cleanup();
      }
    },
  );

  test('omitted extension is preserved and case-only rename works', () async {
    await repo.rename(imported.id, 'Product');
    expect((await repo.find(imported.id))!.fileName, 'Product.pdf');
    await repo.rename(imported.id, 'product.pdf');
    final renamed = (await repo.find(imported.id))!;
    expect(renamed.fileName, 'product.pdf');
    expect(p.basename(renamed.relativePath), 'product.pdf');
    expect(await File(storage.absolute(renamed.relativePath)).exists(), isTrue);
  });

  test(
    'existing target is never overwritten and metadata remains unchanged',
    () async {
      final before = (await repo.find(imported.id))!;
      final target = File(
        p.join(p.dirname(storage.absolute(before.relativePath)), 'Taken.pdf'),
      );
      await target.writeAsString('Keep existing bytes');
      await expectLater(
        repo.rename(imported.id, 'Taken.pdf'),
        throwsStateError,
      );
      expect(await target.readAsString(), 'Keep existing bytes');
      expect(await repo.find(imported.id), before);
      expect(
        await File(storage.absolute(before.relativePath)).readAsString(),
        'Synthetic PDF bytes',
      );
    },
  );

  test('database failure restores the physical name', () async {
    final before = (await repo.find(imported.id))!;
    await db.customStatement(
      "CREATE TRIGGER reject_file_rename BEFORE UPDATE OF file_name ON attachments BEGIN SELECT RAISE(ABORT, 'synthetic write failure'); END",
    );
    await expectLater(
      repo.rename(imported.id, 'Rejected.pdf'),
      throwsA(isA<Exception>()),
    );
    expect(await repo.find(imported.id), before);
    expect(
      await File(storage.absolute(before.relativePath)).readAsString(),
      'Synthetic PDF bytes',
    );
    expect(
      await File(
        p.join(
          p.dirname(storage.absolute(before.relativePath)),
          'Rejected.pdf',
        ),
      ).exists(),
      isFalse,
    );
  });

  test(
    'undownloaded metadata keeps the future download name and extension',
    () async {
      await File(storage.absolute(imported.relativePath)).delete();
      await repo.rename(imported.id, 'Pending');
      final record = (await repo.find(imported.id))!;
      expect(record.fileName, 'Pending.pdf');
      expect(p.basename(record.relativePath), 'Pending.pdf');
    },
  );

  test(
    'an undownloaded file cannot adopt an unrelated existing target',
    () async {
      final before = (await repo.find(imported.id))!;
      await File(storage.absolute(before.relativePath)).delete();
      final target = await File(
        p.join(p.dirname(storage.absolute(before.relativePath)), 'Taken.pdf'),
      ).writeAsString('Unrelated content');
      await expectLater(
        repo.rename(imported.id, 'Taken.pdf'),
        throwsStateError,
      );
      expect(await repo.find(imported.id), before);
      expect(await target.readAsString(), 'Unrelated content');
    },
  );

  test('invalid and nonportable names do not touch the original', () async {
    final before = (await repo.find(imported.id))!;
    for (final name in [
      '../outside.pdf',
      r'..\outside.pdf',
      'CON.pdf',
      'trailing.',
    ]) {
      await expectLater(repo.rename(imported.id, name), throwsArgumentError);
      expect(await repo.find(imported.id), before);
      expect(
        await File(storage.absolute(before.relativePath)).exists(),
        isTrue,
      );
    }
  });

  test(
    'renaming preserves a known MIME type when the extension is unchanged',
    () async {
      await (db.update(
        db.attachments,
      )..where((r) => r.id.equals(imported.id))).write(
        const AttachmentsCompanion(
          mimeType: Value('application/vnd.synthetic+pdf'),
        ),
      );
      await repo.rename(imported.id, 'Updated.pdf');
      expect(
        (await repo.find(imported.id))!.mimeType,
        'application/vnd.synthetic+pdf',
      );
    },
  );

  test('deleted or missing records cannot rename disk content', () async {
    await repo.remove(imported.id);
    final before = (await repo.find(imported.id))!;
    await expectLater(
      repo.rename(imported.id, 'Deleted.pdf'),
      throwsStateError,
    );
    await expectLater(
      repo.rename('missing-id', 'Missing.pdf'),
      throwsStateError,
    );
    expect(await repo.find(imported.id), before);
    expect(await File(storage.absolute(before.relativePath)).exists(), isTrue);
  });
}
