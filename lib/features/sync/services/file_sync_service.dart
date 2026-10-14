import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../files/data/managed_file_storage.dart';
import '../data/sync_outbox_repository.dart';
import '../data/cloud_sync_transport.dart';
import '../domain/sync_protocol.dart';
import 'file_transfer_inventory.dart';

class FileSyncService {
  FileSyncService(this.db, this.root, this.transport);
  final AppDatabase db;
  final String root;
  final SyncTransport transport;
  int queued = 0;
  int waiting = 0;
  int total = 0, completed = 0, bytesTransferred = 0, bytesTotal = 0;
  String phase = 'idle';
  String? currentFile;
  void Function()? onProgress;
  DateTime? _lastProgress;
  String _scope = 'local';
  void _notify({bool force = false}) {
    final now = DateTime.now();
    if (force ||
        _lastProgress == null ||
        now.difference(_lastProgress!).inMilliseconds >= 100) {
      _lastProgress = now;
      onProgress?.call();
    }
  }

  Future<void> _confirmed(String hash) =>
      SyncOutboxRepository(db)
          .saveState(remoteFileStateKey(_scope, hash), 'true');
  Future<void> synchronize({
    bool uploadOnly = false,
    bool uploadEnabled = true,
    bool downloadEnabled = true,
  }) async {
    final files = await (db.select(
      db.attachments,
    )..where((r) => r.deletedAt.isNull())).get();
    queued = total = files.length;
    completed = 0;
    phase = 'checking';
    _scope = await SyncOutboxRepository(db).state('workspace') ?? 'local';
    _notify(force: true);
    waiting = 0;
    final storage = ManagedFileStorage(root);
    final outbox = SyncOutboxRepository(db);
    for (final record in files) {
      try {
        phase = 'checking';
        currentFile = record.displayName.isEmpty
            ? record.originalName
            : record.displayName;
        bytesTransferred = 0;
        bytesTotal = record.fileSize;
        _notify();
        final id = SyncOutboxRepository.identity(
          'attachments',
          jsonEncode([record.id]),
        );
        final local = File(storage.absolute(record.relativePath));
        var expected = record.sha256;
        var size = record.fileSize;
        if (await local.exists()) {
          final actual = (await sha256.bind(local.openRead()).first).toString();
          final known = await outbox.state('localBlob:${record.id}');
          if (uploadOnly &&
              uploadEnabled &&
              (expected == null || (actual != expected && actual != known))) {
            // Legacy binaries and external edits update metadata and outbox atomically.
            expected = actual;
            size = await local.length();
            await (db.update(
              db.attachments,
            )..where((r) => r.id.equals(record.id))).write(
              AttachmentsCompanion(
                sha256: Value(actual),
                fileSize: Value(size),
                updatedAt: Value(DateTime.now()),
              ),
            );
          }
          if (expected == null) continue;
          if (actual == expected) {
            if (uploadEnabled) await _upload(local, expected);
            await outbox.saveState('localBlob:${record.id}', actual);
            continue;
          }
          if (uploadOnly || !downloadEnabled) continue;
          final preserved = File(
            storage.absolute(
              'files/conflicts/$actual/${local.uri.pathSegments.last}',
            ),
          );
          await preserved.parent.create(recursive: true);
          if (!await preserved.exists()) {
            await local.rename(preserved.path);
          } else {
            await local.delete();
          }
        }
        if (expected == null || uploadOnly || !downloadEnabled) continue;
        final partial = File('${local.path}.part');
        try {
          phase = 'downloading';
          _notify(force: true);
          if (transport is CloudSyncTransport) {
            await (transport as CloudSyncTransport).downloadWithProgress(
              '/files/$id/download',
              partial.path,
              onProgress: (received, _) {
                bytesTransferred = received;
                _notify();
              },
            );
          } else {
            await transport.download('/files/$id/download', partial.path);
          }
          final hash = (await sha256.bind(partial.openRead()).first).toString();
          if (hash != expected || await partial.length() != size) {
            throw StateError('下载文件校验失败');
          }
          await partial.rename(local.path);
          await outbox.saveState('localBlob:${record.id}', hash);
          await _confirmed(hash);
          bytesTransferred = size;
          db.notifyUpdates({const TableUpdate('attachments')});
        } finally {
          if (await partial.exists()) await partial.delete();
        }
      } on SyncHttpException catch (e) {
        // A peer may have published metadata before its file has arrived.
        // Continue with other files and retry missing content next cycle.
        if (e.status != 404) rethrow;
        waiting++;
      } finally {
        queued--;
        completed++;
        _notify(force: true);
      }
    }
    phase = 'idle';
    currentFile = null;
    _notify(force: true);
  }

  Future<void> _upload(File file, String hash) async {
    final size = await file.length();
    bytesTotal = size;
    final upload = await transport.request(
      'POST',
      '/files/upload/init',
      body: {'sha256': hash, 'size': size},
    );
    if (upload['exists'] == true) {
      await _confirmed(hash);
      return;
    }
    var offset = upload['offset'] as int;
    final chunkBytes = upload['chunkBytes'] as int;
    if (chunkBytes < 1 ||
        chunkBytes > 4 * 1024 * 1024 ||
        offset < 0 ||
        offset > size) {
      throw StateError('无效分片参数');
    }
    final input = await file.open();
    try {
      phase = 'uploading';
      bytesTransferred = offset;
      _notify(force: true);
      await input.setPosition(offset);
      while (offset < size) {
        final chunk = await input.read(chunkBytes);
        if (chunk.isEmpty) throw StateError('文件读取中断');
        final ack = await transport.uploadChunk(
          '/files/upload/${upload['uploadId']}/chunk?offset=$offset',
          chunk,
        );
        if (ack['offset'] != offset + chunk.length) throw StateError('无效上传进度');
        offset += chunk.length;
        bytesTransferred = offset;
        _notify();
      }
    } finally {
      await input.close();
    }
    await transport.request(
      'POST',
      '/files/upload/${upload['uploadId']}/complete',
    );
    await _confirmed(hash);
  }
}
