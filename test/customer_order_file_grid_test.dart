import 'dart:io';
import 'dart:ui' as drawing;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/app/app.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/core/storage/data_root_providers.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/files/data/thumbnail_cache.dart';
import 'package:fly/features/files/presentation/file_entry_content.dart';
import 'package:fly/features/files/presentation/file_grid_visuals.dart';
import 'package:fly/features/files/presentation/image_file_viewer.dart';
import 'package:fly/features/orders/domain/order_lifecycle.dart';
import 'package:fly/features/orders/presentation/order_detail_panel.dart';
import 'package:fly/features/orders/presentation/order_providers.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/shared/attachments/attachment_providers.dart';
import 'package:fly/shared/attachments/attachment_storage.dart';
import 'package:fly/shared/data/workspace_folder_repository.dart';
import 'package:fly/shared/design_system/fly_color_scheme.dart';

import 'input_continuity_widget_test.dart' as ui;

class _Opener extends PlatformAttachmentOpener {
  final paths = <String>[];
  @override
  Future<void> open(String path) async => paths.add(path);
}

void _expectThumbnailFrames(WidgetTester tester) {
  Size? expected;
  for (final id in ['door', 'panels', 'invoice', 'missing']) {
    final frame = find.byKey(ValueKey('file-grid-visual-$id'));
    expect(frame, findsOneWidget);
    expected ??= tester.getSize(frame);
    expect(tester.getSize(frame), expected);
    final container = tester.widget<Container>(
      find.descendant(of: frame, matching: find.byType(Container)).first,
    );
    final decoration = container.decoration! as BoxDecoration;
    final colors = FlyColorScheme.of(tester.element(frame));
    expect(decoration.color, colors.surfaceMuted);
    expect(decoration.color, isNot(colors.surface));
    expect(decoration.border, isNotNull);
    expect(
      find.descendant(
        of: find.byKey(ValueKey('file-item-$id')),
        matching: find.byIcon(Icons.open_in_new),
      ),
      findsNothing,
    );
    if (id == 'door' || id == 'panels') {
      final image = tester.widget<Image>(
        find.descendant(of: frame, matching: find.byType(Image)),
      );
      expect(image.fit, BoxFit.contain);
    }
  }
}

