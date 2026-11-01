import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/domain/sync_protocol.dart';
import 'package:fly/features/sync/services/file_sync_service.dart';
import 'package:fly/features/sync/services/sync_engine.dart';

class _RecordingTransport implements SyncTransport {
  bool automaticMerge = true;
  final sentDuringTransfer = Completer<void>();
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? body,
  }) async {
    if (path == '/health') {
      return {
        'capabilities': {'automaticMerge': automaticMerge},
      };
    }
    if (path == '/sync/push') {
      final mutations = (body as Map)['mutations'] as List;
      final results = <Map<String, dynamic>>[];
      for (final raw in mutations) {
        final mutation = raw as Map;
        if ((mutation['payload'] as Map)['name'] == 'Created during transfer' &&
            !sentDuringTransfer.isCompleted) {
          sentDuringTransfer.complete();
        }
        results.add({
          'mutationId': mutation['mutationId'],
          'status': 'accepted',
          'record': {
            'entityType': mutation['entityType'],
            'recordId': mutation['recordId'],
            'version': (mutation['baseVersion'] as int) + 1,
            'data': mutation['payload'],
            'fieldClocks': mutation['fieldClocks'],
            'deletedAt': null,
          },
        });
      }
      return {'results': results};
    }
    if (path.startsWith('/sync/pull')) {
      return {'changes': [], 'nextCursor': 0, 'hasMore': false};
    }
    if (path == '/sync/conflicts') return {'items': []};
    throw StateError(path);
  }

  @override
  void close() {}
  @override
  Future<void> download(String path, String destination) async {}
  @override
  Future<Map<String, dynamic>> uploadChunk(
    String path,
    List<int> chunk,
  ) async => {};
}

class _PausedFiles extends FileSyncService {
  _PausedFiles(super.db, super.root, super.transport);
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<void> synchronize({
    bool uploadOnly = false,
    bool uploadEnabled = true,
    bool downloadEnabled = true,
  }) async {
    if (uploadOnly && !entered.isCompleted) {
      phase = 'uploading';
      entered.complete();
      await release.future;
    }
    phase = 'idle';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'incompatible cloud stops after three failures without publishing data',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final transport = _RecordingTransport()..automaticMerge = false;
      final queue = SyncOutboxRepository(db);
      final engine = SyncEngine(
        outbox: queue,
        transport: transport,
        cursorKey: 'cloudCursor',
        files: FileSyncService(db, '', transport),
        automaticMergeRequired: true,
        failureLimit: 3,
      )..enabled = true;
      try {
        await db.ensureBuiltInData();
        await DriftCustomerRepository(db)
            .createCustomer(name: 'Retained offline');
        final pending = await queue.pendingCount();
        for (var i = 0; i < 3; i++) {
          await engine.synchronize();
        }
        expect(engine.enabled, isFalse);
        expect(engine.consecutiveFailures, 3);
        expect(await queue.pendingCount(), pending);
      } finally {
        await engine.shutdown();
        engine.dispose();
        await db.close();
      }
    },
  );
  test(
    'local business edits reach peer while a file transfer remains blocked',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final transport = _RecordingTransport();
      final files = _PausedFiles(db, '', transport);
      final engine = SyncEngine(
        outbox: SyncOutboxRepository(db),
        transport: transport,
        cursorKey: 'testCursor',
        files: files,
        syncFiles: true,
        pollInterval: const Duration(milliseconds: 40),
      );
      try {
        await db.ensureBuiltInData();
        engine.start();
        await files.entered.future.timeout(const Duration(seconds: 5));
        await DriftCustomerRepository(db)
            .createCustomer(name: 'Created during transfer');
        await transport.sentDuringTransfer.future.timeout(
          const Duration(seconds: 3),
        );
        expect(files.release.isCompleted, isFalse);
      } finally {
        files.release.complete();
        await engine.shutdown();
        engine.dispose();
        await db.close();
      }
    },
  );
}
