import 'dart:async';
import 'dart:io';

import '../domain/sync_protocol.dart';
import 'sync_notification_service.dart';

/// LAN presence and change hints use the already paired device credential.
/// Heartbeats keep presence alive without scanning or exchanging business data.
class LanSyncNotifications {
  LanSyncNotifications({required this.onChange, required this.onDisconnect});
  final void Function() onChange, onDisconnect;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _messages;
  bool _disposed = false;

  Future<void> connect(String endpoint, String token) async {
    final base = SyncServerConfig.validate(endpoint);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    // Never send a paired credential to a redirected origin.
    client.connectionFactory = (uri, proxyHost, proxyPort) {
      if (uri.origin != base.origin) throw StateError('LAN redirect rejected');
      final host = uri.host.replaceAll(RegExp(r'^\[|\]$'), '');
      if (uri.scheme == 'https' && proxyHost == null) {
        return SecureSocket.startConnect(host, uri.port);
      }
      return Socket.startConnect(proxyHost ?? host, proxyPort ?? uri.port);
    };
    try {
      final uri = base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '${base.path}/lan/events',
      );
      final socket = await WebSocket.connect(
        '$uri',
        headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
        customClient: client,
      ).timeout(const Duration(seconds: 8));
      if (_disposed) {
        await socket.close();
        return;
      }
      _socket = socket;
      socket.pingInterval = const Duration(seconds: 45);
      _messages = socket.listen(
        (message) {
          if (!_disposed &&
              SyncNotificationService.isSyncNotification(message)) {
            onChange();
          }
        },
        onDone: _disconnected,
        onError: (Object _) => _disconnected(),
        cancelOnError: true,
      );
    } finally {
      client.close(force: true);
    }
  }

  void _disconnected() {
    if (_disposed) return;
    dispose();
    onDisconnect();
  }

  void dispose() {
    _disposed = true;
    unawaited(_messages?.cancel());
    unawaited(_socket?.close());
    _socket = null;
  }
}
