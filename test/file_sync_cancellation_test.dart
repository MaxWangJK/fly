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

class _NoNetwork implements SyncTransport {
  int requests = 0;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? body,
  }) async {
    requests++;
    throw StateError('Cancelled work must not send network requests');
  }

  @override
  void close() {}
  @override
  Future<void> download(String path, String destination) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> uploadChunk(String path, List<int> chunk) =>
      throw UnimplementedError();
}

void main() {
  test('disconnect stops scanning after the in-progress digest', () async {
    final root = await Directory.systemTemp.createTemp('fly-scan-cancel-');
    final db = AppDatabase(NativeDatabase.memory());
    final network = _NoNetwork();
    final started = Completer<void>(), release = Completer<String>();
    var checks = 0;
    const bytes = [1, 2, 3, 4];
    final hash = sha256.convert(bytes).toString();
    try {
      await db.ensureBuiltInData();
      for (var i = 0; i < 2; i++) {
        final relative = 'files/$i/item.txt';
        final file = File('${root.path}/$relative');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
        await ManagedFileRepository(db).commit(
          ImportedFile(
            id: 'file-$i',
            relativePath: relative,
            name: 'item.txt',
            size: bytes.length,
            sha256: hash,
          ),
          duplicateAction: DuplicateFileAction.keepCopy,
        );
      }
      final service = FileSyncService(
        db,
        root.path,
        network,
        digests: FileDigestCache(
          digestFile: (_) {
            checks++;
            if (!started.isCompleted) started.complete();
            return release.future;
          },
        ),
      );
      final work = service.synchronize(uploadOnly: true);
      await started.future.timeout(const Duration(seconds: 3));
      service.cancel();
      release.complete(hash);
      await work;
      expect(checks, 1);
      expect(network.requests, 0);
      expect(service.phase, 'idle');
      expect(service.currentFile, isNull);
    } finally {
      if (!release.isCompleted) release.complete(hash);
      await db.close();
      await root.delete(recursive: true);
    }
  });
}
