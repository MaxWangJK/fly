import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/features/sync/data/cloud_sync_transport.dart';
import 'package:fly/features/sync/services/lan_file_response.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'interrupted download resumes after restart and verifies byte identity',
    () async {
      final root = await Directory.systemTemp.createTemp('fly-range-');
      final bytes = Uint8List.fromList(
        List.generate(512 * 1024, (i) => i % 251),
      );
      final hash = sha256.convert(bytes).toString();
      final source = File('${root.path}/source')..writeAsBytesSync(bytes);
      final partial = File('${root.path}/received.part');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var first = true;
      String? range;
      server.listen((request) async {
        if (first) {
          first = false;
          request.response.contentLength = bytes.length;
          request.response.headers.set('etag', '"$hash"');
          final socket = await request.response.detachSocket();
          socket.add(bytes.sublist(0, 65536));
          await socket.flush();
          socket.destroy();
        } else {
          range = request.headers.value('range');
          await serveLanFile(request, source, hash);
        }
      });
      final endpoint = 'http://127.0.0.1:${server.port}/api';
      var transport = CloudSyncTransport(endpoint);
      try {
        await expectLater(
          transport.downloadWithProgress(
            '/file',
            partial.path,
            expectedSha256: hash,
            expectedSize: bytes.length,
          ),
          throwsA(isA<Object>()),
        );
        transport.close();
        final offset = await partial.length();
        expect(offset, greaterThan(0));
        expect(offset, lessThan(bytes.length));
        // A new transport instance models application restart, without deleting the partial.
        transport = CloudSyncTransport(endpoint);
        final progress = <int>[];
        await transport.downloadWithProgress(
          '/file',
          partial.path,
          expectedSha256: hash,
          expectedSize: bytes.length,
          onProgress: (received, _) => progress.add(received),
        );
        expect(range, 'bytes=$offset-');
        expect(progress.first, offset);
        expect(await partial.readAsBytes(), bytes);
        expect(sha256.convert(await partial.readAsBytes()).toString(), hash);
      } finally {
        transport.close();
        await server.close(force: true);
        await root.delete(recursive: true);
      }
    },
  );

  for (final scenario in [
    'ignores-range',
    'different-content',
    'wrong-etag',
    'oversized',
  ]) {
    test('download safely handles $scenario', () async {
      final root = await Directory.systemTemp.createTemp('fly-range-case-');
      final bytes = utf8.encode('The complete synthetic file content.');
      final hash = sha256.convert(bytes).toString();
      final partial = File('${root.path}/file.part');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final endpoint = 'http://127.0.0.1:${server.port}/api';
      String? range;
      server.listen((request) async {
        range = request.headers.value('range');
        if (scenario == 'wrong-etag') {
          request.response.statusCode = 206;
          request.response.headers.set(
            'content-range',
            'bytes 5-${bytes.length - 1}/${bytes.length}',
          );
          request.response.headers.set('etag', '"other"');
          request.response.add(bytes.sublist(5));
        } else {
          request.response.add(scenario == 'oversized' ? [...bytes, 0] : bytes);
        }
        await request.response.close();
      });
      await partial.writeAsBytes(bytes.take(5).toList());
      await File('${partial.path}.resume.json').writeAsString(
        jsonEncode([
          '$endpoint/file',
          scenario == 'different-content' ? 'old-hash' : hash,
          bytes.length,
        ]),
      );
      final transport = CloudSyncTransport(endpoint);
      try {
        final future = transport.downloadWithProgress(
          '/file',
          partial.path,
          expectedSha256: hash,
          expectedSize: bytes.length,
        );
        if (scenario == 'wrong-etag' || scenario == 'oversized') {
          await expectLater(future, throwsFormatException);
          expect(await partial.exists(), isFalse);
        } else {
          await future;
          expect(await partial.readAsBytes(), bytes);
          expect(range, scenario == 'different-content' ? isNull : 'bytes=5-');
        }
      } finally {
        transport.close();
        await server.close(force: true);
        await root.delete(recursive: true);
      }
    });
  }

  test('LAN file response uses authenticated caller range and rejects invalid offset', () async {
    final root = await Directory.systemTemp.createTemp('fly-range-server-');
    final file = File('${root.path}/data')..writeAsStringSync('0123456789');
    final hash = sha256.convert(utf8.encode('0123456789')).toString();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => serveLanFile(request, file, hash));
    final client = HttpClient();
    try {
      Future<HttpClientResponse> get(String range, String tag) async {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/'),
        );
        request.headers.set('range', range);
        request.headers.set('if-range', tag);
        return request.close();
      }

      final resumed = await get('bytes=4-', '"$hash"');
      expect(resumed.statusCode, 206);
      expect(resumed.headers.value('content-range'), 'bytes 4-9/10');
      expect(await utf8.decoder.bind(resumed).join(), '456789');
      final changed = await get('bytes=4-', '"old-version"');
      expect(changed.statusCode, 200);
      expect(await utf8.decoder.bind(changed).join(), '0123456789');
      final invalid = await get('bytes=999-', '"$hash"');
      expect(invalid.statusCode, 416);
      await invalid.drain<void>();
    } finally {
      client.close(force: true);
      await server.close(force: true);
      await root.delete(recursive: true);
    }
  });
}
