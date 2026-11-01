import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/account/data/auth_service.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/sync/data/cloud_sync_transport.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/services/file_sync_service.dart';
import 'package:fly/features/sync/services/sync_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final url = Platform.environment['FLY_SYNC_TEST_URL'];
  test(
    'two Flutter SQLite clients share account, merge offline edits and transfer files',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final rootA = await Directory.systemTemp.createTemp('fly-client-a-');
      final rootB = await Directory.systemTemp.createTemp('fly-client-b-');
      final a = AppDatabase(NativeDatabase.memory()),
          b = AppDatabase(NativeDatabase.memory());
      final authA = AuthService(url!, rootA.path),
          authB = AuthService(url, rootB.path);
      SyncEngine? engineA, engineB;
      try {
        await a.ensureBuiltInData();
        await b.ensureBuiltInData();
        const email = 'two-device@example.com';
        await authA.authenticate(
          register: false,
          email: email,
          password: 'two-client-password',
          confirm: 'two-client-password',
        );
        await authB.authenticate(
          register: false,
          email: email,
          password: 'two-client-password',
        );
        final qa = SyncOutboxRepository(a), qb = SyncOutboxRepository(b);
        final workspace = 'cloud:$url:${authA.userId}';
        await qa.bind(workspace);
        await qb.bind(workspace);
        final ta = CloudSyncTransport(
          url,
          token: authA.accessToken,
          onUnauthorized: authA.refresh,
        );
        final tb = CloudSyncTransport(
          url,
          token: authB.accessToken,
          onUnauthorized: authB.refresh,
        );
        engineA = SyncEngine(
          outbox: qa,
          transport: ta,
          cursorKey: 'cloudCursor',
          files: FileSyncService(a, rootA.path, ta),
        )..enabled = true;
        engineB = SyncEngine(
          outbox: qb,
          transport: tb,
          cursorKey: 'cloudCursor',
          files: FileSyncService(b, rootB.path, tb),
        )..enabled = true;
        Future<void> sync(SyncEngine engine) async {
          await engine.synchronize();
          expect(engine.error, isNull, reason: engine.status);
        }

        final jack = await DriftCustomerRepository(a)
            .createCustomer(name: 'Jack');
        await sync(engineA);
        await sync(engineB);
        await sync(engineA);
        expect(
          (await (b.select(
            b.customers,
          )..where((r) => r.id.equals(jack.id))).getSingle()).name,
          'Jack',
        );
        await a.customStatement('UPDATE customers SET phone=? WHERE id=?', [
          '123',
          jack.id,
        ]);
        await b.customStatement('UPDATE customers SET address=? WHERE id=?', [
          'Manila',
          jack.id,
        ]);
        await sync(engineA);
        await sync(engineB);
        await sync(engineA);
        final merged = await (a.select(
          a.customers,
        )..where((r) => r.id.equals(jack.id))).getSingle();
        expect(merged.phone, '123');
        expect(merged.address, 'Manila');
        expect(engineA.conflictCount, 0);
        await a.customStatement(
          'UPDATE customers SET company_name=? WHERE id=?',
          ['DEF', jack.id],
        );
        await b.customStatement(
          'UPDATE customers SET company_name=? WHERE id=?',
          ['XYZ', jack.id],
        );
        await sync(engineA);
        await sync(engineB);
        await sync(engineA);
        expect(engineA.conflictCount, 0);
        final tom = await DriftCustomerRepository(b)
            .createCustomer(name: 'Tom');
        await sync(engineB);
        await sync(engineA);
        expect(
          (await (a.select(
            a.customers,
          )..where((r) => r.id.equals(tom.id))).getSingle()).name,
          'Tom',
        );
        await a.customStatement(
          'UPDATE customers SET deleted_at=1 WHERE id=?',
          [jack.id],
        );
        await b.customStatement('UPDATE customers SET phone=? WHERE id=?', [
          'offline phone',
          jack.id,
        ]);
        await sync(engineA);
        await sync(engineB);
        expect(
          (await (b.select(
            b.customers,
          )..where((r) => r.id.equals(jack.id))).getSingle()).deletedAt,
          isNotNull,
        );
        final fileId = const Uuid().v4();
        final content = utf8.encode('Synthetic file bytes');
        final relative = 'files/$fileId/quote.txt';
        final local = File('${rootA.path}/$relative');
        await local.parent.create(recursive: true);
        await local.writeAsBytes(content);
        await a
            .into(a.attachments)
            .insert(
              AttachmentsCompanion.insert(
                id: fileId,
                ownerType: 'library',
                ownerId: fileId,
                fileName: 'quote.txt',
                originalName: 'quote.txt',
                relativePath: relative,
                sha256: Value(sha256.convert(content).toString()),
                fileSize: content.length,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
        await sync(engineA);
        await sync(engineB);
        var remote = await (b.select(
          b.attachments,
        )..where((f) => f.id.equals(fileId))).getSingle();
        expect(
          await File('${rootB.path}/${remote.relativePath}').exists(),
          isFalse,
        );
        engineA.syncFiles = true;
        engineB.syncFiles = true;
        await sync(engineA);
        await sync(engineB);
        remote = await (b.select(
          b.attachments,
        )..where((f) => f.id.equals(fileId))).getSingle();
        expect(
          await File('${rootB.path}/${remote.relativePath}').readAsBytes(),
          content,
        );
      } finally {
        engineA?.dispose();
        engineB?.dispose();
        await a.close();
        await b.close();
        await rootA.delete(recursive: true);
        await rootB.delete(recursive: true);
      }
    },
    skip: url == null
        ? 'Start server/tests/run_test_server.py and set FLY_SYNC_TEST_URL for the real HTTP test.'
        : false,
  );
}
