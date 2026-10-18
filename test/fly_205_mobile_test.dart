import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/app/app.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/core/storage/data_root_providers.dart';
import 'package:fly/features/calendar/presentation/mobile_calendar_workspace.dart';
import 'package:fly/features/files/data/file_browser_preferences.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/files/presentation/file_providers.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/domain/sync_protocol.dart';
import 'package:fly/features/sync/presentation/sync_controller.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/shared/design_system/mobile_workspace_actions.dart';
import 'package:fly/shared/data/workspace_folder_repository.dart';

Map<String, dynamic> remote(
  String table,
  String id,
  Map<String, Object?> data,
) => {
  'entityType': table,
  'recordId': SyncOutboxRepository.identity(table, jsonEncode([id])),
  'version': 1,
  'deletedAt': null,
  'data': {'id': id, ...data},
};

void main() {
  test(
    'customer folder visibility is device-only and does not delete data',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await db.ensureBuiltInData();
        final outbox = SyncOutboxRepository(db);
        final before = await outbox.pendingCount();
        await FileBrowserPreferencesStore(db, phone: true).save(
          const FileBrowserPreferences(
            view: 'small',
            showCustomerFolder: false,
          ),
        );
        expect(
          (await FileBrowserPreferencesStore(
            db,
            phone: true,
          ).load()).showCustomerFolder,
          isFalse,
        );
        expect(
          (await FileBrowserPreferencesStore(
            db,
            phone: false,
          ).load()).showCustomerFolder,
          isTrue,
        );
        expect(await outbox.pendingCount(), before);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'startup retains saved cloud data but only reconnects desktop pairing',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final controller = SyncController(SyncOutboxRepository(db), '');
      try {
        await db.ensureBuiltInData();
        await controller.outbox.saveState('syncConnectionMode', 'cloud');
        await controller.outbox.saveState('cloudEnabled', 'true');
        await controller.outbox.saveState(
          'workspace',
          'cloud:retained-workspace',
        );
        await controller.outbox.saveState(
          'server',
          'https://retained.example/api',
        );
        await controller.initialize();
        expect(controller.connectionMode, SyncConnectionMode.lan);
        expect(controller.engine, isNull);
        expect(controller.cloudEnabled, isFalse);
        expect(await controller.outbox.state('cloudEnabled'), 'false');
        expect(
          await controller.outbox.state('workspace'),
          'cloud:retained-workspace',
        );
        expect(
          await controller.outbox.state('server'),
          'https://retained.example/api',
        );
      } finally {
        controller.dispose();
        await db.close();
      }
    },
  );

  for (final scenario in [
    (const Size(390, 844), const FakeViewPadding(top: 48, bottom: 24)),
    (const Size(844, 390), const FakeViewPadding(left: 44, bottom: 18)),
    (const Size(360, 780), const FakeViewPadding(top: 60, bottom: 24)),
  ]) {
    final size = scenario.$1, insets = scenario.$2;
    testWidgets('folder-first phone, synced lists and safe areas at $size', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = size.width == 360
          ? 1.3
          : 1;
      tester.view.padding = insets;
      tester.view.viewPadding = insets;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final db = AppDatabase(NativeDatabase.memory());
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fly-205-'),
      ))!;
      final sync = SyncController(SyncOutboxRepository(db), root.path)
        ..ready = true;
      final boundary = GlobalKey();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dataRootPathProvider.overrideWithValue(root.path),
          syncControllerProvider.overrideWith((ref) => sync),
        ],
      );
      Future<void> settle() async {
        for (var i = 0; i < 12; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> capture(String name) async {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('build/fly205-$name-${size.width.toInt()}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }

      Future<void> apply(List<Map<String, dynamic>> changes) async {
        await tester.runAsync(
          () => sync.outbox.applyPage({
            'changes': changes,
            'nextCursor': 1,
          }, 'lanCursor'),
        );
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
        final timestamp = DateTime(2026, 10, 17).millisecondsSinceEpoch ~/ 1000;
        await apply([
          for (final name in ['欢迎', '事务推进', '生活随记'])
            remote('task_lists', 'list-$name', {
              'name': name,
              'parent_id': null,
              'color_value': 0xff4d6bd8,
              'sort_order': 1,
              'created_at': timestamp,
              'updated_at': timestamp,
              'version': 1,
            }),
          for (final name in ['light', 'door', 'panel'])
            remote('file_folders', name, {
              'name': name,
              'parent_id': null,
              'sort_order': 1,
              'created_at': timestamp,
              'updated_at': timestamp,
            }),
        ]);
        await tester.runAsync(() async {
          final path = File('${root.path}/files/test.pdf');
          await path.parent.create(recursive: true);
          await path.writeAsBytes([37, 80, 68, 70]);
          await ManagedFileRepository(db).commit(
            const ImportedFile(
              id: 'phone-pdf',
              relativePath: 'files/test.pdf',
              name: 'lamp.pdf',
              size: 4,
              sha256: 'test',
            ),
            folderId: 'light',
          );
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(key: boundary, child: const FlyApp()),
          ),
        );
        await settle();
        final button = find.byKey(const ValueKey('mobile-sync-button'));
        expect(tester.getTopLeft(button).dy, greaterThanOrEqualTo(insets.top));
        container.read(appRouterProvider).go('/tasks/all');
        await settle();
        for (final name in ['欢迎', '事务推进', '生活随记']) {
          expect(
            find.byKey(ValueKey('mobile-list-list-$name')),
            findsOneWidget,
          );
        }
        final add = find.byKey(const ValueKey('task-add-button'));
        final search = find.byKey(const ValueKey('task-search-button'));
        expect(tester.getSize(add), tester.getSize(search));
        expect(tester.getSize(add), const Size(56, 56));
        final actionsRect = tester.getRect(find.byType(MobileWorkspaceActions));
        expect(
          actionsRect.bottom - tester.getRect(add).bottom,
          size.width < size.height ? 36 : 16,
        );
        await capture('lists');
        await apply([
          remote('task_lists', 'later-list', {
            'name': '电脑新增清单',
            'parent_id': 'list-事务推进',
            'color_value': 0xff4d6bd8,
            'sort_order': 2,
            'created_at': timestamp,
            'updated_at': timestamp,
            'version': 1,
          }),
        ]);
        await settle();
        expect(
          find.byKey(const ValueKey('mobile-list-later-list')),
          findsOneWidget,
        );
        container.read(appRouterProvider).go('/files');
        await settle();
        for (final id in ['customers', 'light', 'door', 'panel']) {
          expect(
            find.byKey(ValueKey('mobile-file-folder-$id')),
            findsOneWidget,
          );
        }
        expect(find.byKey(const ValueKey('file-search-input')), findsOneWidget);
        expect(find.byKey(const ValueKey('file-search-button')), findsNothing);
        expect(find.text('我的文件'), findsNothing);
        expect(find.textContaining('标签筛选'), findsNothing);
        expect(find.text('lamp.pdf'), findsNothing);
        await capture('folders');
        await tester.tap(
          find.byKey(const ValueKey('mobile-file-folder-customers')),
        );
        await settle();
        expect(find.byKey(const ValueKey('file-add-button')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('file-add-button')));
        await settle();
        expect(find.byKey(const ValueKey('file-take-photo')), findsOneWidget);
        await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
        await settle();
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          'Customer documents',
        );
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(FilledButton),
          ),
        );
        await settle();
        expect(find.text('Customer documents'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('mobile-files-back')));
        await settle();
        expect(find.text('Customer documents'), findsOneWidget);
        expect(find.text('客户文件'), findsOneWidget);
        const picker = MethodChannel('plugins.flutter.io/file_selector');
        var pickerCalled = false;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (
          call,
        ) async {
          pickerCalled = true;
          return call.method == 'openFile'
              ? ['${root.path}/files/test.pdf']
              : null;
        });
        try {
          await tester.tap(find.byKey(const ValueKey('file-add-button')));
          await settle();
          await tester.tap(find.byIcon(Icons.file_upload_outlined));
          await settle();
          expect(pickerCalled, isTrue);
          for (
            var i = 0;
            i < 40 &&
                find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
            i++
          ) {
            await settle();
          }
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(
            find.text('test.pdf'),
            findsOneWidget,
            reason: find
                .byType(Text)
                .evaluate()
                .map((e) => (e.widget as Text).data)
                .whereType<String>()
                .join(' | '),
          );
          final uploaded = (await tester.runAsync(
            () => ManagedFileRepository(db).watchAll().first,
          ))!.singleWhere((file) => file.originalName == 'test.pdf');
          expect(
            uploaded.folderId,
            WorkspaceFolderRepository.customerFilesRootId,
          );
          expect(
            await tester.runAsync(
              () => File(
                ManagedFileStorage(root.path).absolute(uploaded.relativePath),
              ).exists(),
            ),
            isTrue,
          );
        } finally {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            picker,
            null,
          );
        }
        await capture('customer-files');
        await tester.tap(find.byKey(const ValueKey('mobile-files-back')));
        await settle();
        expect(
          find.byKey(const ValueKey('mobile-file-folder-fly-customer-files')),
          findsNothing,
        );
        await tester.longPress(
          find.byKey(const ValueKey('mobile-file-folder-customers')),
        );
        await settle();
        await tester.tap(
          find.byKey(const ValueKey('mobile-hide-customer-folder')),
        );
        await settle();
        expect(
          find.byKey(const ValueKey('mobile-file-folder-customers')),
          findsNothing,
        );
        expect(
          await tester
              .runAsync(
                () => FileBrowserPreferencesStore(db, phone: true).load(),
              )
              .then((v) => v!.showCustomerFolder),
          isFalse,
        );
        expect(
          (await tester.runAsync(
            () => ManagedFileRepository(db).find('phone-pdf'),
          )),
          isNotNull,
        );
        await tester.tap(
          find.byKey(const ValueKey('mobile-file-folder-light')),
        );
        await settle();
        expect(find.text('lamp.pdf'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('mobile-files-title')),
          findsOneWidget,
        );
        await capture('inside-folder');
        await tester.tap(find.byKey(const ValueKey('mobile-files-back')));
        await settle();
        await tester.tap(find.byKey(const ValueKey('file-more-menu')));
        await settle();
        final customerOption = find.widgetWithText(
          CheckedPopupMenuItem<String>,
          '显示客户文件',
        );
        await tester.ensureVisible(customerOption);
        await settle();
        await capture('menu');
        await tester.tap(customerOption);
        await settle();
        expect(
          find.byKey(const ValueKey('mobile-file-folder-customers')),
          findsOneWidget,
        );
        await apply([
          remote('file_folders', 'desktop-added', {
            'name': '电脑新增文件夹',
            'parent_id': null,
            'sort_order': 3,
            'created_at': timestamp,
            'updated_at': timestamp,
          }),
        ]);
        await settle();
        expect(
          find.byKey(const ValueKey('mobile-file-folder-desktop-added')),
          findsOneWidget,
        );
        await tester.runAsync(
          () => container.read(fileFolderRepositoryProvider).remove('door'),
        );
        await settle();
        await tester.tap(find.byKey(const ValueKey('file-more-menu')));
        await settle();
        final trashOption = find.widgetWithText(PopupMenuItem<String>, '最近删除');
        await tester.ensureVisible(trashOption);
        await settle();
        await tester.tap(trashOption);
        await settle();
        final restore = find.byKey(
          const ValueKey('mobile-restore-folder-door'),
        );
        expect(restore, findsOneWidget);
        await tester.tap(
          find.descendant(of: restore, matching: find.byType(IconButton)),
        );
        await settle();
        expect(restore, findsNothing);
        await tester.tap(find.byKey(const ValueKey('mobile-files-back')));
        await settle();
        expect(
          find.byKey(const ValueKey('mobile-file-folder-door')),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const ValueKey('file-search-input')),
          'lamp',
        );
        await settle();
        expect(find.text('lamp.pdf'), findsOneWidget);
        container.read(appRouterProvider).go('/calendar');
        await settle();
        expect(
          tester
              .widget<PopupMenuButton<MobileCalendarView>>(
                find.byKey(const ValueKey('mobile-calendar-view')),
              )
              .initialValue,
          MobileCalendarView.week,
        );
        await capture('week');
        await tester.tap(find.byKey(const ValueKey('mobile-sync-button')));
        await settle();
        expect(find.byKey(const ValueKey('scan-desktop-qr')), findsOneWidget);
        expect(find.byKey(const ValueKey('sync-mode-cloud')), findsNothing);
        expect(find.byKey(const ValueKey('sync-mode-lan')), findsNothing);
        expect(find.text('云同步'), findsNothing);
        await capture('sync-settings');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await settle();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await db.close();
        });
        await tester.runAsync(() => root.delete(recursive: true));
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
