import 'package:flutter_test/flutter_test.dart';
import 'package:fly/features/sync/domain/sync_protocol.dart';

void main() {
  final supported = {
    'world-workshop.cn/api': 'https://world-workshop.cn/api',
    '192.168.0.21/api': 'http://192.168.0.21/api',
    '192.168.0.21:8765/api': 'http://192.168.0.21:8765/api',
    '198.51.100.10:8000': 'http://198.51.100.10:8000/api',
    'http://198.51.100.10:8000': 'http://198.51.100.10:8000/api',
    'http://198.51.100.10:8000/api/': 'http://198.51.100.10:8000/api',
    'https://198.51.100.10:8443': 'https://198.51.100.10:8443/api',
    'sync.example.com:8080': 'http://sync.example.com:8080/api',
    'http://sync.example.com': 'http://sync.example.com/api',
    'https://sync.example.com/': 'https://sync.example.com/api',
    'https://sync.example.com/api': 'https://sync.example.com/api',
    'https://sync.example.com/fly/api/': 'https://sync.example.com/fly/api',
    'http://[2001:db8::1]:8000': 'http://[2001:db8::1]:8000/api',
    '[2001:db8::1]:8000': 'http://[2001:db8::1]:8000/api',
    'https://[2001:db8::1]:8443': 'https://[2001:db8::1]:8443/api',
    '  http://192.168.1.20:8765/  ': 'http://192.168.1.20:8765/api',
  };
  for (final entry in supported.entries) {
    test('normalizes ${entry.key}', () {
      final base = SyncServerConfig.validate(entry.key);
      expect(base.toString(), entry.value);
      final websocket = SyncServerConfig.websocketUrl(entry.key);
      expect(websocket.host, base.host);
      expect(websocket.port, base.port);
      expect(websocket.path.endsWith('/api/ws'), isTrue);
    });
  }
  for (final invalid in [
    '',
    'http://',
    'ftp://example.com',
    'https://user:password@example.com',
    'https://example.com?token=private',
    'https://example.com#fragment',
    'http://example.com:0',
    'http://example.com:65536',
    'http://example.com:not-a-port',
    'https://example.com/unrelated',
    'https://example.com/../api',
  ]) {
    test('rejects malformed address $invalid', () {
      expect(() => SyncServerConfig.validate(invalid), throwsFormatException);
    });
  }
  test('cloud file contents stay disabled for all accounts and addresses', () {
    for (final url in [
      'world-workshop.cn/api',
      'http://world-workshop.cn:8765/api',
      'https://WORLD-WORKSHOP.CN/fly/api',
    ]) {
      expect(
        SyncServerConfig.allowsCloudFiles(url, 'other@example.com'),
        isFalse,
      );
      expect(
        SyncServerConfig.allowsCloudFiles(url, ' MAX@CEILING-ARTS.COM '),
        isFalse,
      );
    }
    expect(
      SyncServerConfig.allowsCloudFiles(
        '192.168.0.21:8765/api',
        'other@example.com',
      ),
      isFalse,
    );
  });
  test('pairing QR validates type, local address and expiration', () {
    final now = DateTime(2026, 10, 13);
    final valid = LanPairingPayload(
      ['http://192.168.0.21:8765/api'],
      '123456',
      now.add(const Duration(minutes: 5)),
    );
    expect(
      LanPairingPayload.decode(valid.encode(), now: now).endpoints,
      valid.endpoints,
    );
    expect(
      () => LanPairingPayload.decode(
        valid.encode(),
        now: now.add(const Duration(minutes: 6)),
      ),
      throwsFormatException,
    );
    expect(
      () => LanPairingPayload.decode(
        LanPairingPayload(
          ['https://example.com/api'],
          '123456',
          valid.expiresAt,
        ).encode(),
        now: now,
      ),
      throwsFormatException,
    );
    expect(
      () => LanPairingPayload.decode('{}', now: now),
      throwsFormatException,
    );
  });
}
