import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/updates/update_controller.dart';
import 'package:fly/core/updates/update_service.dart';

class _Source extends UpdateService {
  _Source(this.response);
  final Future<UpdateCheck> Function() response;
  @override
  Future<UpdateCheck> check() => response();
}

void main() {
  test('release versions compare numeric components and build numbers', () {
    expect(
      FlyVersion.parse('2.10').compareTo(FlyVersion.parse('2.9')),
      greaterThan(0),
    );
    expect(
      FlyVersion.parse('3.0').compareTo(FlyVersion.parse('2.99.99')),
      greaterThan(0),
    );
    expect(
      FlyVersion.parse('2.0.21+58').compareTo(FlyVersion.parse('2.0.21+57')),
      greaterThan(0),
    );
    expect(FlyVersion.parse('2.0').compareTo(FlyVersion.parse('2.0.0')), 0);
    expect(() => FlyVersion.parse('2.1-beta'), throwsFormatException);
  });

  test('update lookup sends platform only, handles newer/old/none and rejects cross-origin links', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    Map<String, Object>? latest;
    server.listen((request) async {
      paths.add(request.uri.toString());
      expect(request.headers.value('authorization'), isNull);
      expect(request.headers.value('cookie'), isNull);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'latest': latest}));
      await request.response.close();
    });
    try {
      final source = UpdateService(
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}/api'),
        platform: UpdatePlatform.windows,
        currentVersion: '2.0.21+57',
      );
      expect((await source.check()).latest, isNull);
      latest = {
        'version': '2.10.0',
        'build': 0,
        'fileName': 'Fly-2.10.exe',
        'size': 123,
        'sha256': List.filled(64, 'a').join(),
        'downloadPath': '/api/updates/download/Fly-2.10.exe',
      };
      final newer = await source.check();
      expect(newer.isNewer, isTrue);
      expect(newer.latest!.version.display, '2.10.0');
      latest['version'] = '2.0.0';
      expect((await source.check()).isNewer, isFalse);
      latest['downloadPath'] = 'https://other.invalid/installer.exe';
      await expectLater(source.check(), throwsFormatException);
      expect(paths, everyElement('/api/updates/latest/windows'));
    } finally {
      await server.close(force: true);
    }
  });

  test('auto-check failure is silent but manual failure is visible', () async {
    final controller = UpdateController(
      service: _Source(() async => throw const SocketException('offline')),
      launchDownload: (_) async => true,
    );
    await controller.check(silent: true);
    expect(controller.checkFailed, isFalse);
    expect(controller.showNotice, isFalse);
    await controller.check();
    expect(controller.checkFailed, isTrue);
    controller.dispose();
  });

  test('download requires user action, dismiss preserves manual update and handles launcher failure', () async {
    final release = AppRelease(
      version: FlyVersion.parse('3.0'),
      downloadUri: Uri.parse(
        'https://example.test/api/updates/download/Fly-3.0.exe',
      ),
      fileName: 'Fly-3.0.exe',
      size: 100,
      sha256: List.filled(64, 'a').join(),
    );
    final opened = <Uri>[];
    final controller = UpdateController(
      service: _Source(() async => UpdateCheck(latest: release, isNewer: true)),
      launchDownload: (uri) async {
        opened.add(uri);
        return false;
      },
    );
    await controller.check(silent: true);
    expect(opened, isEmpty);
    expect(controller.showNotice, isTrue);
    controller.dismiss();
    expect(controller.showNotice, isFalse);
    expect(controller.result!.isNewer, isTrue);
    await controller.download();
    expect(opened, [release.downloadUri]);
    expect(controller.downloadFailed, isTrue);
    controller.dispose();
  });
}
