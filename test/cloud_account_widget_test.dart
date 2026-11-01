import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/account/data/auth_service.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/domain/sync_protocol.dart';
import 'package:fly/features/sync/presentation/sync_controller.dart';
import 'package:fly/features/sync/presentation/sync_settings_panel.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/design_system/app_theme.dart';

class _Auth extends AuthService {
  _Auth(super.server, super.scope);
  int images = 0;
  @override
  Future<EmailCaptcha> registrationCaptcha(
    String email, {
    bool bind = false,
  }) async {
    images++;
    return EmailCaptcha(
      'isolated-challenge',
      await File('test/fixtures/auth_captcha.png').readAsBytes(),
    );
  }

  @override
  Future<int> sendRegistrationCode(String challengeId, String captcha) async =>
      60;
  @override
  Future<String> verifyRegistrationCode(String challengeId, String code) async {
    if (code != '123456') {
      throw const EmailAuthException('验证码错误 / Incorrect code');
    }
    return 'isolated-verification-ticket';
  }
}

class _Controller extends SyncController {
  _Controller(AppDatabase db) : super(SyncOutboxRepository(db), 'isolated') {
    ready = true;
    connectionMode = SyncConnectionMode.cloud;
    auth = _Auth(server, root);
  }
  Map<String, Object?>? registration;
  @override
  Future<void> login(
    bool register,
    String email,
    String password,
    String confirm, {
    String? verificationTicket,
    bool bindEmail = false,
  }) async {
    registration = {
      'register': register,
      'email': email,
      'ticket': verificationTicket,
      'bind': bindEmail,
    };
    auth.session = {
      'userId': auth.userId ?? 'isolated-user',
      'email': email,
      'emailVerified': true,
    };
    cloudEnabled = true;
    notifyListeners();
  }
}

void main() {
  for (final scenario in [
    (const Size(390, 844), true, false, 1.0),
    (const Size(1000, 900), false, false, 1.0),
    (const Size(360, 780), true, true, 1.3),
    (const Size(844, 390), true, false, 1.0),
  ]) {
    testWidgets(
      'cloud registration preserves errors and completes at ${scenario.$1}',
      (tester) async {
        final size = scenario.$1, zh = scenario.$2;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scenario.$4;
        debugDefaultTargetPlatformOverride =
            size.height < 500 || size.width < 600
            ? TargetPlatform.android
            : TargetPlatform.windows;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final db = AppDatabase(NativeDatabase.memory());
        final controller = _Controller(db);
        final container = ProviderContainer(
          overrides: [syncControllerProvider.overrideWith((ref) => controller)],
        );
        final boundary = GlobalKey();
        Future<void> settle() async {
          for (var i = 0; i < 8; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 15)),
            );
            await tester.pump(const Duration(milliseconds: 40));
          }
        }

        Finder key(String key) => find.byKey(ValueKey(key));
        Future<void> tap(String target) async {
          FocusManager.instance.primaryFocus?.unfocus();
          await settle();
          await tester.ensureVisible(key(target));
          await settle();
          await tester.tap(key(target));
          await settle();
        }

        Future<void> type(String target, String text) async {
          await tester.ensureVisible(key(target));
          await settle();
          await tester.enterText(key(target), text);
          await settle();
        }

        Future<void> capture(String name) async {
          await tester.runAsync(() async {
            final picture =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            try {
              final bytes = await picture.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('build/cloud-email-$name-${size.width.toInt()}.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              picture.dispose();
            }
          });
        }

        try {
          await tester.runAsync(() async {
            await db.ensureBuiltInData();
            for (final font in {
              'Ahem': 'C:/Windows/Fonts/msyh.ttc',
              'Microsoft YaHei UI': 'C:/Windows/Fonts/msyh.ttc',
              'MaterialIcons': 'D:/ProgramData/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            }.entries) {
              final file = File(font.value);
              if (await file.exists()) {
                await (FontLoader(font.key)..addFont(
                      Future.value(
                        ByteData.sublistView(await file.readAsBytes()),
                      ),
                    ))
                    .load();
              }
            }
          });
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: RepaintBoundary(
                key: boundary,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: Locale(zh ? 'zh' : 'en'),
                  supportedLocales: FlyLocalizations.supportedLocales,
                  localizationsDelegates: const [
                    FlyLocalizationsDelegate(),
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  theme: scenario.$3 ? FlyTheme.dark() : FlyTheme.light(),
                  home: const Scaffold(
                    body: SafeArea(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(20),
                        child: SyncSettingsPanel(accountOnly: true),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await settle();
          await capture('login');
          await tap('cloud-show-register');
          await type('cloud-email', 'not-an-email');
          await tap('cloud-load-captcha');
          expect((controller.auth as _Auth).images, 0);
          await type('cloud-email', 'alice@example.com');
          await tap('cloud-load-captcha');
          expect((controller.auth as _Auth).images, 1);
          await tester.ensureVisible(key('cloud-captcha'));
          await settle();
          await capture('captcha');
          await type('cloud-captcha', 'ABCD');
          await tap('cloud-send-code');
          expect(
            tester.widget<TextButton>(key('cloud-resend-code')).onPressed,
            isNull,
          );
          await type('cloud-email-code', '000000');
          await tap('cloud-verify-code');
          expect(key('cloud-email-code'), findsOneWidget);
          await type('cloud-email-code', '123456');
          await tap('cloud-verify-code');
          await type('cloud-password', 'isolated-test-password');
          await type('cloud-confirm-password', 'different-test-password');
          await tap('cloud-complete-register');
          expect(controller.registration, isNull);
          await type('cloud-confirm-password', 'isolated-test-password');
          await tester.ensureVisible(key('cloud-password'));
          await settle();
          await capture('password');
          await tap('cloud-complete-register');
          expect(
            controller.registration?['ticket'],
            'isolated-verification-ticket',
          );
          expect(controller.auth.emailVerified, isTrue);
          expect(controller.cloudFiles, isFalse);
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
          await settle();
          await tester.runAsync(db.close);
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
