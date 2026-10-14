import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fly/features/sync/presentation/sync_controller.dart';
import 'package:fly/features/sync/services/lan_host_service.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/files/data/file_browser_query.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/files/data/permanent_file_deletion.dart';
import 'package:fly/features/files/data/thumbnail_cache.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/domain/sync_protocol.dart';
import 'package:fly/features/sync/services/file_sync_service.dart';
import 'package:fly/features/sync/services/sync_engine.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';

class _Transport implements SyncTransport {
  bool fail = true, closed = false;
  int calls = 0;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? body,
  }) async {
    calls++;
    if (fail) throw const SocketException('Synthetic offline connection');
    if (path.startsWith('/sync/pull')) {
      return {'nextCursor': 0, 'hasMore': false, 'changes': []};
    }
    if (path == '/sync/conflicts') return {'items': []};
    throw StateError('Unexpected $path');
  }

  @override
  void close() => closed = true;
  @override
  Future<void> download(String path, String destination) async =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> uploadChunk(
    String path,
    List<int> chunk,
  ) async => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'three failed connection cycles stop; successful cycle resets failures',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final root = await Directory.systemTemp.createTemp('fly-203-retry-');
      final transport = _Transport();
      final outbox = SyncOutboxRepository(db);
      await db.ensureBuiltInData();
      await db.customStatement('DELETE FROM sync_outbox');
      final engine = SyncEngine(
        outbox: outbox,
        transport: transport,
        cursorKey: 'testCursor',
        files: FileSyncService(db, root.path, transport),
        failureLimit: 3,
      )..enabled = true;
      try {
        await engine.synchronize();
        expect(engine.consecutiveFailures, 1);
        transport.fail = false;
        await engine.synchronize();
        expect(engine.error, isNull);
        expect(engine.consecutiveFailures, 0);
        transport.fail = true;
        for (var i = 0; i < 3; i++) {
          await engine.synchronize();
        }
        expect(engine.enabled, isFalse);
        expect(engine.consecutiveFailures, 3);
        final calls = transport.calls;
        await engine.synchronize();
        expect(transport.calls, calls);
        expect(engine.status, '连接失败，已停止重试');
      } finally {
        await engine.shutdown();
        engine.dispose();
        await db.close();
        await root.delete(recursive: true);
      }
    },
  );

  test('purge removes actual content, cache and blob; tombstone cannot be restored', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final root = await Directory.systemTemp.createTemp('fly-203-purge-');
    final storage = ManagedFileStorage(root.path);
    final repo = ManagedFileRepository(db);
    final hash = 'a' * 64;
    try {
      await db.ensureBuiltInData();
      final paths = [
        'files/sample.png',
        'files/sample.png.part',
        'sync_blobs/$hash',
        'sync_blobs/$hash.part',
      ];
      for (final path in paths) {
        final file = File(storage.absolute(path));
        await file.parent.create(recursive: true);
        await file.writeAsString('synthetic');
      }
      await repo.commit(
        ImportedFile(
          id: 'purged',
          relativePath: paths.first,
          name: 'sample.png',
          size: 9,
          sha256: hash,
        ),
      );
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
          .drawColor(const ui.Color(0xff168b62), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(8, 8);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(storage.absolute(paths.first))
          .writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
      final record = (await repo.find('purged'))!;
      final thumbnail = (await ThumbnailCache(storage).get(record))!;
      expect(await thumbnail.exists(), isTrue);
      await repo.remove('purged');
      await PermanentFileDeletion(db, storage).purge('purged');
      for (final path in paths) {
        expect(await File(storage.absolute(path)).exists(), isFalse);
      }
      expect(await thumbnail.exists(), isFalse);
      expect((await repo.find('purged'))!.deletionBatch, 'permanent');
      expect(
        await FileBrowserQuery(db)
            .watch(collection: FileCollection.deleted)
            .first,
        isEmpty,
      );
      await expectLater(repo.restore('purged'), throwsStateError);
      expect(await SyncOutboxRepository(db).pendingCount(), greaterThan(0));
    } finally {
      await db.close();
      await root.delete(recursive: true);
    }
  });

  test(
    'schema18 migration keeps task lists and adds synced parent relationships',
    () async {
      final root = await Directory.systemTemp.createTemp('fly-203-schema-');
      final file = File('${root.path}/fly.db');
      var db = AppDatabase(NativeDatabase(file));
      try {
        await db.ensureBuiltInData();
        final list = await DriftTaskRepository(db).createList('Existing list');
        for (final suffix in ['insert', 'update', 'delete']) {
          await db.customStatement(
            'DROP TRIGGER IF EXISTS sync_task_lists_$suffix',
          );
        }
        await db.customStatement(
          'ALTER TABLE task_lists DROP COLUMN parent_id',
        );
        await db.customStatement('PRAGMA user_version=18');
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        final child = await DriftTaskRepository(db)
            .createList('Child list', parentId: list.id);
        final lists = await DriftTaskRepository(db).watchLists().first;
        expect(lists.firstWhere((l) => l.id == list.id).name, 'Existing list');
        expect(lists.firstWhere((l) => l.id == child.id).parentId, list.id);
        final mutation = (await SyncOutboxRepository(db).prepare()).firstWhere(
          (m) =>
              m['entityType'] == 'task_lists' &&
              (m['payload'] as Map)['id'] == child.id,
        );
        expect((mutation['payload'] as Map)['parent_id'], list.id);
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
            'user_version',
          ),
          19,
        );
      } finally {
        await db.close();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'phone disconnects in background and resumes saved LAN connection',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      FlutterSecureStorage.setMockInitialValues({});
      HttpOverrides.global = null;
      final rootA = await Directory.systemTemp.createTemp('fly-203-life-a-');
      final rootB = await Directory.systemTemp.createTemp('fly-203-life-b-');
      final a = AppDatabase(NativeDatabase.memory()),
          b = AppDatabase(NativeDatabase.memory());
      final host = LanHostService(SyncOutboxRepository(a), rootA.path);
      final controller = SyncController(SyncOutboxRepository(b), rootB.path);
      try {
        await a.ensureBuiltInData();
        await b.ensureBuiltInData();
        final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = socket.port;
        await socket.close();
        await host.start(port: port);
        await controller.initialize();
        await controller.selectConnectionMode(SyncConnectionMode.lan);
        await controller.pair('http://127.0.0.1:$port/api', host.pairingCode);
        await controller.engine!.synchronize();
        expect(controller.connected, isTrue);
        final endpoint = controller.lanEndpoint;
        await controller.suspend();
        expect(controller.engine, isNull);
        expect(controller.connected, isFalse);
        await DriftCustomerRepository(b)
            .createCustomer(name: 'Created while offline');
        await controller.resume();
        await controller.engine!.synchronize();
        expect(controller.lanEndpoint, endpoint);
        expect(controller.connected, isTrue);
        expect(controller.engine!.failureLimit, 3);
        expect(controller.engine!.pollInterval, const Duration(seconds: 2));
        expect(await controller.outbox.pendingCount(), 0);
        await controller.suspend();
      } finally {
        controller.dispose();
        await host.stop();
        await a.close();
        await b.close();
        await rootA.delete(recursive: true);
        await rootB.delete(recursive: true);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
