import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/account/data/local_profile.dart';
import 'package:fly/features/account/presentation/my_settings_panel.dart';
import 'package:fly/features/customers/domain/customer.dart';
import 'package:fly/features/customers/presentation/customer_create_dialog.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/domain/sync_protocol.dart';
import 'package:fly/features/sync/presentation/sync_controller.dart';
import 'package:fly/features/sync/presentation/sync_settings_panel.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/design_system/app_theme.dart';

class _Sync extends SyncController {
  _Sync(AppDatabase db) : super(SyncOutboxRepository(db), 'isolated-build44') {
    ready = true;
  }
  @override
  Future<void> selectConnectionMode(SyncConnectionMode value) async {
    connectionMode = value;
    cloudEnabled = false;
    notifyListeners();
  }

  @override
  Future<void> setCloud(bool value) async {
    cloudEnabled = value;
    notifyListeners();
  }

  @override
  Future<void> refreshDetails() async {}
  void signIn() {
    auth.session = {
      'userId': 'synthetic',
      'email': 'demo@example.com',
      'emailVerified': true,
    };
    notifyListeners();
  }
}

void main() {
  for (final scenario in [
    (const Size(390, 844), false, 1.0),
    (const Size(1100, 900), false, 1.0),
    (const Size(360, 780), true, 1.3),
  ]) {
    testWidgets(
      'customer required capture and simple profile/sync at ${scenario.$1}',
      (tester) async {
        tester.view.physicalSize = scenario.$1;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scenario.$3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        FlutterSecureStorage.setMockInitialValues({});
        final db = AppDatabase(NativeDatabase.memory());
        final sync = _Sync(db);
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            syncControllerProvider.overrideWith((ref) => sync),
          ],
        );
        final boundary = GlobalKey();
        Future<void> settle() async {
          for (var i = 0; i < 6; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 15)),
            );
            await tester.pump(const Duration(milliseconds: 60));
          }
        }

        Finder key(String name) => find.byKey(ValueKey(name));
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

        Future<void> pump(Widget child) async {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: RepaintBoundary(
                key: boundary,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: const Locale('zh'),
                  supportedLocales: FlyLocalizations.supportedLocales,
                  localizationsDelegates: const [
                    FlyLocalizationsDelegate(),
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  theme: scenario.$2 ? FlyTheme.dark() : FlyTheme.light(),
                  home: Scaffold(
                    body: SafeArea(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await settle();
        }

        Future<void> capture(String name) async => tester.runAsync(() async {
          final picture =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('build/build44-$name-${scenario.$1.width.toInt()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            picture.dispose();
          }
        });
        try {
          await tester.runAsync(() async {
            await db.ensureBuiltInData();
            for (final item in {
              'Ahem': 'C:/Windows/Fonts/msyh.ttc',
              'Microsoft YaHei UI': 'C:/Windows/Fonts/msyh.ttc',
              'MaterialIcons': 'D:/ProgramData/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            }.entries) {
              if (await File(item.value).exists()) {
                await (FontLoader(item.key)..addFont(
                      Future.value(
                        ByteData.sublistView(
                          await File(item.value).readAsBytes(),
                        ),
                      ),
                    ))
                    .load();
              }
            }
          });
          Customer? created;
          await pump(
            Builder(
              builder: (context) => IconButton(
                key: const ValueKey('open-customer'),
                icon: const Icon(Icons.add),
                onPressed: () async => created = await showDialog<Customer>(
                  context: context,
                  builder: (_) => const CustomerCreateDialog(),
                ),
              ),
            ),
          );
          await tap('open-customer');
          await capture('customer-form');
          await tap('phone-create-customer');
          expect(created, isNull);
          expect(find.text('请填写客户姓名'), findsOneWidget);
          await type('customer-quick-add-input', 'Build44 customer');
          await type('customer-create-country', 'Portugal');
          await tap('customer-create-category-category-a');
          await tap('customer-create-status-customer-intent');
          await type('customer-create-source', 'Partner webinar');
          await capture('customer-capture');
          await tap('phone-create-customer');
          expect(created?.country, 'Portugal');
          expect(created?.statusId, 'customer-intent');
          expect(created?.sourceId, isNotNull);
          await pump(const MySettingsPanel());
          expect(
            tester.widget<TextField>(key('my-sync-server')).controller!.text,
            isEmpty,
          );
          expect(find.textContaining('world-workshop.cn'), findsNothing);
          await type('my-display-name', 'Sam');
          await tap('my-save-profile');
          final saved = await tester.runAsync(
            () => LocalProfileRepository(db).watch().first,
          );
          expect(saved!.name, 'Sam');
          await type('my-sync-server', 'https://sync.example.test/api');
          await tap('my-save-server');
          expect(sync.server, 'https://sync.example.test/api');
          await tap('my-reset-server');
          expect(sync.server, SyncServerConfig.defaultBaseUrl);
          expect(
            tester.widget<TextField>(key('my-sync-server')).controller!.text,
            isEmpty,
          );
          await tester.ensureVisible(find.text('个人资料'));
          await tester.pump(const Duration(seconds: 5));
          await settle();
          await capture('my');
          var openMy = 0;
          await pump(SyncSettingsPanel(onOpenMy: () => openMy++));
          await tester.tap(find.text('云同步'));
          await settle();
          expect(find.byType(AlertDialog), findsOneWidget);
          await tester.tap(find.text('取消'));
          await settle();
          expect(sync.connectionMode, SyncConnectionMode.lan);
          await tester.tap(find.text('云同步'));
          await settle();
          await tap('confirm-sync-mode-switch');
          expect(sync.connectionMode, SyncConnectionMode.cloud);
          await tap('enable-cloud-sync');
          expect(openMy, 1);
          sync.signIn();
          await settle();
          await tap('enable-cloud-sync');
          expect(sync.cloudEnabled, isTrue);
          expect(find.text('demo@example.com'), findsNothing);
          expect(find.textContaining('world-workshop.cn'), findsNothing);
          await capture('sync');
          await tester.tap(find.text('本地同步'));
          await settle();
          await tap('confirm-sync-mode-switch');
          expect(sync.connectionMode, SyncConnectionMode.lan);
          expect(sync.cloudEnabled, isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
          await settle();
          await tester.runAsync(db.close);
        }
      },
    );
  }
}
