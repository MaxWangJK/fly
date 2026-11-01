import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../config/app_version.dart';
import '../../sync/data/cloud_sync_transport.dart';

class EmailCaptcha {
  const EmailCaptcha(this.id, this.image);
  final String id;
  final Uint8List image;
}

class EmailAuthException implements Exception {
  const EmailAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

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
  bool get emailVerified => session?['emailVerified'] == true;
  Future<String?> accessToken() async => session?['accessToken'] as String?;

  Future<void> restore() async {
    final saved = await storage.read(key: storageKey);
    if (saved != null) {
      session = (jsonDecode(saved) as Map).cast<String, dynamic>();
    }
  }

  Future<void> enrollDevice(String code, {String? expectedUserId}) async {
    final transport = CloudSyncTransport(server);
    try {
      final data = await transport.request(
        'POST',
        '/sync/enroll-device',
        body: {
          'code': code.trim(),
          'deviceName': Platform.localHostname,
          'platform': Platform.operatingSystem,
          'deviceType': Platform.isAndroid || Platform.isIOS
              ? 'mobile'
              : 'desktop',
          'appVersion': flyAppVersion,
        },
      );
      if ((userId != null && userId != data['userId']) ||
          (expectedUserId != null && expectedUserId != data['userId'])) {
        final rejected = CloudSyncTransport(
          server,
          token: () async => data['accessToken'] as String,
        );
        try {
          await rejected.request('POST', '/auth/logout');
        } finally {
          rejected.close();
        }
        throw StateError('此目录已连接另一用户，不能混入其他用户的数据');
      }
      await _persist(data);
    } on SyncHttpException catch (error) {
      if (error.status == 401) {
        throw ArgumentError('设备接入码无效、已使用或已过期，请重新签发');
      }
      rethrow;
    } finally {
      transport.close();
    }
  }

  Future<void> _persist(Map<String, dynamic> data) async {
    await storage.write(key: storageKey, value: jsonEncode(data));
    session = data;
  }

  Future<Map<String, dynamic>> _verificationRequest(
    String path,
    Map<String, dynamic> body, {
    bool authorized = false,
  }) async {
    final transport = CloudSyncTransport(
      server,
      token: authorized ? accessToken : null,
      onUnauthorized: authorized ? refresh : null,
    );
    try {
      return await transport.request('POST', path, body: body);
    } on SyncHttpException catch (error) {
      final message = switch (error.status) {
        429 => '请求过于频繁，请稍后重试 / Too many attempts. Please try later.',
        503 => '邮件未能发送，请稍后重试 / Email could not be sent. Please retry later.',
        404 =>
          '服务器尚未启用邮箱注册 / Email registration is not enabled on this server.',
        400
            when (error.reason ?? '').contains(
              'Graphical verification is incorrect',
            ) =>
          '图形验证码错误 / Incorrect graphical code.',
        400 when (error.reason ?? '').contains('graphical verification') =>
          '请刷新图形验证码 / Refresh the graphical verification.',
        400 when (error.reason ?? '').contains('email code') =>
          '邮箱验证码错误、已使用或已过期 / Email code is incorrect, used or expired.',
        400 when (error.reason ?? '').contains('password is incorrect') =>
          '当前密码错误 / Incorrect current password.',
        400 =>
          '邮箱验证已过期，请重新验证 / Email verification expired. Please verify again.',
        401 => '登录已过期，请重新连接 / Session expired. Please reconnect.',
        409 => '此账号已绑定邮箱 / This account already has a verified email.',
        _ => '无法完成邮箱验证，请稍后重试 / Could not verify email. Please retry.',
      };
      throw EmailAuthException(message);
    } finally {
      transport.close();
    }
  }

  Future<EmailCaptcha> registrationCaptcha(
    String email, {
    bool bind = false,
    String? purpose,
  }) async {
    final data = await _verificationRequest('/auth/registration/captcha', {
      'email': email.trim().toLowerCase(),
      'purpose': purpose ?? (bind ? 'bind' : 'register'),
    }, authorized: bind || purpose == 'delete');
    final encoded = data['imageBase64'] as String;
    if (encoded.length > 200000) {
      throw const FormatException('Invalid verification image');
    }
    return EmailCaptcha(data['challengeId'] as String, base64Decode(encoded));
  }

  Future<int> sendRegistrationCode(String challengeId, String captcha) async {
    final data = await _verificationRequest('/auth/registration/send-code', {
      'challengeId': challengeId,
      'captcha': captcha.trim().toUpperCase(),
    });
    return (data['retryAfter'] as int).clamp(1, 3600);
  }

