import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/account/data/auth_service.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/presentation/sync_controller.dart';
import 'package:fly/features/sync/services/sync_workspace_binding.dart';
import 'package:uuid/uuid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late HttpServer server;
  late String endpoint;
  final requests = <(String, Map<String, dynamic>, String?)>[];
  var failDelete = false, rejectRefresh = false;
  const session = {
    'userId': 'original-user',
    'email': 'owner@example.com',
    'emailVerified': true,
    'deviceId': 'original-device',
    'accessToken': 'isolated-token',
    'refreshToken': 'isolated-refresh',
  };

  setUp(() async {
    requests.clear();
    failDelete = rejectRefresh = false;
    FlutterSecureStorage.setMockInitialValues({});
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    endpoint = 'http://127.0.0.1:${server.port}/api';
    server.listen((request) async {
      final text = await utf8.decoder.bind(request).join();
      final body = text.isEmpty
          ? <String, dynamic>{}
          : (jsonDecode(text) as Map).cast<String, dynamic>();
      requests.add((
        request.uri.path,
        body,
        request.headers.value('authorization'),
      ));
      Object result = {'ok': true, 'fileCleanupPending': true};
      if (request.uri.path.endsWith('/captcha')) {
        result = {
          'challengeId': 'isolated-challenge',
          'imageBase64': base64Encode([1, 2, 3]),
        };
      } else if (request.uri.path.endsWith('/delete') && failDelete) {
        request.response.statusCode = 400;
        result = {'detail': 'Account password is incorrect'};
      } else if (request.uri.path.endsWith('/refresh') && rejectRefresh) {
        request.response.statusCode = 401;
        result = {'detail': 'Invalid refresh token'};
      } else if (request.uri.path.endsWith('/login')) {
        result = {
          ...session,
          if (body['email'] != 'owner@example.com') 'userId': 'different-user',
        };
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(result));
      await request.response.close();
    });
  });
  tearDown(() async => server.close(force: true));

  Future<AuthService> signedIn(String scope) async {
    final auth = AuthService(endpoint, scope);
    auth.session = Map<String, dynamic>.from(session);
    await auth.storage.write(key: auth.storageKey, value: jsonEncode(session));
    return auth;
  }

  test(
    'recovery uses its own proof and clears only the recovered account session',
    () async {
      final auth = await signedIn('isolated-recovery');
      await auth.registrationCaptcha(' Owner@Example.com ', purpose: 'reset');
      expect(requests.last.$2['purpose'], 'reset');
      expect(requests.last.$3, isNull);
      await auth.resetPassword(
        email: 'other@example.com',
        password: 'new-test-password',
        confirm: 'new-test-password',
        verificationTicket: 'isolated-proof',
      );
      expect(auth.userId, 'original-user');
      await auth.resetPassword(
        email: ' Owner@Example.com ',
        password: 'new-test-password',
        confirm: 'new-test-password',
        verificationTicket: 'isolated-proof',
      );
      expect(requests.last.$1, '/api/auth/password/reset');
      expect(requests.last.$2['confirmPassword'], 'new-test-password');
      expect(auth.userId, isNull);
      final restored = AuthService(endpoint, auth.scope);
      await restored.restore();
      expect(restored.userId, isNull);
      expect(requests.any((r) => r.$1.endsWith('/login')), isFalse);
    },
  );

  test('delete requires authenticated proof, keeps session on wrong password, then removes secure credentials', () async {
    final auth = await signedIn('isolated-delete');
    await auth.registrationCaptcha('owner@example.com', purpose: 'delete');
    expect(requests.last.$3, 'Bearer isolated-token');
    failDelete = true;
    await expectLater(
      auth.deleteAccount(
        password: 'wrong-password',
        verificationTicket: 'proof',
      ),
      throwsA(
        isA<EmailAuthException>().having(
          (e) => e.message,
          'message',
          contains('Incorrect current password'),
        ),
      ),
    );
    expect(auth.userId, 'original-user');
    expect(await auth.storage.read(key: auth.storageKey), isNotNull);
    failDelete = false;
    expect(
      await auth.deleteAccount(
        password: 'current-test-password',
        verificationTicket: 'proof',
      ),
      isTrue,
    );
    expect(requests.last.$2, {
      'email': 'owner@example.com',
      'password': 'current-test-password',
      'verificationTicket': 'proof',
      'confirmation': 'DELETE',
    });
    expect(auth.userId, isNull);
    expect(await auth.storage.read(key: auth.storageKey), isNull);
  });

  test(
    'a remotely revoked refresh session is removed from secure storage',
    () async {
      final auth = await signedIn('isolated-remote-revoke');
      rejectRefresh = true;
      await expectLater(auth.refresh(), throwsA(isA<Exception>()));
      expect(auth.userId, isNull);
      expect(await auth.storage.read(key: auth.storageKey), isNull);
    },
  );

  for (final delete in [false, true]) {
    test(
      '${delete ? 'deletion' : 'password reset'} disconnects cloud while preserving local customers, files, outbox and account binding',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final root = await Directory.systemTemp.createTemp('fly-lifecycle-');
        final queue = SyncOutboxRepository(db);
        final controller = SyncController(queue, root.path);
        try {
          await db.ensureBuiltInData();
          final customer = await DriftCustomerRepository(db)
              .createCustomer(name: 'Local ${const Uuid().v4()}');
          final localFile = File('${root.path}/retained.txt');
          await localFile.writeAsString('local content');
          controller.server = endpoint;
          controller.auth = await signedIn(root.path);
          controller.cloudEnabled = true;
          await queue.saveState('cloudEnabled', 'true');
          final binding = 'cloud:$endpoint:original-user';
          await SyncWorkspaceBinding(queue).activate(binding);
          final pendingBefore = await queue.prepare();
          if (delete) {
            await controller.deleteAccount(
              password: 'current-test-password',
              verificationTicket: 'proof',
            );
          } else {
            await controller.resetPassword(
              email: 'owner@example.com',
              password: 'new-test-password',
              confirm: 'new-test-password',
              verificationTicket: 'proof',
            );
          }
          expect(controller.error, isNull);
          expect(controller.auth.userId, isNull);
          expect(controller.cloudEnabled, isFalse);
          expect(await queue.state('cloudEnabled'), 'false');
          expect(await queue.state('binding:cloud'), binding);
          expect(await queue.prepare(), pendingBefore);
          expect(
            (await (db.select(
              db.customers,
            )..where((r) => r.id.equals(customer.id))).getSingle()).name,
            customer.name,
          );
          expect(await localFile.readAsString(), 'local content');
          if (delete) {
            await controller.login(
              false,
              'different@example.com',
              'new-test-password',
              '',
            );
            expect(controller.error, contains('another cloud account'));
            expect(await queue.state('binding:cloud'), binding);
          }
        } finally {
          controller.dispose();
          await db.close();
          await root.delete(recursive: true);
        }
      },
    );
  }
}
