import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly/features/sync/services/sync_notification_service.dart';

void main() {
  test('notification socket stays usable after the HTTP handshake', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((message) => socket.add(message));
    });
    WebSocket? socket;
    try {
      socket = await SyncNotificationService.openSocket(
        'http://127.0.0.1:${server.port}/api',
      );
      final response = socket.first;
      socket.add('sync_available');
      expect(
        await response.timeout(const Duration(seconds: 3)),
        'sync_available',
      );
    } finally {
      await socket?.close();
      await server.close(force: true);
    }
  });

  test('notification redirects cannot connect to another origin', () async {
    final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var targetRequests = 0;
    target.listen((request) async {
      targetRequests++;
      final socket = await WebSocketTransformer.upgrade(request);
      await socket.close();
    });
    source.listen((request) async {
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(
          HttpHeaders.locationHeader,
          'http://127.0.0.1:${target.port}/api/ws',
        );
      await request.response.close();
    });
    try {
      await expectLater(
        SyncNotificationService.openSocket(
          'http://127.0.0.1:${source.port}/api',
        ),
        throwsA(isA<StateError>()),
      );
      expect(targetRequests, 0);
    } finally {
      await source.close(force: true);
      await target.close(force: true);
    }
  });
}
