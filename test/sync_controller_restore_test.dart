import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/account/data/auth_service.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/presentation/sync_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('changed LAN address restores secret by workspace after restart without reconnecting a disabled mode', () async {
    const root = 'synthetic-restore-root', workspace = 'paired-workspace';
    final secretKey =
        'fly-lan-workspace-${AuthService(workspace, root).storageKey}';
    FlutterSecureStorage.setMockInitialValues({
      secretKey: 'saved-paired-secret',
    });
    final db = AppDatabase(NativeDatabase.memory());
    final queue = SyncOutboxRepository(db);
    final controller = SyncController(queue, root);
    try {
      await db.ensureBuiltInData();
      await queue.saveState('lanEndpoint', 'http://192.168.2.99:8765/api');
      await queue.saveState('lanRemoteWorkspace', workspace);
      await queue.saveState('lanDeviceId', 'synthetic-paired-device');
      await queue.saveState('lanClientEnabled', 'false');
      await controller.initialize();
      expect(controller.error, isNull);
      expect(controller.lanToken, 'saved-paired-secret');
      expect(controller.lanWorkspace, workspace);
      expect(controller.engine, isNull);
      expect(await queue.state('lanPeers'), contains(workspace));
    } finally {
      controller.dispose();
      await db.close();
    }
  });
}
