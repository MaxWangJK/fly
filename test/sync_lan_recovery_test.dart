import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/sync/data/cloud_sync_transport.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/services/file_transfer_scheduler.dart';
import 'package:fly/features/sync/services/lan_discovery_service.dart';
import 'package:fly/features/sync/services/lan_host_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'discovery recovers paired host only with correct live secret',
    () async {
      final reserved = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reserved.port;
      reserved.close();
      var revoked = false;
      final host = LanDiscoveryHost();
      await host.start(
        workspace: 'synthetic-workspace',
        httpPort: 18765,
        discoveryPort: port,
        tokenHash: (id) async => !revoked && id == 'paired-device'
            ? sha256.convert(utf8.encode('secret')).toString()
            : null,
      );
      Future<String?> find(String token) => discoverPairedLanHost(
        workspace: 'synthetic-workspace',
        deviceId: 'paired-device',
        token: token,
        port: port,
        targets: [InternetAddress.loopbackIPv4],
        timeout: const Duration(seconds: 2),
      );
      try {
        expect(await find('secret'), 'http://127.0.0.1:18765/api');
        expect(await find('wrong-secret'), isNull);
        revoked = true;
        expect(await find('secret'), isNull);
      } finally {
        host.close();
      }
    },
  );
  test('scheduler bounds transfers and serializes the same upload', () async {
    final scheduler = FileTransferScheduler();
    final release = Completer<void>(), started = <String>[];
    final first = scheduler.run(() async {
      started.add('a');
      await release.future;
    }, key: 'hash');
    final second = scheduler.run(() async {
      started.add('b');
    }, key: 'hash');
    final third = scheduler.run(() async {
      started.add('c');
      await release.future;
    });
    final fourth = scheduler.run(() async {
      started.add('d');
    });
    await Future<void>.delayed(Duration.zero);
    expect(started, ['a', 'c']);
    release.complete();
    await Future.wait([first, second, third, fourth]);
    expect(started.indexOf('b'), greaterThan(started.indexOf('a')));
    expect(started, containsAll(['a', 'b', 'c', 'd']));
  });
  test('relayed discovery cannot redirect a paired secret to an unsigned source address', () async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = socket.receive();
      if (packet == null) return;
      final request = jsonDecode(utf8.decode(packet.data)) as Map;
      final nonce = request['nonce'] as String;
      final key = sha256.convert(utf8.encode('synthetic-secret')).toString();
      const address = '192.0.2.99';
      final proof = Hmac(sha256, utf8.encode(key))
          .convert(
            utf8.encode(
              jsonEncode(['found', 'workspace', nonce, 8765, address]),
            ),
          )
          .toString();
      socket.send(
        utf8.encode(
          jsonEncode({
            'type': 'fly-lan-found',
            'workspace': 'workspace',
            'nonce': nonce,
            'port': 8765,
            'addresses': [address],
            'proof': proof,
          }),
        ),
        packet.address,
        packet.port,
      );
    });
    try {
      expect(
        await discoverPairedLanHost(
          workspace: 'workspace',
          deviceId: 'paired-device',
          token: 'synthetic-secret',
          port: socket.port,
          targets: [InternetAddress.loopbackIPv4],
          timeout: const Duration(milliseconds: 120),
        ),
        isNull,
      );
    } finally {
      await subscription.cancel();
      socket.close();
    }
  });
  test('slow file upload does not block business sync requests', () async {
    final root = await Directory.systemTemp.createTemp('fly-scheduling-');
    final db = AppDatabase(NativeDatabase.memory());
    final host = LanHostService(SyncOutboxRepository(db), root.path)
      ..syncFiles = true;
    final client = HttpClient();
    LanSyncTransport? transport;
    HttpClientRequest? slow;
    try {
      await db.ensureBuiltInData();
      final reserved = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = reserved.port;
      await reserved.close();
      await host.start(port: port);
      final endpoint = 'http://127.0.0.1:${host.port}/api';
      transport = LanSyncTransport(endpoint, token: () async => host.hostToken);
      final hash = sha256.convert(List.filled(32, 1)).toString();
      await transport.request(
        'POST',
        '/files/upload/init',
        body: {'sha256': hash, 'size': 32},
      );
      slow = await client.putUrl(
        Uri.parse('$endpoint/files/upload/$hash/chunk?offset=0'),
      );
      slow.headers.set('authorization', 'Bearer ${host.hostToken}');
      slow.contentLength = 32;
      slow.add([1]);
      await slow.flush();
      final info = await transport
          .request('GET', '/lan/info')
          .timeout(const Duration(seconds: 2));
      expect(info['workspaceId'], host.workspace);
    } finally {
      slow?.abort();
      client.close(force: true);
      transport?.close();
      await host.stop();
      await db.close();
      await root.delete(recursive: true);
    }
  });
}
