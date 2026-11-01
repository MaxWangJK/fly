import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/account/data/auth_service.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/features/reviews/data/daily_review_repository.dart';
import 'package:fly/features/sync/data/cloud_sync_transport.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/services/file_sync_service.dart';
import 'package:fly/features/sync/services/sync_engine.dart';
import 'package:fly/features/sync/services/sync_workspace_binding.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final url = Platform.environment['FLY_THREE_SYNC_TEST_URL'];
  final codesPath = Platform.environment['FLY_SYNC_TEST_ENROLLMENT_FILE'];
  test(
    'work PC, phone and home PC converge after independent offline edits',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final codes =
          (jsonDecode(await File(codesPath!).readAsString())['codes'] as List)
              .cast<String>();
      final root = await Directory.systemTemp.createTemp('fly-three-clients-');
      final databases = <AppDatabase>[],
          engines = <SyncEngine>[],
          queues = <SyncOutboxRepository>[];
      final auth = <AuthService>[];
      try {
        for (var i = 0; i < 3; i++) {
          final db = AppDatabase(NativeDatabase.memory());
          databases.add(db);
          await db.ensureBuiltInData();
          final identity = AuthService(url!, '${root.path}/device-$i');
          auth.add(identity);
          await identity.enrollDevice(codes[i]);
          final queue = SyncOutboxRepository(db);
          queues.add(queue);
          await SyncWorkspaceBinding(queue)
              .activate('cloud:$url:${identity.userId}');
          final transport = CloudSyncTransport(
            url,
            token: identity.accessToken,
            onUnauthorized: identity.refresh,
          );
          engines.add(
            SyncEngine(
              outbox: queue,
              transport: transport,
              cursorKey: 'cloudCursor',
              files: FileSyncService(db, '${root.path}/device-$i', transport),
            )..enabled = true,
          );
        }
        expect(auth.map((a) => a.userId).toSet(), hasLength(1));
        Future<void> sync(int i) async {
          await engines[i].synchronize();
          expect(engines[i].error, isNull);
          expect(engines[i].conflictCount, 0);
        }

        // All three create records before any one of them has synced.
        for (var i = 0; i < 3; i++) {
          await DriftCustomerRepository(databases[i])
              .createCustomer(name: 'Device $i customer');
          await DriftTaskRepository(databases[i])
              .createTask(title: 'Device $i task');
        }
        for (var cycle = 0; cycle < 2; cycle++) {
          for (var i = 0; i < 3; i++) {
            await sync(i);
          }
        }
        final customer =
            (await databases[0].select(databases[0].customers).get())
                .firstWhere((c) => c.name == 'Device 0 customer');
        await DailyReviewRepository(databases[0])
            .saveAnswer('2026-11-01', 'q1', 'Base answer');
        await sync(0);
        await sync(1);
        await sync(2);
        await DailyReviewRepository(databases[0])
            .saveAnswer('2026-11-01', 'q1', 'Work reflection');
        await DailyReviewRepository(databases[2])
            .saveAnswer('2026-11-01', 'q2', 'Home reflection');
        await sync(2);
        await sync(0);
        await sync(1);
        await sync(2);
        for (final db in databases) {
          expect(await DailyReviewRepository(db).answers('2026-11-01'), {
            'q1': 'Work reflection',
            'q2': 'Home reflection',
          });
        }
        // Both computers edit a shared record offline. Different fields merge.
        await databases[0].customStatement(
          'UPDATE customers SET phone=? WHERE id=?',
          ['work-phone', customer.id],
        );
        await databases[2].customStatement(
          'UPDATE customers SET address=? WHERE id=?',
          ['home-address', customer.id],
        );
        await sync(2);
        await sync(0);
        await sync(1);
        await sync(2);
        // Two conflicting phone edits: the older one is deliberately delivered last.
        await databases[0].customStatement(
          'UPDATE customers SET phone=? WHERE id=?',
          ['older-offline', customer.id],
        );
        final old = (await queues[0].prepare()).firstWhere(
          (m) => m['entityType'] == 'customers',
        );
        final oldClock =
            ((old['fieldClocks'] as Map)['phone'] as List).first as int;
        await databases[2].customStatement(
          'UPDATE customers SET phone=? WHERE id=?',
          ['newer-home', customer.id],
        );
        final pending = await databases[2]
            .customSelect(
              "SELECT mutation_id FROM sync_outbox WHERE entity_type='customers' ORDER BY ordinal DESC LIMIT 1",
            )
            .getSingle();
        // Synthetic edit timestamps avoid sleeping or depending on wall-clock granularity.
        await queues[2].saveState(
          'mutationClocks:${pending.read<String>('mutation_id')}',
          jsonEncode({
            'phone': [oldClock + 1000, pending.read<String>('mutation_id')],
          }),
        );
        await sync(2);
        await sync(0);
        for (var cycle = 0; cycle < 2; cycle++) {
          for (var i = 0; i < 3; i++) {
            await sync(i);
          }
        }
        for (var i = 0; i < 3; i++) {
          final db = databases[i];
          final customers = await db.select(db.customers).get();
          expect(
            customers.where((c) => c.name.startsWith('Device ')),
            hasLength(3),
          );
          final shared = customers.singleWhere((c) => c.id == customer.id);
          expect(shared.phone, 'newer-home');
          expect(shared.address, 'home-address');
          final tasks = await db.select(db.tasks).get();
          expect(
            tasks.where((t) => t.title.startsWith('Device ')),
            hasLength(3),
          );
          expect(await queues[i].pendingCount(), 0);
        }
        // The same local rows can move through two paired desktop coordinators,
        // retaining field provenance; cloud identity remains pinned to one user.
        await SyncWorkspaceBinding(queues[1]).activate('lan:work-desktop');
        await queues[1].prepare();
        await SyncWorkspaceBinding(queues[1]).activate('lan:home-desktop');
        final forwarded = (await queues[1].prepare()).firstWhere(
          (m) => m['recordId'] == old['recordId'],
        );
        expect((forwarded['fieldClocks'] as Map)['phone'], isNotNull);
        await SyncWorkspaceBinding(queues[1])
            .activate('cloud:$url:${auth[1].userId}');
        await sync(1);
        await expectLater(
          SyncWorkspaceBinding(queues[1]).activate('cloud:$url:other-user'),
          throwsStateError,
        );
      } finally {
        for (final engine in engines) {
          await engine.shutdown();
          engine.dispose();
        }
        for (final db in databases) {
          await db.close();
        }
        await root.delete(recursive: true);
      }
    },
    skip: url == null || codesPath == null
        ? 'Requires isolated three-device test server'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
