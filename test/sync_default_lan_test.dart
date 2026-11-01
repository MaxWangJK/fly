import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/domain/sync_protocol.dart';
import 'package:fly/features/sync/presentation/sync_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'new desktop workspace starts LAN and returning from cloud offers a new QR',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      FlutterSecureStorage.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('fly-build44-lan-');
      final db = AppDatabase(NativeDatabase.memory());
      final outbox = SyncOutboxRepository(db);
      final c = SyncController(outbox, root.path);
      try {
        await db.ensureBuiltInData();
        final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = socket.port;
        await socket.close();
        await outbox.saveState('lanPort', '$port');
        await c.initialize();
        expect(c.error, isNull);
        expect(c.connectionMode, SyncConnectionMode.lan);
        expect(c.host.running, isTrue);
        expect(c.lanPort, port);
        expect(c.pairingPayload, isNotNull);
        await c.selectConnectionMode(SyncConnectionMode.cloud);
        expect(c.host.running, isFalse);
        expect(c.engine, isNull);
        expect(c.cloudEnabled, isFalse);
        await c.selectConnectionMode(SyncConnectionMode.lan);
        expect(c.error, isNull);
        expect(c.host.running, isTrue);
        expect(c.pairingPayload, isNotNull);
        expect(await outbox.state('lanHostEnabled'), 'true');
        await c.setHost(false, port);
        expect(c.host.running, isFalse);
      } finally {
        await c.setHost(false, c.lanPort);
        c.dispose();
        await db.close();
        await root.delete(recursive: true);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
