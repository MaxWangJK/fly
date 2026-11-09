import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/analytics/analytics_action.dart';
import 'package:fly/core/analytics/analytics_service.dart';
import 'package:fly/core/analytics/analytics_storage.dart';

class _Transport implements AnalyticsTransport {
  final actions = <int>[];
  final codes = <String>[];
  final failures = <int>{};
  @override
  Future<bool> send(String code, AnalyticsAction action) async {
    actions.add(action.code);
    codes.add(code);
    return !failures.contains(action.code);
  }
}

void main() {
  late Directory directory;
  late File file;
  late FileAnalyticsStorage storage;
  late _Transport transport;
  var today = DateTime.utc(2026, 11, 9, 4);
  AnalyticsService service() => AnalyticsService(
    storage: storage,
    transport: transport,
    clock: () => today,
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fly-anonymous-test-');
    file = File('${directory.path}/anonymous-analytics.json');
    storage = FileAnalyticsStorage(file);
    transport = _Transport();
    today = DateTime.utc(2026, 11, 9, 4);
  });
  tearDown(() async => directory.delete(recursive: true));

  test('analytics device code generation uses 16 secure Base32 symbols', () {
    final codes = {
      for (var i = 0; i < 2000; i++) AnalyticsService.randomDeviceCode(),
    };
    expect(codes.length, 2000);
    expect(
      codes.every((code) => RegExp(r'^[A-HJ-NP-Z2-9]{16}$').hasMatch(code)),
      isTrue,
    );
  });

  test(
    'analytics install once persists before requests and survives reopening',
    () async {
      await service().initialize();
      expect(transport.actions, [1, 2]);
      final saved = AnalyticsState.fromJson(
        jsonDecode(await file.readAsString()),
      );
      expect(saved.installReported, isTrue);
      expect(saved.lastOpenDate, '2026-11-09');
      expect(transport.codes.toSet(), {saved.deviceCode});
      storage = FileAnalyticsStorage(file);
      await service().initialize();
      expect(transport.actions, [1, 2]);
    },
  );

  test('analytics daily open once and next day send only action 2', () async {
    final reporter = service();
    await reporter.initialize();
    await Future.wait([reporter.initialize(), reporter.initialize()]);
    expect(transport.actions, [1, 2]);
    today = today.add(const Duration(days: 1));
    await reporter.initialize();
    expect(transport.actions, [1, 2, 2]);
    final saved = await storage.loadOrCreate(
      () => throw StateError('Must retain the original code'),
    );
    expect(saved.lastOpenDate, '2026-11-10');
  });

  test(
    'analytics failed install retries later even if daily open succeeded',
    () async {
      transport.failures.add(1);
      await service().initialize();
      var saved = await storage.loadOrCreate(AnalyticsService.randomDeviceCode);
      expect(saved.installReported, isFalse);
      expect(saved.lastOpenDate, '2026-11-09');
      transport.failures.clear();
      await service().initialize();
      saved = await storage.loadOrCreate(AnalyticsService.randomDeviceCode);
      expect(saved.installReported, isTrue);
      expect(transport.actions, [1, 2, 1]);
    },
  );

  test(
    'analytics failed open retries without resending successful install',
    () async {
      transport.failures.add(2);
      await service().initialize();
      final failed = await storage.loadOrCreate(
        AnalyticsService.randomDeviceCode,
      );
      expect(failed.installReported, isTrue);
      expect(failed.lastOpenDate, isNull);
      transport.failures.clear();
      await service().initialize();
      expect(transport.actions, [1, 2, 2]);
    },
  );

  test('analytics uses Shanghai date at UTC midnight boundaries', () {
    expect(
      AnalyticsService.statisticsDay(DateTime.utc(2026, 11, 8, 15, 59)),
      '2026-11-08',
    );
    expect(
      AnalyticsService.statisticsDay(DateTime.utc(2026, 11, 8, 16)),
      '2026-11-09',
    );
  });

  test('concurrent storage instances keep one installation identity', () async {
    final other = FileAnalyticsStorage(file);
    final states = await Future.wait([
      storage.loadOrCreate(AnalyticsService.randomDeviceCode),
      other.loadOrCreate(AnalyticsService.randomDeviceCode),
    ]);
    expect(states.map((s) => s.deviceCode).toSet().length, 1);
    await Future.wait([
      storage.markInstallReported(states.first.deviceCode),
      other.markDailyOpenReported(states.first.deviceCode, '2026-11-09'),
    ]);
    final saved = await storage.loadOrCreate(AnalyticsService.randomDeviceCode);
    expect(saved.installReported, isTrue);
    expect(saved.lastOpenDate, '2026-11-09');
  });

  test(
    'unreadable analytics config fails silently and is not overwritten',
    () async {
      await file.writeAsString('damaged configuration');
      await service().initialize();
      expect(transport.actions, isEmpty);
      expect(await file.readAsString(), 'damaged configuration');
    },
  );

  test('analytics wire protocol sends only code and numeric action with no body or credentials', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <(String, String, String, String?, String?, String?)>[];
    server.listen((request) async {
      requests.add((
        request.method,
        request.uri.toString(),
        await utf8.decoder.bind(request).join(),
        request.headers.value('authorization'),
        request.headers.value('cookie'),
        request.headers.value('user-agent'),
      ));
      request.response.statusCode = 200;
      await request.response.close();
    });
    try {
      final http = HttpAnalyticsTransport(
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}/api'),
      );
      await AnalyticsService(
        storage: storage,
        transport: http,
        generateCode: () => 'RANDOMCODE2345678',
        clock: () => today,
      ).initialize();
      expect(requests, [
        ('POST', '/api/stats/RANDOMCODE2345678/1', '', null, null, 'Fly'),
        ('POST', '/api/stats/RANDOMCODE2345678/2', '', null, null, 'Fly'),
      ]);
    } finally {
      await server.close(force: true);
    }
  });

  test(
    'HTTP failures and timeout remain silent without marking success',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var hang = false;
      server.listen((request) async {
        if (hang) return;
        request.response.statusCode = 404;
        await request.response.close();
      });
      try {
        final http = HttpAnalyticsTransport(
          baseUrl: Uri.parse('http://127.0.0.1:${server.port}/api'),
          timeout: const Duration(milliseconds: 60),
        );
        expect(
          await http.send('RANDOMCODE2345678', AnalyticsAction.install),
          isFalse,
        );
        hang = true;
        expect(
          await http.send('RANDOMCODE2345678', AnalyticsAction.open),
          isFalse,
        );
      } finally {
        await server.close(force: true);
      }
    },
  );
}
