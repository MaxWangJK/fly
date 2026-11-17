import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/sync/data/cloud_sync_transport.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/presentation/sync_controller.dart';
import 'package:fly/features/sync/services/lan_sync_notifications.dart';

class _Desktop extends SyncController {
  _Desktop(super.outbox, super.root);
  @override
  bool get isMobile => false;
}

class _Phone extends SyncController {
  _Phone(super.outbox, super.root);
  @override
  bool get isMobile => true;
}

Future<void> _until(FutureOr<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) fail('LAN state did not settle');
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
}

Future<int> _port() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('desktop waits with no engine, changes wake LAN peers, disconnect stops both engines', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('fly-presence-');
    final a = AppDatabase(NativeDatabase.memory());
    final b = AppDatabase(NativeDatabase.memory());
    final desktop = _Desktop(SyncOutboxRepository(a), '${root.path}/desktop')
      ..ready = true;
    final phone = _Phone(SyncOutboxRepository(b), '${root.path}/phone')
      ..ready = true;
    try {
      await a.ensureBuiltInData();
      await b.ensureBuiltInData();
      await desktop.setHost(true, await _port());
      expect(desktop.error, isNull);
      expect(desktop.host.running, isTrue);
      expect(desktop.host.connectedDevices, 0);
      expect(desktop.engine, isNull);
      expect(desktop.connected, isFalse);
      expect(desktop.status, '等待设备连接');
      // A local edit while unpaired must not start hashing or synchronization.
      final customer = await DriftCustomerRepository(a)
          .createCustomer(name: 'Local work');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(desktop.engine, isNull);
      final endpoint = 'http://127.0.0.1:${desktop.lanPort}/api';
      await phone.pair(endpoint, desktop.host.pairingCode);
      expect(phone.error, isNull);
      await _until(() => desktop.connected && phone.connected);
      await _until(
        () async =>
            (await (b.select(
              b.customers,
            )..where((c) => c.id.equals(customer.id))).getSingleOrNull()) !=
            null,
      );
      const content = [70, 76, 89, 32, 115, 121, 110, 99];
      final fileId = const Uuid().v4();
      final relative = 'files/$fileId/example.txt';
      final phoneFile = File('${phone.root}/$relative');
      await phoneFile.parent.create(recursive: true);
      await phoneFile.writeAsBytes(content);
      await ManagedFileRepository(b).commit(
        ImportedFile(
          id: fileId,
          relativePath: relative,
          name: 'example.txt',
          size: content.length,
          sha256: sha256.convert(content).toString(),
        ),
      );
      await _until(() async {
        final record = await ManagedFileRepository(a).find(fileId);
        return record != null &&
            await File('${desktop.root}/${record.relativePath}').exists();
      });
      final transferred = (await ManagedFileRepository(a).find(fileId))!;
      expect(
        await File('${desktop.root}/${transferred.relativePath}').readAsBytes(),
        content,
        reason: 'File completion hints wake download without the five-minute fallback',
      );
      expect(desktop.host.connectedDevices, 1);
      expect(desktop.engine!.pollInterval, const Duration(minutes: 5));
      expect(phone.engine!.pollInterval, const Duration(minutes: 5));
      final edited = await DriftCustomerRepository(a)
          .createCustomer(name: 'Changed while paired');
      await _until(
        () async =>
            (await (b.select(
              b.customers,
            )..where((c) => c.id.equals(edited.id))).getSingleOrNull()) !=
            null,
      );
      await _until(() => !desktop.engine!.running && !phone.engine!.running);
      await Future<void>.delayed(const Duration(seconds: 1));
      final last = desktop.engine!.lastSuccess;
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(
        desktop.engine!.lastSuccess,
        last,
        reason: 'No recurring two-second sync cycles',
      );
      final retired = desktop.engine!;
      await phone.suspend();
      await _until(
        () => desktop.host.connectedDevices == 0 && desktop.engine == null,
      );
      expect(phone.engine, isNull);
      expect(retired.enabled, isFalse);
      expect(desktop.connected, isFalse);
      expect(desktop.status, '等待设备连接');
      expect(
        desktop.host.running,
        isTrue,
        reason: 'QR listener remains available',
      );
      await DriftCustomerRepository(a)
          .createCustomer(name: 'Offline after disconnect');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(desktop.engine, isNull);
      // Returning to Fly restores the same pairing and drains pending edits.
      await phone.resume();
      await _until(() => desktop.connected && phone.connected);
      await _until(
        () async => (await b.select(b.customers).get()).any(
          (c) => c.name == 'Offline after disconnect',
        ),
      );
      await phone.suspend();
      await _until(() => desktop.engine == null);
    } finally {
      await phone.suspend();
      await desktop.setHost(false, desktop.lanPort);
      desktop.dispose();
      phone.dispose();
      await a.close();
      await b.close();
      await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('LAN events reject unpaired credentials and ignore requests after socket disconnect', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    final desktop = _Desktop(SyncOutboxRepository(db), '')..ready = true;
    LanSyncNotifications? events;
    LanSyncTransport? transport;
    try {
      await db.ensureBuiltInData();
      await desktop.setHost(true, await _port());
      final endpoint = 'http://127.0.0.1:${desktop.lanPort}/api';
      final wrong = LanSyncNotifications(onChange: () {}, onDisconnect: () {});
      await expectLater(
        wrong.connect(endpoint, 'untrusted'),
        throwsA(isA<WebSocketException>()),
      );
      wrong.dispose();
      expect(desktop.host.connectedDevices, 0);
      final pairing = LanSyncTransport(endpoint, token: () async => null);
      final result = await pairing.request(
        'POST',
        '/lan/pair',
        body: {
          'code': desktop.host.pairingCode,
          'deviceName': 'Synthetic phone',
        },
      );
      pairing.close();
      transport = LanSyncTransport(
        endpoint,
        token: () async => result['token'] as String,
      );
      events = LanSyncNotifications(onChange: () {}, onDisconnect: () {});
      await events.connect(endpoint, result['token'] as String);
      await _until(() => desktop.host.connectedDevices == 1);
      events.dispose();
      await _until(
        () => desktop.host.connectedDevices == 0 && desktop.engine == null,
      );
      await transport.request('GET', '/lan/info');
      expect(
        desktop.host.connectedDevices,
        0,
        reason: 'An in-flight old request must not resurrect presence',
      );
      expect(desktop.engine, isNull);
    } finally {
      events?.dispose();
      transport?.close();
      await desktop.setHost(false, desktop.lanPort);
      desktop.dispose();
      await db.close();
    }
  });
}
