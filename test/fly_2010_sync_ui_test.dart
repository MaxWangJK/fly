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
import 'package:fly/app/shell/primary_navigation_rail.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/account/data/local_profile.dart';
import 'package:fly/features/account/presentation/local_profile_avatar.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/presentation/sync_controller.dart';
import 'package:fly/features/sync/presentation/sync_settings_panel.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/design_system/app_theme.dart';

void main() {
  for (final scenario in [
    (const Size(1100, 900), false, 1.0),
    (const Size(390, 844), false, 1.0),
    (const Size(320, 850), true, 1.3),
  ]) {
    testWidgets('live avatar and Fly scanner guide at ${scenario.$1}', (
      tester,
    ) async {
      final desktop = scenario.$1.width > 600;
      debugDefaultTargetPlatformOverride = desktop
          ? TargetPlatform.windows
          : TargetPlatform.android;
      tester.view.physicalSize = scenario.$1;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scenario.$3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final db = AppDatabase(NativeDatabase.memory());
      final sync = SyncController(SyncOutboxRepository(db), '')..ready = true;
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncControllerProvider.overrideWith((ref) => sync),
        ],
      );
      final boundary = GlobalKey();
      Future<void> settle() async {
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await tester.pump(const Duration(milliseconds: 60));
        }
      }

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
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(disableAnimations: scenario.$2),
                  child: child!,
                ),
                home: Scaffold(
                  body: Row(
                    children: [
                      if (desktop)
                        SizedBox(
                          width: 64,
                          child: PrimaryNavigationRail(
                            selectedModule: PrimaryModule.tasks,
                            onSelected: (_) {},
                          ),
                        ),
                      Expanded(
                        child: Column(
                          children: [
                            if (!desktop)
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: LocalProfileAvatar(hideWhenEmpty: true),
                              ),
                            Expanded(
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 680,
                                  ),
                                  child: const SingleChildScrollView(
                                    padding: EdgeInsets.all(16),
                                    child: SyncSettingsPanel(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await settle();
        {
          final avatar = find.byKey(const ValueKey('primary-profile-avatar'));
          final sameElement = avatar.evaluate().firstOrNull;
          expect(
            find.byKey(const ValueKey('primary-profile-image')),
            findsNothing,
          );
          final bytes = (await tester.runAsync(_avatar))!;
          await tester.runAsync(
            () => LocalProfileRepository(db).save('Alex', bytes),
          );
          await settle();
          final image = tester.widget<Image>(
            find.byKey(const ValueKey('primary-profile-image')),
          );
          expect((image.image as MemoryImage).bytes, orderedEquals(bytes));
          if (desktop) {
            expect(identical(sameElement, avatar.evaluate().single), isTrue);
          }
          expect(find.byTooltip('Alex'), findsOneWidget);
        }
        expect(find.byKey(const ValueKey('lan-pairing-guide')), findsOneWidget);
        expect(find.text('我的 → 同步设置 → 本地同步'), findsOneWidget);
        expect(find.textContaining('系统相机或其他应用无法完成配对'), findsOneWidget);
        // The illustration animates once and honors reduced-motion settings.
        final line = find.byKey(const ValueKey('lan-guide-scan-line'));
        final before = tester.getTopLeft(line);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.getTopLeft(line) == before, scenario.$2);
        await tester.pump(const Duration(seconds: 4));
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.runAsync(() async {
          final picture =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final png = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('build/build46-sync-${scenario.$1.width.toInt()}.png')
                .writeAsBytes(png!.buffer.asUint8List());
          } finally {
            picture.dispose();
          }
        });
        if (!desktop) {
          final scanner = find.byKey(const ValueKey('scan-desktop-qr'));
          await tester.ensureVisible(scanner);
          await settle();
          expect(scanner.hitTestable(), findsOneWidget);
        }
        await tester.runAsync(
          () => LocalProfileRepository(db).save('Alex', null),
        );
        await settle();
        expect(
          find.byKey(const ValueKey('primary-profile-image')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await settle();
        await tester.runAsync(db.close);
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}

Future<Uint8List> _avatar() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFF28624A), BlendMode.src);
  canvas.drawCircle(const Offset(32, 22), 10, Paint()..color = Colors.white);
  canvas.drawCircle(const Offset(32, 58), 22, Paint()..color = Colors.white);
  final picture = recorder.endRecording();
  final image = await picture.toImage(64, 64);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
