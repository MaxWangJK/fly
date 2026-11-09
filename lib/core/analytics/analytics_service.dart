import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../../config/service_endpoints.dart';
import 'analytics_action.dart';
import 'analytics_storage.dart';

abstract interface class AnalyticsTransport {
  Future<bool> send(String code, AnalyticsAction action);
}

class HttpAnalyticsTransport implements AnalyticsTransport {
  HttpAnalyticsTransport({
    Uri? baseUrl,
    this.timeout = const Duration(seconds: 4),
  }) : baseUrl = baseUrl ?? FlyServiceEndpoints.analyticsBaseUrl;
  final Uri baseUrl;
  final Duration timeout;

  @override
  Future<bool> send(String code, AnalyticsAction action) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..autoUncompress = false
      ..userAgent = 'Fly';
    try {
      return await (() async {
        final request = await client.postUrl(
          FlyServiceEndpoints.endpoint(baseUrl, [
            'stats',
            code,
            '${action.code}',
          ]),
        );
        request.followRedirects = false;
        request.contentLength = 0;
        final response = await request.close();
        return response.statusCode >= 200 && response.statusCode < 300;
      })().timeout(timeout);
    } on Object {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}

/// Installation analytics only: no business/account repository dependencies.
class AnalyticsService {
  AnalyticsService({
    required this.storage,
    required this.transport,
    DateTime Function()? clock,
    String Function()? generateCode,
  }) : clock = clock ?? DateTime.now,
       generateCode = generateCode ?? randomDeviceCode;

  final AnalyticsStorage storage;
  final AnalyticsTransport transport;
  final DateTime Function() clock;
  final String Function() generateCode;
  Future<void>? _running;

  static String randomDeviceCode() {
    // 32 unambiguous symbols, 16 characters = 80 random bits. No hardware reads.
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(
      16,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  static String statisticsDay(DateTime value) => value
      .toUtc()
      .add(const Duration(hours: 8))
      .toIso8601String()
      .substring(0, 10);

  /// Call without awaiting from startup/foreground. Concurrent calls coalesce;
  /// subsequent calls read persisted success flags and do not send again today.
  Future<void> initialize() =>
      _running ??= _initialize().whenComplete(() => _running = null);

  Future<void> _initialize() async {
    try {
      final state = await storage.loadOrCreate(generateCode);
      if (!state.installReported) {
        try {
          if (await transport.send(state.deviceCode, AnalyticsAction.install)) {
            await storage.markInstallReported(state.deviceCode);
          }
        } on Object {
          // Deliberately silent; retry on the next launch/foreground.
        }
      }
      final today = statisticsDay(clock());
      if (state.lastOpenDate != today) {
        try {
          if (await transport.send(state.deviceCode, AnalyticsAction.open)) {
            await storage.markDailyOpenReported(state.deviceCode, today);
          }
        } on Object {
          // No dialogs, banners, logs, or background retry loops.
        }
      }
    } on Object {
      // Storage/network failures must never escape into application startup.
    }
  }
}
