import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/features/account/data/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test('verified registration sends proof and confirmation, login accepts the same space', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <(String, Map<String, dynamic>)>[];
    final subscription = server.listen((request) async {
      final body = (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
          .cast<String, dynamic>();
      requests.add((request.uri.path, body));
      final result = switch (request.uri.path) {
        '/api/auth/registration/captcha' => {
          'challengeId': 'test-challenge',
          'imageBase64': base64Encode([1, 2, 3]),
        },
        '/api/auth/registration/send-code' => {'retryAfter': 60},
        '/api/auth/registration/verify-code' => {
          'verificationTicket': 'test-proof-from-server',
        },
        _ => {
          'userId': 'same-space',
          'deviceId': 'device',
          'email': 'owner@example.com',
          'emailVerified': true,
          'accessToken': 'test-access',
          'refreshToken': 'test-refresh',
        },
      };
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(result));
      await request.response.close();
    });
    try {
      final auth = AuthService(
        'http://127.0.0.1:${server.port}/api',
        'isolated',
      );
      final captcha = await auth.registrationCaptcha(' Owner@Example.com ');
      expect(await auth.sendRegistrationCode(captcha.id, 'abcd'), 60);
      final ticket = await auth.verifyRegistrationCode(captcha.id, '012345');
      await auth.authenticate(
        register: true,
        email: ' Owner@Example.com ',
        password: 'local-test-password',
        confirm: 'local-test-password',
        verificationTicket: ticket,
        expectedUserId: 'same-space',
      );
      expect(auth.emailVerified, isTrue);
      final registration = requests
          .where((r) => r.$1.endsWith('/register'))
          .single
          .$2;
      expect(registration['email'], 'owner@example.com');
      expect(registration['verificationTicket'], ticket);
      expect(registration['confirmPassword'], 'local-test-password');
      await auth.authenticate(
        register: false,
        email: 'owner@example.com',
        password: 'local-test-password',
        expectedUserId: 'same-space',
      );
      expect(requests.last.$2.containsKey('verificationTicket'), isFalse);
      final unicodePassword = List.filled(100, '🔐').join();
      await auth.authenticate(
        register: true,
        email: 'owner@example.com',
        password: unicodePassword,
        confirm: unicodePassword,
        verificationTicket: ticket,
        expectedUserId: 'same-space',
      );
      expect((requests.last.$2['password'] as String).runes.length, 100);
      expect(requests.any((r) => r.$1.contains('/files')), isFalse);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test('wrong account is revoked before persisting and registration cannot skip verification', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var loggedOut = false;
    final subscription = server.listen((request) async {
      await request.drain<void>();
      if (request.uri.path.endsWith('/logout')) loggedOut = true;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'userId': 'different-user',
          'deviceId': 'new-device',
          'email': 'other@example.com',
          'emailVerified': true,
          'accessToken': 'new-token',
          'refreshToken': 'refresh',
        }),
      );
      await request.response.close();
    });
    try {
      final auth = AuthService(
        'http://127.0.0.1:${server.port}/api',
        'isolated',
      );
      auth.session = {
        'userId': 'original-user',
        'accessToken': 'original-token',
      };
      await expectLater(
        auth.authenticate(
          register: true,
          email: 'test@example.com',
          password: 'test-password-long',
          confirm: 'test-password-long',
        ),
        throwsA(isA<EmailAuthException>()),
      );
      await expectLater(
        auth.authenticate(
          register: false,
          email: 'test@example.com',
          password: 'test-password-long',
          expectedUserId: 'original-user',
        ),
        throwsStateError,
      );
      expect(loggedOut, isTrue);
      expect(auth.userId, 'original-user');
      expect(await auth.accessToken(), 'original-token');
      expect(await auth.storage.read(key: auth.storageKey), isNull);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
