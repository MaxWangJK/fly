import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../account/data/auth_service.dart';
import '../domain/sync_protocol.dart';

class SyncNotificationService {
  SyncNotificationService(this.auth, this.wake);
  final AuthService auth;
  final void Function() wake;
  WebSocket? _socket;
  Timer? _retry;
  bool _stopped = false;
  static Future<WebSocket> openSocket(String server) async {
    final base = SyncServerConfig.validate(server);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..connectionFactory = (uri, proxyHost, proxyPort) {
        // Dart's WebSocket handshake can follow HTTP redirects. A fresh client
        // checks every new connection before any authentication frame is sent.
        if (uri.origin != base.origin) {
          throw StateError('WebSocket 服务器不允许跨源重定向');
        }
        final hostname = uri.host.startsWith('[')
            ? uri.host.substring(1, uri.host.length - 1)
            : uri.host;
        if (uri.scheme == 'https' && proxyHost == null) {
          return SecureSocket.startConnect(hostname, uri.port);
        }
        return Socket.startConnect(
          proxyHost ?? hostname,
          proxyPort ?? uri.port,
        );
      };
    try {
      final uri = SyncServerConfig.websocketUrl(server);
      return await WebSocket.connect(
        '$uri',
        customClient: client,
      ).timeout(const Duration(seconds: 15));
    } finally {
      // Upgraded sockets are detached from HttpClient and retain their lifetime.
      client.close(force: true);
    }
  }

  static bool isSyncNotification(Object? message) {
    if (message is! String) return false;
    try {
      final value = jsonDecode(message);
      return value is Map && value['type'] == 'sync_available';
    } on FormatException {
      return false;
    }
  }

  Future<void> connect() async {
    if (_stopped) return;
    try {
      await auth.refresh();
      final socket = await openSocket(auth.server);
      if (_stopped) {
        await socket.close();
        return;
      }
      _socket = socket;
      socket.add(await auth.accessToken());
      wake();
      socket.listen(
        (message) {
          if (isSyncNotification(message)) wake();
        },
        onError: (Object _) => _reconnect(),
        onDone: _reconnect,
        cancelOnError: true,
      );
    } on Object {
      _reconnect();
    }
  }

  void _reconnect() {
    _socket = null;
    if (_stopped) return;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 15), () => unawaited(connect()));
  }

  void dispose() {
    _stopped = true;
    _retry?.cancel();
    unawaited(_socket?.close());
  }
}
