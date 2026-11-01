import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../account/data/auth_service.dart';
import '../domain/sync_protocol.dart';

class SyncNotificationService {
  SyncNotificationService(
    this.auth,
    this.wake, {
    Future<WebSocket> Function(String)? open,
    Duration Function(int)? retryDelay,
  }) : _open = open ?? openSocket,
       _retryDelay = retryDelay ?? reconnectDelay;
  final AuthService auth;
  final void Function() wake;
  final Future<WebSocket> Function(String) _open;
  final Duration Function(int) _retryDelay;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _messages;
  Timer? _retry;
  Future<void>? _connecting;
  int _failures = 0;
  bool _stopped = false;

  static Duration reconnectDelay(int failures) =>
      Duration(seconds: (2 << (failures - 1).clamp(0, 5)).clamp(2, 60));
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

  static String? _messageType(Object? message) {
    if (message is! String) return null;
    try {
      final value = jsonDecode(message);
      return value is Map && value['type'] is String
          ? value['type'] as String
          : null;
    } on FormatException {
      return null;
    }
  }

  static bool isSyncNotification(Object? message) =>
      _messageType(message) == 'sync_available';

  Future<void> connect() {
    if (_stopped || _socket != null) return Future.value();
    _retry?.cancel();
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<void> _connect() async {
    try {
      await auth.refresh();
      if (_stopped) return;
      final socket = await _open(auth.server);
      if (_stopped) {
        await socket.close();
        return;
      }
      _socket = socket;
      socket.pingInterval = const Duration(seconds: 30);
      socket.add(await auth.accessToken());
      _messages = socket.listen(
        (message) {
          if (_stopped || !identical(_socket, socket)) return;
          if (isSyncNotification(message)) {
            _failures = 0;
            wake();
          } else if (_messageType(message) == 'heartbeat') {
            _failures = 0;
          }
        },
        onError: (Object _) => _reconnect(socket),
        onDone: () => _reconnect(socket),
        cancelOnError: true,
      );
    } on Object {
      _reconnect();
    }
  }

  void _reconnect([WebSocket? failed]) {
    if (failed != null && !identical(failed, _socket)) return;
    final socket = _socket;
    _socket = null;
    unawaited(_messages?.cancel());
    _messages = null;
    unawaited(socket?.close());
    if (_stopped) return;
    if (_retry?.isActive == true) return;
    _retry = Timer(_retryDelay(++_failures), () => unawaited(connect()));
  }

  void dispose() {
    _stopped = true;
    _retry?.cancel();
    unawaited(_messages?.cancel());
    _messages = null;
    unawaited(_socket?.close());
    _socket = null;
  }
}
