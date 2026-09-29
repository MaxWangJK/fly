import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:fly/app/app.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/shared/dev/first_run_demo_seeder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void>? _snapshotFontLoad;

void main() {
  testWidgets('captures the V6 customer detail workspace', (tester) async {
    final boundaryKey = GlobalKey();
    final database = await _pumpSeededApp(tester, boundaryKey);
    addTearDown(database.close);

    await tester.tap(find.byKey(const ValueKey('primary-customers')));
    await _pumpUi(tester);
    await tester.tap(find.text('Jack Lim'));
    await _pumpUi(tester);

    expect(find.text('Consignee: Manila Home Depot'), findsOneWidget);
    await _captureIfRequested(
      tester,
      boundaryKey,
      'docs/screenshots/polish_v6/customer_detail.png',
    );
    await _disposeUi(tester);
  });

  testWidgets('captures the V6 order and financial workspaces', (tester) async {
    final boundaryKey = GlobalKey();
    final database = await _pumpSeededApp(tester, boundaryKey);
    addTearDown(database.close);

    await tester.tap(find.byKey(const ValueKey('primary-orders')));
    await _pumpUi(tester);
    final orderNumber = 'SO-${DateTime.now().year}-001';
    await tester.tap(find.text(orderNumber));
    await _pumpUi(tester);
    expect(find.text(orderNumber), findsWidgets);
    await _captureIfRequested(
      tester,
      boundaryKey,
      'docs/screenshots/polish_v6/order_detail.png',
    );

    await tester.tap(find.byKey(const ValueKey('order-financial-preview')));
    await _pumpUi(tester);
    expect(find.byKey(const ValueKey('quick-financial-定金')), findsOneWidget);
    await _captureIfRequested(
      tester,
      boundaryKey,
      'docs/screenshots/polish_v6/order_financial.png',
    );
    await _disposeUi(tester);
  });
}

Future<AppDatabase> _pumpSeededApp(
  WidgetTester tester,
  GlobalKey boundaryKey,
) async {
  const capture = bool.fromEnvironment('FLY_UPDATE_SCREENSHOTS');
  if (capture) {
    await tester.runAsync(() async {
      _snapshotFontLoad ??= _loadSnapshotFonts();
      await _snapshotFontLoad;
    });
  }
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 820);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final database = AppDatabase(NativeDatabase.memory());
  await tester.runAsync(() async {
    await database.ensureBuiltInData();
    await FirstRunDemoSeeder(
      database: database,
      tasks: DriftTaskRepository(database),
      customers: DriftCustomerRepository(database),
      orders: DriftOrderRepository(database),
    ).seedIfEligible();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: RepaintBoundary(key: boundaryKey, child: const FlyApp()),
    ),
  );
  await _pumpUi(tester);
  return database;
}

Future<void> _loadSnapshotFonts() async {
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

Future<void> _captureIfRequested(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String path,
) async {
  const enabled = bool.fromEnvironment('FLY_UPDATE_SCREENSHOTS');
  if (!enabled) return;
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) throw StateError('Unable to encode $path');
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  });
}

Future<void> _pumpUi(WidgetTester tester) async {
  for (var index = 0; index < 16; index++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _disposeUi(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(Duration.zero);
}
