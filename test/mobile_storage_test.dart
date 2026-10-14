import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/storage/data_root_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(
    () async =>
        temp = await Directory.systemTemp.createTemp('fly-mobile-storage-'),
  );
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          FlyDataRootService.mobileStorageChannel,
          null,
        );
    await temp.delete(recursive: true);
  });
  FlyDataRootService service(TargetPlatform platform) => FlyDataRootService(
    platform: platform,
    supportDirectory: Directory('${temp.path}/support'),
    documentsDirectory: Directory('${temp.path}/documents'),
  );
  test('Android permission creates shared fly automatically and reopening preserves data', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FlyDataRootService.mobileStorageChannel, (
          call,
        ) async {
          calls.add(call.method);
          return call.method == 'sharedRoot' ? '${temp.path}/shared/fly' : true;
        });
    final s = service(TargetPlatform.android);
    final root = await s.initializeMobile();
    expect(await Directory('$root/files').exists(), isTrue);
    final db = File('$root/fly.db');
    await db.writeAsString('Existing database content');
    expect(await s.initializeMobile(), root);
    expect(await db.readAsString(), 'Existing database content');
    expect(calls, ['sharedRoot', 'ensureAccess']);
  });
  test(
    'denied initial Android permission uses a persistent private fly directory',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            FlyDataRootService.mobileStorageChannel,
            (_) async => null,
          );
      final s = service(TargetPlatform.android);
      final root = await s.initializeMobile();
      expect(root.replaceAll('\\', '/'), endsWith('/documents/fly'));
      expect(await s.loadDataRoot(), root);
      expect(await Directory('$root/files').exists(), isTrue);
    },
  );
  test(
    'revoked access preserves existing root and refuses an empty replacement',
    () async {
      final s = service(TargetPlatform.android);
      final existing = '${temp.path}/shared/fly';
      await s.saveDataRoot(existing);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            FlyDataRootService.mobileStorageChannel,
            (_) async => false,
          );
      await expectLater(s.initializeMobile(), throwsStateError);
      expect(
        await s.loadDataRoot(),
        existing.replaceAll('/', Platform.pathSeparator),
      );
      expect(await Directory('${temp.path}/documents/fly').exists(), isFalse);
    },
  );
  test(
    'iOS creates fly in Documents and keeps an existing configured directory',
    () async {
      final s = service(TargetPlatform.iOS);
      final root = await s.initializeMobile();
      expect(root.replaceAll('\\', '/'), endsWith('/documents/fly'));
      expect(await Directory('$root/files').exists(), isTrue);
      final oldRoot = '${temp.path}/old-mobile-data';
      await s.saveDataRoot(oldRoot);
      expect(
        (await s.initializeMobile()).replaceAll('\\', '/'),
        oldRoot.replaceAll('\\', '/'),
      );
    },
  );
}
