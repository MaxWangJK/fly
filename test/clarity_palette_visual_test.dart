import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fly/app/app.dart';
import 'package:fly/app/settings/navigation_settings.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/notes/data/note_repository.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/shared/design_system/design_tokens.dart';
import 'package:fly/shared/design_system/fly_color_scheme.dart';
import 'package:fly/shared/dev/first_run_demo_seeder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('palette renders dashboard, files and notes', (tester) async {
    const capture = bool.fromEnvironment('FLY_CAPTURE_CLARITY');
    const dark = bool.fromEnvironment('FLY_VISUAL_DARK');
    const paletteName = String.fromEnvironment(
      'FLY_VISUAL_PALETTE',
      defaultValue: 'clarity',
    );
    final captureFolder = dark ? '$paletteName-dark' : paletteName;
    if (capture) await tester.runAsync(_loadFonts);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 820);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final boundaryKey = GlobalKey();
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.runAsync(() async {
      await database.ensureBuiltInData();
      await FirstRunDemoSeeder(
        database: database,
        tasks: DriftTaskRepository(database),
        customers: DriftCustomerRepository(database),
        orders: DriftOrderRepository(database),
      ).seedIfEligible();
      await NoteRepository(database).create('客户开发方法');
      final now = DateTime.now();
      await database
          .into(database.attachments)
          .insert(
            AttachmentsCompanion.insert(
              id: 'clarity-preview-file',
              ownerType: 'library',
              ownerId: 'clarity-preview-file',
              fileName: 'WPC-price-list.pdf',
              originalName: 'WPC-price-list.pdf',
              displayName: const Value('WPC-price-list.pdf'),
              relativePath: 'preview/WPC-price-list.pdf',
              mimeType: const Value('application/pdf'),
              fileSize: 38240,
              createdAt: now,
              updatedAt: now,
            ),
          );
      final navigation = NavigationSettingsController(database);
      await navigation.ready;
      await navigation.update(const NavigationSettings(dashboardVisible: true));
      navigation.dispose();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          flyPaletteProvider.overrideWith(
            (ref) => FlyPaletteIdX.parse(paletteName),
          ),
          themeModeProvider.overrideWith(
            (ref) => dark ? ThemeMode.dark : ThemeMode.light,
          ),
        ],
        child: RepaintBoundary(key: boundaryKey, child: const FlyApp()),
      ),
    );
    await _pumpUi(tester);
    final avatar = find.byKey(const ValueKey('primary-profile-avatar'));
    final search = find.byKey(const ValueKey('primary-global-search'));
    expect(
      tester.getTopLeft(search).dy - tester.getBottomLeft(avatar).dy,
      greaterThanOrEqualTo(FlySpacing.sm),
    );

    await tester.tap(find.byKey(const ValueKey('primary-dashboard')));
    await _pumpUi(tester);
    expect(find.text('本月利润'), findsOneWidget);
    await tester.runAsync(
      () => _capture(
        boundaryKey,
        'artifacts/$captureFolder/dashboard.png',
        capture,
      ),
    );
    tester.view.physicalSize = const Size(660, 760);
    await _pumpUi(tester);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1400, 820);
    await _pumpUi(tester);

    await tester.tap(find.byKey(const ValueKey('primary-tasks')));
    await _pumpUi(tester);
    expect(find.byKey(const ValueKey('task-search')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('quick-add-input')), '报价');
    await _pumpUi(tester);
    expect(find.text('更新 WPC 报价单'), findsOneWidget);
    await tester.runAsync(
      () => _capture(
        boundaryKey,
        'artifacts/$captureFolder/tasks-search.png',
        capture,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('primary-files')));
    await _pumpUi(tester);
    expect(find.text('WPC-price-list.pdf'), findsWidgets);
    await tester.runAsync(
      () =>
          _capture(boundaryKey, 'artifacts/$captureFolder/files.png', capture),
    );

    await tester.tap(find.byKey(const ValueKey('primary-notes')));
    await _pumpUi(tester);
    await tester.tap(find.text('我的笔记').first);
    await _pumpUi(tester);
    expect(find.text('客户开发方法'), findsOneWidget);
    await tester.tap(find.text('客户开发方法'));
    await _pumpUi(tester);
    expect(find.text('客户开发方法'), findsWidgets);
    expect(find.byKey(const ValueKey('note-continuous-body')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('note-continuous-body')),
      '# 客户开发\n\n- [ ] 跟进报价\n\n记录客户需求与下一步。',
    );
    await _pumpUi(tester);
    expect(find.textContaining('跟进报价'), findsOneWidget);
    await tester.runAsync(
      () =>
          _capture(boundaryKey, 'artifacts/$captureFolder/notes.png', capture),
    );
    await tester.tap(find.byKey(const ValueKey('primary-settings')));
    await _pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('settings-category-1')));
    await _pumpUi(tester);
    expect(find.byKey(const ValueKey('palette-mintCloud')), findsOneWidget);
    expect(find.byKey(const ValueKey('palette-sageMist')), findsOneWidget);
    expect(find.byKey(const ValueKey('palette-graphite')), findsNothing);
    await tester.runAsync(
      () => _capture(
        boundaryKey,
        'artifacts/$captureFolder/settings.png',
        capture,
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(Duration.zero);
  });
}

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final bytes = await File(path).readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  await load('Microsoft YaHei UI', r'C:\Windows\Fonts\msyh.ttc');
  await load(
    'MaterialIcons',
    r'D:\ProgramData\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
  );
}

Future<void> _capture(GlobalKey key, String path, bool enabled) async {
  if (!enabled) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) throw StateError('Unable to encode $path');
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
}

Future<void> _pumpUi(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}
