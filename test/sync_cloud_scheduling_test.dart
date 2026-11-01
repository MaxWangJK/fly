import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/domain/sync_protocol.dart';
import 'package:fly/features/sync/services/file_sync_service.dart';
import 'package:fly/features/sync/services/sync_engine.dart';

class _CloudTransport implements SyncTransport {
  final names = <String>{};
  int pulls = 0;
  bool holdConflicts = false;
  final atConflicts = Completer<void>(), releaseConflicts = Completer<void>();
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? body,
  }) async {
    if (path == '/sync/push') {
      return {
        'results': [
          for (final raw in (body as Map)['mutations'] as List)
            _accept(raw as Map),
        ],
      };
    }
    if (path.startsWith('/sync/pull')) {
      pulls++;
      return {'changes': [], 'nextCursor': 0, 'hasMore': false};
    }
    if (path == '/sync/conflicts') {
      if (holdConflicts) {
        holdConflicts = false;
        atConflicts.complete();
        await releaseConflicts.future;
      }
      return {'items': []};
    }
    throw StateError(path);
  }

  Map<String, dynamic> _accept(Map mutation) {
    final payload = mutation['payload'] as Map;
    if (mutation['entityType'] == 'customers') {
      names.add(payload['name'] as String);
    }
    return {
      'mutationId': mutation['mutationId'],
      'status': 'accepted',
      'record': {
        'entityType': mutation['entityType'],
        'recordId': mutation['recordId'],
        'version': (mutation['baseVersion'] as int) + 1,
        'data': payload,
        'fieldClocks': mutation['fieldClocks'],
        'deletedAt': null,
      },
    };
  }

  @override
  void close() {}
  @override
  Future<void> download(String path, String destination) =>
      throw StateError('Cloud must not download files');
  @override
  Future<Map<String, dynamic>> uploadChunk(String path, List<int> chunk) =>
      throw StateError('Cloud must not upload files');
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Sync did not react before the five-minute fallback');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cloud starts immediately and new or modified customers upload without waiting for fallback', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final transport = _CloudTransport();
    final engine = SyncEngine(
      outbox: SyncOutboxRepository(db),
      transport: transport,
      cursorKey: 'cloudCursor',
      files: FileSyncService(db, '', transport),
    );
    try {
      await db.ensureBuiltInData();
      final repository = DriftCustomerRepository(db);
      await repository.createCustomer(name: 'Created before startup');
      engine.start();
      await _until(() => transport.names.contains('Created before startup'));
      expect(engine.pollInterval, const Duration(minutes: 5));
      final customer = await repository.createCustomer(
        name: 'Created while open',
      );
      await _until(() => transport.names.contains(customer.name));
      await repository.saveCustomer(
        customer.copyWith(name: 'Modified while open'),
      );
      await _until(() => transport.names.contains('Modified while open'));
      expect(engine.error, isNull);
    } finally {
      await engine.shutdown();
      engine.dispose();
      await db.close();
    }
  });

  test('an edit after the current pull retains a follow-up instead of being lost in an active cycle', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final transport = _CloudTransport()..holdConflicts = true;
    final engine = SyncEngine(
      outbox: SyncOutboxRepository(db),
      transport: transport,
      cursorKey: 'cloudCursor',
      files: FileSyncService(db, '', transport),
    );
    try {
      await db.ensureBuiltInData();
      engine.start();
      await transport.atConflicts.future.timeout(const Duration(seconds: 4));
      await DriftCustomerRepository(db).createCustomer(name: 'Late edit');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(transport.names, isNot(contains('Late edit')));
      transport.releaseConflicts.complete();
      await _until(() => transport.names.contains('Late edit'));
      expect(engine.error, isNull);
    } finally {
      if (!transport.releaseConflicts.isCompleted) {
        transport.releaseConflicts.complete();
      }
      await engine.shutdown();
      engine.dispose();
      await db.close();
    }
  });

  test(
    'periodic fallback works without notifications and stops when suspended',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final transport = _CloudTransport();
      final engine = SyncEngine(
        outbox: SyncOutboxRepository(db),
        transport: transport,
        cursorKey: 'cloudCursor',
        files: FileSyncService(db, '', transport),
        pollInterval: const Duration(milliseconds: 40),
      );
      try {
        await db.ensureBuiltInData();
        engine.start();
        await _until(() => transport.pulls >= 6);
        await engine.shutdown();
        final calls = transport.pulls;
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(transport.pulls, calls);
        expect(engine.enabled, isFalse);
      } finally {
        engine.dispose();
        await db.close();
      }
    },
  );
}
