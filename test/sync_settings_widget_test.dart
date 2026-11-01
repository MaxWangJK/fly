import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/presentation/sync_controller.dart';
import 'package:fly/features/sync/presentation/sync_settings_panel.dart';
import 'package:fly/l10n/fly_localizations.dart';

void main() {
  for (final width in [1000.0, 390.0]) {
    testWidgets(
      'cloud email settings retain optional device enrollment at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = AppDatabase(NativeDatabase.memory());
        await tester.runAsync(() async {
          for (final font in {
            'FlyPreview': 'C:/Windows/Fonts/msyh.ttc',
            'MaterialIcons': 'D:/ProgramData/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          }.entries) {
            final file = File(font.value);
            if (await file.exists()) {
              final loader = FontLoader(font.key)
                ..addFont(
                  Future.value(ByteData.sublistView(await file.readAsBytes())),
                );
              await loader.load();
            }
          }
        });
        await tester.runAsync(db.ensureBuiltInData);
        final c = SyncController(SyncOutboxRepository(db), '')..ready = true;
        final boundary = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [syncControllerProvider.overrideWith((ref) => c)],
            child: MaterialApp(
              locale: const Locale('zh'),
              supportedLocales: FlyLocalizations.supportedLocales,
              localizationsDelegates: const [
                FlyLocalizationsDelegate(),
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xff81a58f),
                ),
                brightness: Brightness.light,
                fontFamily: 'FlyPreview',
              ),
              home: RepaintBoundary(
                key: boundary,
                child: const Scaffold(
                  body: SafeArea(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(24),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: 740,
                          child: SyncSettingsPanel(accountOnly: true),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('云同步'), findsOneWidget);
        expect(find.byKey(const ValueKey('cloud-email')), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('cloud-device-code-option')),
        );
        await tester.tap(
          find.byKey(const ValueKey('cloud-device-code-option')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('sync-device-code')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/sync-settings-${width.toInt()}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.enterText(
          find.byKey(const ValueKey('sync-device-code')),
          'short',
        );
        await tester.ensureVisible(find.text('连接云同步'));
        await tester.tap(find.text('连接云同步'));
        await tester.pump();
        expect(find.text('请填写后台签发的一次性设备接入码'), findsWidgets);
        expect(c.auth.userId, isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(db.close);
      },
    );
  }
}
