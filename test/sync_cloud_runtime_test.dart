import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/account/data/auth_service.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/presentation/sync_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final url = Platform.environment['FLY_SYNC_TEST_URL'];
  test(
    'saved cloud mode syncs on launch and uploads offline edits immediately on mobile resume',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final directory = await Directory.systemTemp.createTemp(
        'fly-cloud-runtime-',
      );
      final runId = const Uuid().v4();
      final db = AppDatabase(NativeDatabase.memory());
      final queue = SyncOutboxRepository(db);
      final controller = SyncController(queue, directory.path);
      Future<void> untilSynced() async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (controller.engine?.lastSuccess == null ||
            await queue.pendingCount() != 0) {
          if (DateTime.now().isAfter(deadline)) {
            fail(
              'Cloud startup/resume did not complete: ${controller.error} / ${controller.engine?.error}',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
      }

      try {
        await db.ensureBuiltInData();
        final identity = AuthService(url!, directory.path);
        await identity.authenticate(
          register: false,
          email: 'two-device@example.com',
          password: 'two-client-password',
        );
        await queue.saveState('server', url);
        await queue.saveState('syncConnectionMode', 'cloud');
        await queue.saveState('cloudEnabled', 'true');
        await DriftCustomerRepository(db)
            .createCustomer(name: 'Launch upload $runId');
        await controller.initialize();
        await untilSynced();
        expect(controller.engine!.pollInterval, const Duration(minutes: 5));
        expect(controller.engine!.syncFiles, isFalse);
        expect(controller.auth.userId, identity.userId);
        await controller.suspend();
        expect(controller.engine, isNull);
        expect(controller.notifications, isNull);
        await DriftCustomerRepository(db)
            .createCustomer(name: 'While suspended $runId');
        expect(await queue.pendingCount(), greaterThan(0));
        await controller.resume();
        await untilSynced();
        expect(controller.engine!.syncFiles, isFalse);
        expect(controller.engine!.error, isNull);
        expect(await queue.state('cloudEnabled'), 'true');
      } finally {
        await controller.suspend();
        controller.dispose();
        await db.close();
        debugDefaultTargetPlatformOverride = null;
        await directory.delete(recursive: true);
      }
    },
    skip: url == null
        ? 'Start the isolated protocol backend and set FLY_SYNC_TEST_URL'
        : false,
  );
}
