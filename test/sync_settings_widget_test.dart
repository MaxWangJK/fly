import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/account/presentation/my_settings_panel.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/domain/sync_protocol.dart';
import 'package:fly/features/sync/presentation/sync_controller.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/l10n/fly_localizations.dart';

void main() {
  for (final width in [1000.0, 390.0]) {
    testWidgets(
      'Me keeps email registration and optional device enrollment at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = AppDatabase(NativeDatabase.memory());
        final c = SyncController(SyncOutboxRepository(db), '')
          ..ready = true
          ..connectionMode = SyncConnectionMode.cloud;
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            syncControllerProvider.overrideWith((ref) => c),
          ],
        );
        Future<void> settle() async {
          for (var i = 0; i < 8; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 15)),
            );
            await tester.pump(const Duration(milliseconds: 60));
          }
        }

        try {
          await tester.runAsync(db.ensureBuiltInData);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                locale: const Locale('zh'),
                supportedLocales: FlyLocalizations.supportedLocales,
                localizationsDelegates: const [
                  FlyLocalizationsDelegate(),
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: const Scaffold(
                  body: SingleChildScrollView(
                    padding: EdgeInsets.all(20),
                    child: MySettingsPanel(),
                  ),
                ),
              ),
            ),
          );
          await settle();
          expect(find.byKey(const ValueKey('cloud-email')), findsOneWidget);
          expect(find.textContaining('world-workshop.cn'), findsNothing);
          final option = find.byKey(const ValueKey('cloud-device-code-option'));
          await tester.ensureVisible(option);
          await settle();
          await tester.tap(option);
          await settle();
          final input = find.byKey(const ValueKey('sync-device-code'));
          expect(input, findsOneWidget);
          await tester.ensureVisible(input);
          await tester.enterText(input, 'short');
          FocusManager.instance.primaryFocus?.unfocus();
          await settle();
          await tester.ensureVisible(find.text('连接'));
          await settle();
          await tester.tap(find.text('连接'));
          await settle();
          expect(c.error, '请填写后台签发的一次性设备接入码');
          expect(find.text('请填写后台签发的一次性设备接入码'), findsOneWidget);
          expect(c.auth.userId, isNull);
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
