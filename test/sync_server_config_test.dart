import 'package:flutter_test/flutter_test.dart';
import 'package:fly/features/sync/domain/sync_protocol.dart';

void main() {
  final supported = {
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
}
