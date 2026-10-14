import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/domain/customer.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/files/data/permanent_file_deletion.dart';
import 'package:fly/features/sync/data/cloud_sync_transport.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/services/file_sync_service.dart';
import 'package:fly/features/sync/services/file_transfer_inventory.dart';
import 'package:fly/features/sync/services/lan_host_service.dart';
import 'package:fly/features/sync/services/sync_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'picked bytes are imported even without an ordinary filesystem source',
    () async {
      final root = await Directory.systemTemp.createTemp('fly-picked-');
      try {
        final storage = ManagedFileStorage(root.path);
        final picked = XFile.fromData(
          Uint8List.fromList([1, 2, 3]),
          path: 'photo.jpg',
        );
        final imported = await storage.import(picked.path, pickedFile: picked);
        expect(imported.relativePath, isNot(contains('\\')));
        expect(
          await File(storage.absolute(imported.relativePath)).readAsBytes(),
          [1, 2, 3],
        );
        expect(
          storage.absolute(imported.relativePath.replaceAll('/', '\\')),
          storage.absolute(imported.relativePath),
        );
        for (final bad in [
          '../outside',
          '..\\outside',
          'C:\\outside',
          '/outside',
        ]) {
          expect(() => storage.absolute(bad), throwsArgumentError);
        }
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('LAN transfers actual files both ways, including old Windows paths and a 20 MiB file', () async {
    final rootA = await Directory.systemTemp.createTemp('fly-lan-files-a-');
    final rootB = await Directory.systemTemp.createTemp('fly-lan-files-b-');
    final a = AppDatabase(NativeDatabase.memory()),
        b = AppDatabase(NativeDatabase.memory());
    final qa = SyncOutboxRepository(a), qb = SyncOutboxRepository(b);
    final host = LanHostService(qa, rootA.path)..syncFiles = true;
    SyncEngine? ea, eb;
    LanSyncTransport? pairing;
    try {
      await a.ensureBuiltInData();
      await b.ensureBuiltInData();
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      await host.start(port: port);
      final endpoint = 'http://127.0.0.1:$port/api';
      pairing = LanSyncTransport(endpoint, token: () async => null);
      final session = await pairing.request(
        'POST',
        '/lan/pair',
        body: {'code': host.pairingCode, 'deviceName': 'Synthetic phone'},
      );
      await qa.bind('lan:${host.workspace}');
      await qb.bind('lan:${host.workspace}');
      final ta = LanSyncTransport(endpoint, token: () async => host.hostToken);
      final tb = LanSyncTransport(
        endpoint,
        token: () async => session['token'] as String,
      );
      ea = SyncEngine(
        outbox: qa,
        transport: ta,
        cursorKey: 'lanCursor',
        files: FileSyncService(a, rootA.path, ta),
        syncFiles: true,
      )..enabled = true;
      eb = SyncEngine(
        outbox: qb,
        transport: tb,
        cursorKey: 'lanCursor',
        files: FileSyncService(b, rootB.path, tb),
        syncFiles: true,
      )..enabled = true;
      final uploaded = <int>[], downloaded = <int>[];
      eb.addListener(() {
        if (eb!.files.phase == 'uploading') {
          uploaded.add(eb.files.bytesTransferred);
        }
      });
      ea.addListener(() {
        if (ea!.files.phase == 'downloading') {
          downloaded.add(ea.files.bytesTransferred);
        }
      });
      Future<void> sync(SyncEngine e) async {
        await e.synchronize();
        expect(e.error, isNull, reason: e.status);
      }

      final desktopCustomer = await DriftCustomerRepository(a)
          .createCustomer(name: 'Desktop customer without a follow-up date');
      await sync(ea);
      await sync(eb);
      expect(
        (await DriftCustomerRepository(b)
                .watchCustomers(
                  const CustomerQuery(projection: CustomerProjection.all),
                )
                .first)
            .map((c) => c.id),
        contains(desktopCustomer.id),
      );

      final source = File(p.join(rootA.path, 'quote.txt'));
      await source.writeAsString('Desktop synthetic quote');
      final importedA = await ManagedFileStorage(rootA.path)
          .import(source.path);
      await ManagedFileRepository(a).commit(importedA);
      await (a.update(
        a.attachments,
      )..where((f) => f.id.equals(importedA.id))).write(
        AttachmentsCompanion(
          relativePath: Value(importedA.relativePath.replaceAll('/', '\\')),
        ),
      );
      await sync(ea);
      await sync(eb);
      final copied = await ManagedFileRepository(b).find(importedA.id);
      expect(
        await File(
          ManagedFileStorage(rootB.path).absolute(copied!.relativePath),
        ).readAsString(),
        'Desktop synthetic quote',
      );
      final cameraBytes = Uint8List(20 * 1024 * 1024);
      for (var i = 0; i < cameraBytes.length; i += 4096) {
        cameraBytes[i] = i ~/ 4096 % 251;
      }
      final camera = XFile.fromData(cameraBytes, path: 'camera.jpg');
      final importedB = await ManagedFileStorage(rootB.path)
          .import(camera.path, pickedFile: camera);
      await ManagedFileRepository(b).commit(importedB);
      await sync(eb);
      await sync(ea);
      await sync(eb);
      final remote = await ManagedFileRepository(a).find(importedB.id);
      expect(
        await File(
          ManagedFileStorage(rootA.path).absolute(remote!.relativePath),
        ).readAsBytes(),
        cameraBytes,
      );
      expect(remote.sha256, importedB.sha256);
      expect(uploaded, contains(cameraBytes.length));
      expect(uploaded, contains(0));
      expect(downloaded, contains(cameraBytes.length));
      expect(downloaded, contains(0));
      expect(
        DateTime.parse(
          (await qa.state(await qa.successStateKey('lanCursor')))!,
        ),
        ea.lastSuccess,
      );
      for (final pair in [(a, rootA), (b, rootB)]) {
        final inventory = await FileTransferInventory.load(
          pair.$1,
          pair.$2.path,
        );
        expect(inventory.uploads, 0);
        expect(inventory.downloads, 0);
      }
      await ManagedFileRepository(b).remove(importedB.id);
      await sync(eb);
      await sync(ea);
      await PermanentFileDeletion(
        b,
        ManagedFileStorage(rootB.path),
      ).purge(importedB.id);
      await sync(eb);
      await sync(ea);
      expect(
        await File(ManagedFileStorage(rootA.path).absolute(remote.relativePath))
            .exists(),
        isFalse,
      );
      expect(
        await File(
          ManagedFileStorage(rootB.path).absolute(importedB.relativePath),
        ).exists(),
        isFalse,
      );
      expect(
        (await ManagedFileRepository(a).find(importedB.id))!.deletionBatch,
        'permanent',
      );
      await expectLater(
        ManagedFileRepository(a).restore(importedB.id),
        throwsStateError,
      );
    } finally {
      if (ea != null) {
        await ea.shutdown();
        ea.dispose();
      }
      if (eb != null) {
        await eb.shutdown();
        eb.dispose();
      }
      pairing?.close();
      await host.stop();
      await a.close();
      await b.close();
      await rootA.delete(recursive: true);
      await rootB.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
