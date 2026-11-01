import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly/features/account/data/auth_service.dart';
import 'package:fly/features/sync/services/sync_notification_service.dart';

class _Auth extends AuthService {
  _Auth(String server) : super(server, 'notification-test');
  int refreshes = 0;
  Future<void>? gate;
  @override
  Future<void> refresh() async {
    refreshes++;
    await gate;
  }

  @override
  Future<String?> accessToken() async => 'isolated-test-token';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test('only authenticated change hints wake sync, and concurrent connects share one socket', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    final received = Completer<void>(), gate = Completer<void>();
    var tokens = 0, wakes = 0;
    final auth = _Auth('http://127.0.0.1:${server.port}/api')
      ..gate = gate.future;
    final service = SyncNotificationService(auth, () {
      wakes++;
      if (!received.isCompleted) received.complete();
    });
    server.listen((request) async {
      expect(request.uri.path, '/api/ws');
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((message) {
        expect(message, 'isolated-test-token');
        tokens++;
        socket.add('{"type":"heartbeat"}');
        socket.add('not JSON');
        socket.add('{"type":"other"}');
        socket.add('{"type":"sync_available","latest_cursor":7}');
      });
    });
    try {
      final first = service.connect(), second = service.connect();
      gate.complete();
      await Future.wait([first, second]);
      await received.future.timeout(const Duration(seconds: 4));
      expect(auth.refreshes, 1);
      expect(sockets, hasLength(1));
      expect(tokens, 1);
      expect(wakes, 1);
    } finally {
      service.dispose();
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    }
  });

  test(
    'failed connections back off, recover and stop reconnecting after disposal',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final received = Completer<void>();
      final retries = <int>[];
      var opens = 0;
      final service = SyncNotificationService(
        _Auth('http://127.0.0.1:${server.port}/api'),
        () {
          if (!received.isCompleted) received.complete();
        },
        open: (server) async {
          opens++;
          if (opens < 3) throw const SocketException('Synthetic offline state');
          return SyncNotificationService.openSocket(server);
        },
        retryDelay: (failure) {
          retries.add(failure);
          return const Duration(milliseconds: 15);
        },
      );
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen(
          (_) => socket.add('{"type":"sync_available","latest_cursor":0}'),
        );
      });
      try {
        await service.connect();
        await received.future.timeout(const Duration(seconds: 4));
        expect(retries, [1, 2]);
        expect(opens, 3);
        expect(
          [
            for (var i = 1; i <= 8; i++)
              SyncNotificationService.reconnectDelay(i).inSeconds,
          ],
          [2, 4, 8, 16, 32, 60, 60, 60],
        );
        service.dispose();
        await sockets.single.close();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(opens, 3);
      } finally {
        service.dispose();
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
      }
    },
  );

  test('disposing during a delayed handshake closes the late socket without sending a token', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final late = Completer<WebSocket>(), opening = Completer<void>();
    final sockets = <WebSocket>[];
    var tokens = 0, wakes = 0;
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((_) => tokens++);
    });
    final auth = _Auth('http://127.0.0.1:${server.port}/api');
    final service = SyncNotificationService(
      auth,
      () => wakes++,
      open: (_) {
        opening.complete();
        return late.future;
      },
    );
    try {
      final connection = service.connect();
      await opening.future;
      service.dispose();
      late.complete(await SyncNotificationService.openSocket(auth.server));
      await connection;
      expect(tokens, 0);
      expect(wakes, 0);
    } finally {
      service.dispose();
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    }
  });
}
