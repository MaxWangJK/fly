import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/core/storage/file_digest_cache.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/sync/domain/sync_protocol.dart';
import 'package:fly/features/sync/services/file_sync_service.dart';

class _Remote implements SyncTransport {
  int uploads = 0;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? body,
  }) async {
    if (path == '/files/upload/init') {
      uploads++;
      return {'exists': true};
    }
    throw StateError('Unexpected request: $path');
  }

  @override
  Future<Map<String, dynamic>> uploadChunk(String path, List<int> chunk) =>
      throw UnimplementedError();
  @override
  Future<void> download(String path, String destination) =>
      throw UnimplementedError();
  @override
  void close() {}
}

void main() {
  test(
    'unchanged files reuse verified bytes, edits and audit expiry rehash',
    () async {
      final root = await Directory.systemTemp.createTemp('fly-digest-');
      addTearDown(() => root.delete(recursive: true));
      final file = await File('${root.path}/video.mp4').writeAsString('first');
      var now = DateTime.utc(2026, 11, 12);
      var reads = 0;
      final cache = FileDigestCache(
        now: () => now,
        digestFile: (path) async {
          reads++;
          return sha256FileInBackground(path);
        },
      );
      final first = await cache.digest(file);
      await file
          .readAsBytes(); // Playing/reading is not a content modification.
      expect(await cache.digest(file), first);
      expect(reads, 1);
      await file.writeAsString('other'); // Same length, different content.
      await file.setLastModified(now.add(const Duration(seconds: 1)));
      final changed = await cache.digest(file);
      expect(changed, isNot(first));
      expect(reads, 2);
      now = now.add(const Duration(minutes: 4));
      expect(await cache.digest(file), changed);
      expect(reads, 2);
      now = now.add(const Duration(minutes: 1));
      expect(await cache.digest(file), changed);
      expect(reads, 3);
      await cache.digest(file, refresh: true);
      expect(reads, 4);
      await file.delete();
      await expectLater(
        cache.digest(file),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'simultaneous checks share work and a changing file is not cached',
    () async {
      final root = await Directory.systemTemp.createTemp('fly-digest-race-');
      addTearDown(() => root.delete(recursive: true));
      final file = await File('${root.path}/source').writeAsString('A');
      final gate = Completer<void>();
      var reads = 0;
      final cache = FileDigestCache(
        digestFile: (path) async {
          reads++;
          await gate.future;
          return sha256FileInBackground(path);
        },
      );
      final checks = [
        cache.digest(file),
        cache.digest(file),
        cache.digest(file),
      ];
      gate.complete();
      expect((await Future.wait(checks)).toSet(), hasLength(1));
      expect(reads, 1);
      var changing = 0;
      final unstable = FileDigestCache(
        digestFile: (path) async {
          changing++;
          final hash = await sha256FileInBackground(path);
          await File(path).writeAsString('changed $changing');
          await File(path)
              .setLastModified(DateTime.utc(2026, 11, 12, 0, 0, changing));
          return hash;
        },
      );
      await expectLater(
        unstable.digest(file),
        throwsA(isA<FileSystemException>()),
      );
      expect(changing, 2);
      await expectLater(
        unstable.digest(file),
        throwsA(isA<FileSystemException>()),
      );
      expect(changing, 4);
    },
  );

  test('bounded cache evicts older files and failed reads can retry', () async {
    final root = await Directory.systemTemp.createTemp('fly-digest-bounds-');
    addTearDown(() => root.delete(recursive: true));
    final a = await File('${root.path}/a').writeAsString('A');
    final b = await File('${root.path}/b').writeAsString('B');
    var reads = 0;
    final cache = FileDigestCache(
      maxEntries: 1,
      digestFile: (path) async {
        reads++;
        if (reads == 1) throw const FileSystemException('Fixture failure');
        return sha256FileInBackground(path);
      },
    );
    await expectLater(cache.digest(a), throwsA(isA<FileSystemException>()));
    await cache.digest(a);
    await cache.digest(b);
    await cache.digest(a);
    expect(reads, 4);
  });

  test('LAN upload pass, download pass and polling do not reread an unchanged video', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final root = await Directory.systemTemp.createTemp('fly-sync-digest-');
    addTearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });
    await db.ensureBuiltInData();
    final source = await File('${root.path}/clip.mp4')
        .writeAsBytes(List.filled(2 * 1024 * 1024, 37));
    final storage = ManagedFileStorage(root.path);
    final imported = await storage.import(source.path);
    await ManagedFileRepository(db).commit(imported);
    var reads = 0;
    final cache = FileDigestCache(
      digestFile: (path) async {
        reads++;
        return sha256FileInBackground(path);
      },
    );
    final remote = _Remote();
    final sync = FileSyncService(db, root.path, remote, digests: cache);
    await sync.synchronize(uploadOnly: true);
    await sync.synchronize();
    await sync.synchronize(uploadOnly: true);
    await sync.synchronize();
    expect(reads, 1);
    expect(remote.uploads, 4);
    final local = File(storage.absolute(imported.relativePath));
    await local.writeAsString('External edit');
    await sync.synchronize(uploadOnly: true);
    final record = await ManagedFileRepository(db).find(imported.id);
    expect(
      record!.sha256,
      sha256.convert('External edit'.codeUnits).toString(),
    );
    expect(reads, 2);
    expect(await local.readAsString(), 'External edit');
  });
}
