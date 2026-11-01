import 'package:fly/features/tasks/presentation/task_providers.dart';

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
  _Auth(this.image) : super('https://sync.example.com/api', 'isolated');
  final Uint8List image;
  String? purpose;
  @override
  Future<EmailCaptcha> registrationCaptcha(
    String email, {
    bool bind = false,
    String? purpose,
  }) async {
    this.purpose = purpose;
    return EmailCaptcha('isolated-challenge', image);
  }

  @override
  Future<int> sendRegistrationCode(String challengeId, String captcha) async =>
      60;
  @override
  Future<String> verifyRegistrationCode(String challengeId, String code) async {
    if (code != '123456') {
      throw const EmailAuthException('验证码错误 / Incorrect code');
    }
    return 'isolated-proof';
  }
}

class _Controller extends SyncController {
  _Controller(AppDatabase db, Uint8List image)
    : super(SyncOutboxRepository(db), 'isolated') {
    ready = true;
    connectionMode = SyncConnectionMode.cloud;
    auth = _Auth(image);
  }
  int resets = 0, deletions = 0;
  void signInForDeletion() {
    auth.session = {
      'userId': 'owner',
      'email': 'owner@example.com',
      'emailVerified': true,
    };
    cloudEnabled = true;
    notifyListeners();
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String password,
    required String confirm,
    required String verificationTicket,
  }) async {
    resets++;
    error = null;
  }

  @override
  Future<void> deleteAccount({
    required String password,
    required String verificationTicket,
  }) async {
    if (password == 'wrong-password') {
      error = '当前密码错误 / Incorrect current password';
      return;
    }
    deletions++;
    error = null;
    cloudEnabled = false;
    auth.session = null;
    notifyListeners();
  }
}

void main() {
  for (final scenario in [
    (const Size(390, 844), true, false, 1.0),
    (const Size(1000, 900), false, false, 1.0),
    (const Size(360, 780), false, true, 1.3),
    (const Size(844, 390), true, false, 1.0),
  ]) {
    testWidgets(
      'recover and delete with confirmation, recoverable errors at ${scenario.$1}',
      (tester) async {
        final size = scenario.$1;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scenario.$4;
        debugDefaultTargetPlatformOverride = size.width > 900
            ? TargetPlatform.windows
            : TargetPlatform.android;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final image = await tester.runAsync(
          () => File('test/fixtures/auth_captcha.png').readAsBytes(),
        );
        final db = AppDatabase(NativeDatabase.memory());
        final controller = _Controller(db, image!);
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            syncControllerProvider.overrideWith((ref) => controller),
          ],
        );
        final boundary = GlobalKey();
        Finder key(String name) {
          final matches = find.byKey(ValueKey(name));
          return find.byType(Dialog).evaluate().isEmpty
              ? matches
              : find.descendant(of: find.byType(Dialog), matching: matches);
        }

        Future<void> settle() async {
          for (var i = 0; i < 4; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump(const Duration(milliseconds: 80));
          }
        }

        Future<void> tap(String name) async {
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.ensureVisible(key(name));
          await settle();
          await tester.tap(key(name));
          await settle();
        }

        Future<void> type(String name, String text) async {
          await tester.ensureVisible(key(name));
          await settle();
          await tester.enterText(key(name), text);
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
              await File(
                'build/cloud-lifecycle-$name-${size.width.toInt()}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              picture.dispose();
            }
          });
        }

        Future<void> verify() async {
          await tap('cloud-load-captcha');
          await type('cloud-captcha', 'ABCD');
          await tap('cloud-send-code');
          await type('cloud-email-code', '000000');
          await tap('cloud-verify-code');
          expect(key('cloud-email-code'), findsOneWidget);
          await type('cloud-email-code', '123456');
          await tap('cloud-verify-code');
        }

        try {
          await tester.runAsync(() async {
            await db.ensureBuiltInData();
            for (final entry in {
              'Ahem': 'C:/Windows/Fonts/msyh.ttc',
              'Microsoft YaHei UI': 'C:/Windows/Fonts/msyh.ttc',
              'MaterialIcons': 'D:/ProgramData/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            }.entries) {
              if (await File(entry.value).exists()) {
                await (FontLoader(entry.key)..addFont(
                      Future.value(
                        ByteData.sublistView(
                          await File(entry.value).readAsBytes(),
                        ),
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
                  locale: Locale(scenario.$2 ? 'zh' : 'en'),
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
          await tap('cloud-forgot-password');
          await tap('cloud-auth-back');
          expect(find.byType(Dialog), findsNothing);
          expect(controller.resets, 0);
          await tap('cloud-forgot-password');
          await type('cloud-email', 'owner@example.com');
          await capture('reset');
          await verify();
          expect((controller.auth as _Auth).purpose, 'reset');
          await type('cloud-password', 'new-test-password');
          await type('cloud-confirm-password', 'different-password');
          await tap('cloud-reset-password');
          expect(controller.resets, 0);
          await type('cloud-confirm-password', 'new-test-password');
          await tap('cloud-reset-password');
          expect(controller.resets, 1);
          expect(find.byType(Dialog), findsNothing);
          controller.signInForDeletion();
          await settle();
          await tap('cloud-manage-delete');
          await capture('delete');
          await verify();
          expect((controller.auth as _Auth).purpose, 'delete');
          expect(
            tester.widget<FilledButton>(key('cloud-delete-account')).onPressed,
            isNull,
          );
          expect(controller.deletions, 0);
          await type('cloud-password', 'wrong-password');
          await tap('cloud-confirm-delete');
          await tap('cloud-delete-account');
          expect(controller.deletions, 0);
          expect(key('cloud-password'), findsOneWidget);
          await type('cloud-password', 'current-password');
          await tap('cloud-delete-account');
          expect(controller.deletions, 1);
          expect(find.byType(Dialog), findsNothing);
          expect(controller.auth.userId, isNull);
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