Future<void> _photo(File file, {required bool portrait}) async {
  final size = portrait ? const Size(300, 480) : const Size(480, 300);
  final recorder = drawing.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFFECE7DD), BlendMode.src);
  final rect = Rect.fromLTWH(30, 25, size.width - 60, size.height - 50);
  canvas.drawRect(rect, Paint()..color = const Color(0xFF7D9F89));
  for (var x = 45.0; x < size.width - 30; x += 30) {
    canvas.drawLine(
      Offset(x, 35),
      Offset(x, size.height - 35),
      Paint()
        ..color = const Color(0xFF355D53)
        ..strokeWidth = 5,
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  try {
    final bytes = await image.toByteData(format: drawing.ImageByteFormat.png);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  for (final phone in [false, true]) {
    testWidgets('customer detail creates order through PI dialog phone=$phone', (
      tester,
    ) async {
      ui.viewport(tester, phone);
      if (!phone) tester.view.physicalSize = const Size(1400, 950);
      final db = AppDatabase(NativeDatabase.memory());
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fly-order-dialog-'),
      ))!;
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dataRootPathProvider.overrideWithValue(root.path),
        ],
      );
      final capture = GlobalKey();
      try {
        final customer = (await tester.runAsync(() async {
          await db.ensureBuiltInData();
          await ui.fonts();
          return DriftCustomerRepository(db).createCustomer(name: '海岸照明');
        }))!;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(key: capture, child: const FlyApp()),
          ),
        );
        await ui.settle(tester);
        container.read(appRouterProvider).go('/customers/all');
        await ui.settle(tester);
        if (phone) {
          await tester.tap(
            find.byKey(ValueKey('phone-customer-${customer.id}')),
          );
          await ui.settle(tester);
        }
        final button = find.byKey(const ValueKey('create-order-for-customer'));
        await ui.reveal(tester, button);
        await tester.tap(button);
        await ui.settle(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(
                  ValueKey('create-order-status-${OrderLifecycle.pending}'),
                ),
              )
              .selected,
          isTrue,
        );
        await tester.tap(find.text('取消').last);
        await ui.settle(tester);
        expect(
          (await tester.runAsync(() => db.select(db.orders).get()))!,
          isEmpty,
        );
        // Cancel stays on the customer; submitting a valid PI opens its order.
        await tester.tap(button);
        await ui.settle(tester);
        await tester.tap(find.byKey(const ValueKey('create-order-submit')));
        await ui.settle(tester);
        expect(find.text('请填写PI发票号'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('create-order-number')),
          'PI-COAST-0015',
        );
        await tester.tap(
          find.byKey(const ValueKey('create-order-status-order-production')),
        );
        await ui.settle(tester);
        await ui.capture(
          tester,
          capture,
          phone ? 'detail-order-phone' : 'detail-order-desktop',
        );
        container.read(orderSearchProvider.notifier).state = 'previous search';
        await tester.tap(find.byKey(const ValueKey('create-order-submit')));
        await ui.settle(tester);
        final order = (await tester.runAsync(
          () => db.select(db.orders).getSingle(),
        ))!;
        expect(order.customerId, customer.id);
        expect(order.orderNumber, 'PI-COAST-0015');
        expect(order.statusId, 'order-production');
        expect(container.read(selectedOrderIdProvider), order.id);
        expect(container.read(orderCustomerFilterProvider), customer.id);
        expect(container.read(orderSearchProvider), isEmpty);
        expect(find.byType(OrderDetailPanel), findsOneWidget);
        if (phone) {
          expect(
            find.byKey(const ValueKey('customer-detail-sheet')),
            findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await ui.settle(tester);
        await tester.runAsync(() async {
          await db.close();
          await root.delete(recursive: true);
        });
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
      'compact folders and usable image/document tiles preserve file actions dark=$dark',
      (tester) async {
        ui.viewport(tester, false);
        tester.view.physicalSize = const Size(1264, 800);
        tester.platformDispatcher.textScaleFactorTestValue = dark ? 1.3 : 1;
        final db = AppDatabase(NativeDatabase.memory());
        final root = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('fly-file-grid-'),
        ))!;
        final opener = _Opener();
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dataRootPathProvider.overrideWithValue(root.path),
            attachmentOpenerProvider.overrideWithValue(opener),
          ],
        );
        final capture = GlobalKey();
        try {
          final folder = (await tester.runAsync(() async {
            await db.ensureBuiltInData();
            await ui.fonts();
            final folders = WorkspaceFolderRepository(
              db,
              WorkspaceFolderKind.files,
            );
            final first = await folders.create('产品01图集');
            await folders.create('产品02图集');
            await folders.create('门与墙板安装资料');
            final repo = ManagedFileRepository(db);
            for (final record in [
              ('door', '木门.png'),
              ('panels', '产品展示.png'),
              ('invoice', 'PI-COAST-0015.pdf'),
              ('missing', '待下载的图片.jpg'),
            ]) {
              final path = 'files/${record.$2}';
              if (record.$1 == 'door' || record.$1 == 'panels') {
                await _photo(
                  File('${root.path}/$path'),
                  portrait: record.$1 == 'door',
                );
              }
              await repo.commit(
                ImportedFile(
                  id: record.$1,
                  relativePath: path,
                  name: record.$2,
                  size: 2048,
                  sha256: record.$1,
                ),
              );
            }
            for (final id in ['door', 'panels']) {
              expect(
                await ThumbnailCache(ManagedFileStorage(root.path))
                    .get((await repo.find(id))!),
                isNotNull,
              );
            }
            return first;
          }))!;
          if (dark) {
            // Theme is supplied by the existing app preference controller.
            container.read(themeModeProvider.notifier).state = ThemeMode.dark;
          }
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: RepaintBoundary(key: capture, child: const FlyApp()),
            ),
          );
          await ui.settle(tester);
          container.read(appRouterProvider).go('/files');
          await ui.settle(tester);
          await tester.tap(find.text('我的文件').first);
          await ui.settle(tester);
          final folderTile = find.byKey(
            ValueKey('desktop-file-folder-$folder'),
          );
          expect(
            tester.getSize(folderTile).height,
            lessThanOrEqualTo(dark ? 114 : 100),
          );
          expect(tester.getSize(folderTile).width, lessThanOrEqualTo(112));
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('desktop-files-blank')),
              matching: find.byType(FileFolderVisual),
            ),
            findsNWidgets(3),
          );
          final photoArea = find.byKey(const ValueKey('file-grid-visual-door'));
          expect(tester.getSize(photoArea).width, greaterThan(85));
          expect(tester.getSize(photoArea).height, greaterThan(85));
          expect(find.byType(FileDocumentVisual), findsOneWidget);
          _expectThumbnailFrames(tester);
          expect(tester.takeException(), isNull);
          await ui.capture(
            tester,
            capture,
            dark ? 'file-grid-dark' : 'file-grid-light',
          );
          // PDF keeps direct system opening; image opens Fly's full image viewer.
          await tester.tap(find.byTooltip('PI-COAST-0015.pdf'));
          await ui.settle(tester);
          expect(opener.paths.single, endsWith('PI-COAST-0015.pdf'));
          await tester.tap(find.text('木门.png'));
          await ui.settle(tester);
          expect(find.byType(ImageFileViewer), findsOneWidget);
          await tester.tap(find.byTooltip('关闭').last);
          await ui.settle(tester);
          // Context actions and batch selection remain available on compact tiles.
          await tester.tapAt(
            tester.getCenter(find.byKey(const ValueKey('file-item-door'))),
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton,
          );
          await ui.settle(tester);
          expect(find.text('移动'), findsWidgets);
          await tester.tapAt(const Offset(1200, 650));
          await ui.settle(tester);
          await tester.tap(find.byTooltip('多选'));
          await ui.settle(tester);
          await tester.tap(find.byKey(const ValueKey('file-item-door')));
          await tester.tap(find.byKey(const ValueKey('file-item-panels')));
          await ui.settle(tester);
          expect(find.text('已选 2 项'), findsOneWidget);
          expect(
            tester
                .widget<Checkbox>(find.byKey(const ValueKey('file-check-door')))
                .value,
            isTrue,
          );
          expect(
            tester
                .widget<TextButton>(
                  find.byKey(const ValueKey('files-batch-move')),
                )
                .onPressed,
            isNotNull,
          );
          await tester.tap(find.text('取消').last);
          await ui.settle(tester);
          for (final name in ['中图标', '列表']) {
            await tester.tap(find.byKey(const ValueKey('files-settings')));
            await ui.settle(tester);
            await tester.tap(
              find.widgetWithText(CheckedPopupMenuItem<FileViewMode>, name),
            );
            await ui.settle(tester);
            expect(find.text('木门.png'), findsOneWidget);
            if (name == '中图标') {
              expect(tester.getSize(photoArea).height, greaterThan(140));
              _expectThumbnailFrames(tester);
            } else {
              expect(
                find.byKey(ValueKey('desktop-folder-list-$folder')),
                findsOneWidget,
              );
            }
            expect(tester.takeException(), isNull);
          }
          if (!dark) {
            await tester.tap(find.byKey(const ValueKey('files-settings')));
            await ui.settle(tester);
            await tester.tap(
              find.byKey(const ValueKey('files-settings-view-small')),
            );
            await ui.settle(tester);
            tester.view.physicalSize = const Size(430, 932);
            debugDefaultTargetPlatformOverride = TargetPlatform.android;
            await ui.settle(tester);
            // Search the folder-first phone home to display all test files.
            await tester.enterText(find.byType(TextField).first, '.');
            await ui.settle(tester);
            _expectThumbnailFrames(tester);
            await ui.capture(tester, capture, 'file-grid-phone');
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
          await ui.settle(tester);
          await tester.runAsync(() async {
            await db.close();
            await root.delete(recursive: true);
          });
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
