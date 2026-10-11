import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../config/app_version.dart';
import '../../sync/data/cloud_sync_transport.dart';

class AuthService {
  AuthService(this.server, this.scope, {FlutterSecureStorage? storage})
    : storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );
  final String server, scope;
  final FlutterSecureStorage storage;
  Map<String, dynamic>? session;
  Future<void>? _refreshing;
  String get storageKey =>
      'fly-sync-${sha256.convert(utf8.encode('$server:$scope'))}';
  String? get email => session?['email'] as String?;
  String? get userId => session?['userId'] as String?;
  String? get deviceId => session?['deviceId'] as String?;
  Future<String?> accessToken() async => session?['accessToken'] as String?;

  Future<void> restore() async {
    final saved = await storage.read(key: storageKey);
    if (saved != null) {
      session = (jsonDecode(saved) as Map).cast<String, dynamic>();
    }
  }

  Future<void> _persist(Map<String, dynamic> data) async {
    await storage.write(key: storageKey, value: jsonEncode(data));
    session = data;
  }

  Future<void> authenticate({
    required bool register,
    required String email,
    required String password,
    String? confirm,
  }) async {
    if (register && password != confirm) throw ArgumentError('两次密码不一致');
    if (password.length < 10) throw ArgumentError('密码至少需要 10 个字符');
    final transport = CloudSyncTransport(server);
    try {
      final data = await transport.request(
        'POST',
        register ? '/auth/register' : '/auth/login',
        body: {
          'email': email.trim().toLowerCase(),
          'password': password,
          'deviceName': Platform.localHostname,
          'platform': Platform.operatingSystem,
          'deviceType': Platform.isAndroid || Platform.isIOS
              ? 'mobile'
              : 'desktop',
          'appVersion': flyAppVersion,
        },
      );
      await _persist(data);
    } on SyncHttpException catch (e) {
      if (register && e.status == 409) {
        throw ArgumentError('此邮箱已注册，请登录');
      }
      if (!register && e.status == 401) {
        throw ArgumentError('邮箱或密码错误');
      }
      if (e.status == 422) {
        throw ArgumentError('请检查邮箱格式和密码长度');
      }
      rethrow;
    } finally {
      transport.close();
    }
  }

  Future<void> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  Future<void> _refresh() async {
    final refresh = session?['refreshToken'];
    if (refresh == null) throw StateError('请先登录');
    final transport = CloudSyncTransport(server);
    try {
      await _persist(
        await transport.request(
          'POST',
          '/auth/refresh',
          body: {'refreshToken': refresh},
        ),
      );
    } finally {
      transport.close();
    }
  }

  Future<void> logout() async {
    final transport = CloudSyncTransport(
      server,
      token: accessToken,
      onUnauthorized: refresh,
    );
    try {
      await transport.request('POST', '/auth/logout');
    } finally {
      transport.close();
      await storage.delete(key: storageKey);
      session = null;
    }
  }
}