  Future<String> verifyRegistrationCode(String challengeId, String code) async {
    final data = await _verificationRequest('/auth/registration/verify-code', {
      'challengeId': challengeId,
      'code': code.trim(),
    });
    return data['verificationTicket'] as String;
  }

  Future<void> resetPassword({
    required String email,
    required String password,
    required String confirm,
    required String verificationTicket,
  }) async {
    if (password != confirm ||
        password.runes.length < 10 ||
        password.runes.length > 128) {
      throw const EmailAuthException(
        '请检查密码长度及两次输入是否一致 / Check password length and confirmation.',
      );
    }
    await _verificationRequest('/auth/password/reset', {
      'email': email.trim().toLowerCase(),
      'password': password,
      'confirmPassword': confirm,
      'verificationTicket': verificationTicket,
    });
    if (this.email == email.trim().toLowerCase()) await clearLocalSession();
  }

  Future<bool> deleteAccount({
    required String password,
    required String verificationTicket,
  }) async {
    if (userId == null || !emailVerified) {
      throw const EmailAuthException(
        '请先登录已验证的邮箱账号 / Sign in with a verified email first.',
      );
    }
    final result = await _verificationRequest('/account/delete', {
      'email': email,
      'password': password,
      'verificationTicket': verificationTicket,
      'confirmation': 'DELETE',
    }, authorized: true);
    await clearLocalSession();
    return result['fileCleanupPending'] == true;
  }

  Future<void> clearLocalSession() async {
    // A refresh started before deletion must not restore the removed session.
    try {
      await _refreshing;
    } catch (_) {
      // The server has already revoked this session.
    }
    session = null;
    await storage.delete(key: storageKey);
  }

  Future<void> _acceptSession(
    Map<String, dynamic> data,
    String? expectedUserId,
  ) async {
    if ((userId != null && userId != data['userId']) ||
        (expectedUserId != null && expectedUserId != data['userId'])) {
      final rejected = CloudSyncTransport(
        server,
        token: () async => data['accessToken'] as String,
      );
      try {
        await rejected.request('POST', '/auth/logout');
      } finally {
        rejected.close();
      }
      throw StateError(
        '此目录已连接另一用户，请使用独立数据目录 / This folder belongs to another cloud account.',
      );
    }
    await _persist(data);
  }

  Future<void> authenticate({
    required bool register,
    required String email,
    required String password,
    String? confirm,
    String? verificationTicket,
    String? expectedUserId,
    bool bindEmail = false,
  }) async {
    if (register && password != confirm) throw ArgumentError('两次密码不一致');
    if (password.runes.length < 10) throw ArgumentError('密码至少需要 10 个字符');
    if (register &&
        (verificationTicket == null || verificationTicket.isEmpty)) {
      throw const EmailAuthException('请先验证邮箱 / Verify your email first.');
    }
    if (register && password.runes.length > 128) {
      throw ArgumentError('密码最多 128 个字符');
    }
    final transport = CloudSyncTransport(
      server,
      token: bindEmail ? accessToken : null,
      onUnauthorized: bindEmail ? refresh : null,
    );
    try {
      final data = await transport.request(
        'POST',
        bindEmail
            ? '/auth/link-email'
            : register
            ? '/auth/register'
            : '/auth/login',
        body: {
          'email': email.trim().toLowerCase(),
          'password': password,
          if (register) 'confirmPassword': confirm,
          if (register) 'verificationTicket': verificationTicket,
          'deviceName': Platform.localHostname,
          'platform': Platform.operatingSystem,
          'deviceType': Platform.isAndroid || Platform.isIOS
              ? 'mobile'
              : 'desktop',
          'appVersion': flyAppVersion,
        },
      );
      await _acceptSession(data, expectedUserId);
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
      if (e.status == 400) {
        throw const EmailAuthException(
          '邮箱验证已过期，请重新验证 / Email verification expired.',
        );
      }
      if (e.status == 429) {
        throw const EmailAuthException(
          '尝试次数过多，请稍后重试 / Too many attempts. Please try later.',
        );
      }
      if (e.status == 404) {
        throw const EmailAuthException(
          '服务器尚未启用邮箱登录 / Email login is not enabled on this server.',
        );
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
    } on SyncHttpException catch (error) {
      if (error.status == 401) {
        session = null;
        await storage.delete(key: storageKey);
      }
      rethrow;
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
      await clearLocalSession();
    }
  }
}
