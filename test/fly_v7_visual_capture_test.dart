import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:fly/app/app.dart';
import 'package:fly/app/settings/navigation_settings.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/shared/dev/first_run_demo_seeder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('captures V7 dashboard and command palette', (tester) async {
    const capture = bool.fromEnvironment('FLY_UPDATE_SCREENSHOTS');
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
      final navigation = NavigationSettingsController(database);
      await navigation.ready;
      await navigation.update(const NavigationSettings(dashboardVisible: true));
      navigation.dispose();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: RepaintBoundary(key: boundaryKey, child: const FlyApp()),
      ),
    );
    await _pumpUi(tester);

    await tester.tap(find.byKey(const ValueKey('primary-dashboard')));
    await _pumpUi(tester);
    expect(find.text('本月利润'), findsOneWidget);
    await tester.runAsync(
      () => _capture(
        boundaryKey,
        'docs/screenshots/v7/dashboard.png',
        enabled: capture,
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('global-search-input')),
      'Jack',
    );
    await tester.pump(const Duration(milliseconds: 260));
    await _pumpUi(tester);
    expect(find.text('Jack Lim'), findsWidgets);
    await tester.runAsync(
      () => _capture(
        boundaryKey,
        'docs/screenshots/v7/global_search.png',
        enabled: capture,
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(Duration.zero);
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

Future<void> _capture(
  GlobalKey boundaryKey,
  String path, {
  required bool enabled,
}) async {
  if (!enabled) return;
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('Unable to encode $path');
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
}

Future<void> _pumpUi(WidgetTester tester) async {
  for (var index = 0; index < 16; index++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}
