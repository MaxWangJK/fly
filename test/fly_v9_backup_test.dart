import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:fly/core/database/app_database.dart';
import 'package:fly/shared/backup/backup_service.dart';
import 'package:fly/shared/backup/library_backup_store.dart';

void main() {
  test(
    'backup rejects custom directories nested inside business data',
    () async {
      final root = await Directory.systemTemp.createTemp('fly-backup-path-');
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final data = p.join(root.path, 'data');
        final service = FlyBackupService(database: db, dataRootPath: data);
        final nested = p.join(data, 'files', 'backup');
        await expectLater(
          service.createBackup(directory: nested),
          throwsArgumentError,
        );
        expect(await Directory(nested).exists(), isFalse);
        final backup = await service.createBackup(now: DateTime(2026, 9, 29));
        expect(backup.parent.path, p.join(data, 'backups'));
      } finally {
        await db.close();
        await root.delete(recursive: true);
      }
    },
  );

  test('V9 library snapshots reuse immutable objects and restore verifies missing/corrupt data', () async {
    final root = await Directory.systemTemp.createTemp('fly-v9-backup-');
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await db.ensureBuiltInData();
      final data = p.join(root.path, 'data');
      final backups = p.join(root.path, 'backups');
      final source = File(p.join(data, 'files', 'folder', 'uuid', '报价单.pdf'));
      await source.parent.create(recursive: true);
      await source.writeAsBytes(List.generate(10000, (i) => i % 250));
      final cache = File(p.join(data, 'cache', 'thumbnails', 'test.png'));
      await cache.parent.create(recursive: true);
      await cache.writeAsBytes([1, 2, 3]);
      final service = FlyBackupService(database: db, dataRootPath: data);
      final a = await service.createBackup(
        directory: backups,
        now: DateTime(2026, 9, 8),
      );
      await service.createBackup(directory: backups, now: DateTime(2026, 9, 9));
      final objects = await Directory(
        p.join(backups, LibraryBackupStore.objectDirectory),
      ).list().toList();
      expect(objects.whereType<File>(), hasLength(1));
      final prepared = await service.prepareRestore(a.path);
      try {
        expect(
          await File(
            p.join(
              prepared.directory.path,
              'files',
              'folder',
              'uuid',
              '报价单.pdf',
            ),
          ).readAsBytes(),
          await source.readAsBytes(),
        );
        expect(
          await Directory(p.join(prepared.directory.path, 'cache')).exists(),
          isFalse,
        );
      } finally {
        await prepared.dispose();
      }
      final object = objects.whereType<File>().single;
      await object.writeAsBytes(List.filled(10000, 0));
      await expectLater(service.prepareRestore(a.path), throwsStateError);
      await object.delete();
      await expectLater(service.prepareRestore(a.path), throwsStateError);
    } finally {
      await db.close();
      await root.delete(recursive: true);
    }
  });
  test(
    'V9 library manifest rejects traversal before materializing objects',
    () async {
      final root = await Directory.systemTemp.createTemp('fly-v9-manifest-');
      try {
        final stage = p.join(root.path, 'stage');
        await Directory(stage).create();
        await File(
          p.join(stage, LibraryBackupStore.manifestName),
        ).writeAsString(
          jsonEncode({
            'version': 1,
            'files': [
              {'relativePath': '../escape.bin', 'sha256': 'a' * 64, 'size': 1},
            ],
          }),
        );
        await expectLater(
          LibraryBackupStore().restore(
            packageDirectory: root.path,
            stage: stage,
          ),
          throwsFormatException,
        );
        expect(await File(p.join(root.path, 'escape.bin')).exists(), isFalse);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
