import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

String _proof(String tokenHash, List<Object> values) => Hmac(
  sha256,
  utf8.encode(tokenHash),
).convert(utf8.encode(jsonEncode(values))).toString();
bool _equal(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

/// Discovery proves possession of a previously paired secret; it never pairs a
/// new device and never broadcasts that secret or any business records.
class LanDiscoveryHost {
  RawDatagramSocket? _socket;
  Future<void> start({
    required String workspace,
    required int httpPort,
    required Future<String?> Function(String deviceId) tokenHash,
    int discoveryPort = 8766,
  }) async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
      );
      _socket = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null || datagram.data.length > 2048) return;
        unawaited(() async {
          try {
            final data = jsonDecode(utf8.decode(datagram.data)) as Map;
            final id = data['deviceId'], nonce = data['nonce'];
            if (data['type'] != 'fly-lan-discover' ||
                data['workspace'] != workspace ||
                id is! String ||
                id.length > 80 ||
                nonce is! String ||
                nonce.length != 36) {
              return;
            }
            final key = await tokenHash(id);
            if (key == null ||
                !_equal(
                  '${data['proof']}',
                  _proof(key, ['find', workspace, id, nonce]),
                )) {
              return;
            }
            final addresses = [
              for (final adapter in await NetworkInterface.list(
                type: InternetAddressType.IPv4,
                includeLoopback: true,
              ))
                for (final address in adapter.addresses) address.address,
            ].take(32).toList();
            final reply = jsonEncode({
              'type': 'fly-lan-found',
              'workspace': workspace,
              'nonce': nonce,
              'port': httpPort,
              'addresses': addresses,
              'proof': _proof(key, [
                'found',
                workspace,
                nonce,
                httpPort,
                ...addresses,
              ]),
            });
            socket.send(utf8.encode(reply), datagram.address, datagram.port);
          } on Object {
            /* Malformed or late discovery packets are ignored. */
          }
        }());
      });
    } on SocketException {
      /* QR and saved addresses remain usable if UDP is blocked. */
    }
  }

  void close() {
    _socket?.close();
    _socket = null;
  }
}

Future<String?> discoverPairedLanHost({
  required String workspace,
  required String deviceId,
  required String token,
  int port = 8766,
  List<InternetAddress>? targets,
  Duration timeout = const Duration(milliseconds: 900),
}) async {
  RawDatagramSocket? socket;
  StreamSubscription<RawSocketEvent>? subscription;
  Timer? timer;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final nonce = const Uuid().v4(), result = Completer<String?>();
    final key = sha256.convert(utf8.encode(token)).toString();
    subscription = socket.listen((event) {
      if (event != RawSocketEvent.read || result.isCompleted) return;
      final datagram = socket!.receive();
      if (datagram == null || datagram.data.length > 2048) return;
      try {
        final data = jsonDecode(utf8.decode(datagram.data)) as Map;
        final tcpPort = data['port'];
        final addresses = data['addresses'];
        if (data['type'] != 'fly-lan-found' ||
            data['workspace'] != workspace ||
            data['nonce'] != nonce ||
            tcpPort is! int ||
            tcpPort < 1 ||
            tcpPort > 65535 ||
            addresses is! List ||
            addresses.length > 32 ||
            addresses.any((value) => value is! String) ||
            !addresses.contains(datagram.address.address) ||
            !_equal(
              '${data['proof']}',
              _proof(key, [
                'found',
                workspace,
                nonce,
                tcpPort,
                ...addresses.cast<String>(),
              ]),
            )) {
          return;
        }
        result.complete('http://${datagram.address.address}:$tcpPort/api');
      } on Object {
        /* Untrusted announcements cannot change the paired host. */
      }
    });
    final payload = utf8.encode(
      jsonEncode({
        'type': 'fly-lan-discover',
        'workspace': workspace,
        'deviceId': deviceId,
        'nonce': nonce,
        'proof': _proof(key, ['find', workspace, deviceId, nonce]),
      }),
    );
    for (final target in targets ?? [InternetAddress('255.255.255.255')]) {
      socket.send(payload, target, port);
    }
    timer = Timer(timeout, () {
      if (!result.isCompleted) result.complete(null);
    });
    return await result.future;
  } on SocketException {
    return null;
  } finally {
    timer?.cancel();
    await subscription?.cancel();
    socket?.close();
  }
}
