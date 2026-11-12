import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/app/app.dart';
import 'package:fly/app/settings/settings_center.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/core/storage/data_root_providers.dart';
import 'package:fly/features/files/data/file_browser_preferences.dart';
import 'package:fly/features/files/data/file_browser_query.dart';
import 'package:fly/features/files/presentation/file_providers.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';

import 'input_continuity_widget_test.dart' as ui;

void main() {
  testWidgets(
    'desktop sidebar lists only live root folders and follows edits',
    (tester) async {
      ui.viewport(tester, false);
      tester.view.physicalSize = const Size(1264, 850);
      final db = AppDatabase(NativeDatabase.memory());
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fly-folder-shortcuts-'),
      ))!;
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dataRootPathProvider.overrideWithValue(root.path),
        ],
      );
      final repo = container.read(fileFolderRepositoryProvider);
      final capture = GlobalKey();
      try {
        late String first, second, door, child;
        await tester.runAsync(() async {
          await db.ensureBuiltInData();
          await ui.fonts();
          first = await repo.create('产品01图集');
          second = await repo.create('产品02图集');
          door = await repo.create('门');
          child = await repo.create('铁门', parentId: door);
          await FileBrowserPreferencesStore(db, phone: false).save(
            const FileBrowserPreferences(
              view: 'small',
              collection: FileCollection.folder,
            ),
          );
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(key: capture, child: const FlyApp()),
          ),
        );
        await ui.settle(tester);
        expect(
          find.byKey(const ValueKey('primary-global-search')),
          findsNothing,
        );
        final avatar = find.byKey(const ValueKey('primary-profile-avatar'));
        final customer = find.byKey(const ValueKey('primary-customers'));
        expect(
          tester.getTopLeft(customer).dy - tester.getBottomLeft(avatar).dy,
          lessThanOrEqualTo(44),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await ui.settle(tester);
        expect(
          find.byKey(const ValueKey('global-search-input')),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await ui.settle(tester);
        container.read(appRouterProvider).go('/files');
        await ui.settle(tester);
        final sidebar = find.byKey(const ValueKey('desktop-files-sidebar'));
        Finder shortcut(String id) =>
            find.byKey(ValueKey('file-folder-shortcut-$id'));
        for (final id in [first, second, door]) {
          expect(shortcut(id).hitTestable(), findsOneWidget);
        }
        expect(shortcut(child), findsNothing);
        await ui.capture(tester, capture, 'root-folder-shortcuts');
        await tester.tap(shortcut(door));
        await ui.settle(tester);
        expect(tester.widget<ListTile>(shortcut(door)).selected, isTrue);
        expect(
          find.byKey(ValueKey('desktop-file-folder-$child')),
          findsOneWidget,
        );
        expect(shortcut(child), findsNothing);

        final add = find.descendant(
          of: sidebar,
          matching: find.byTooltip('新建文件夹'),
        );
        await tester.tap(add);
        await ui.settle(tester);
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          '新产品',
        );
        await tester.tap(find.widgetWithText(FilledButton, '确认'));
        await ui.settle(tester);
        final created = (await tester.runAsync(repo.all))!
            .singleWhere((f) => f.name == '新产品');
        expect(created.parentId, isNull);
        expect(shortcut(created.id), findsOneWidget);

        await tester.runAsync(() => repo.rename(first, '更新图集'));
        await ui.settle(tester);
        expect(
          find.descendant(of: sidebar, matching: find.text('更新图集')),
          findsOneWidget,
        );
        await tester.runAsync(() => repo.move(second, door));
        await ui.settle(tester);
        expect(shortcut(second), findsNothing);
        await tester.runAsync(() => repo.remove(first));
        await ui.settle(tester);
        expect(shortcut(first), findsNothing);
        expect(shortcut(door), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await ui.settle(tester);
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

  for (final (platform, tablet) in [
    (TargetPlatform.windows, false),
    (TargetPlatform.android, false),
    (TargetPlatform.iOS, false),
    (TargetPlatform.android, true),
    (TargetPlatform.iOS, true),
  ]) {
    testWidgets(
      'import/export settings are desktop only on $platform tablet=$tablet',
      (tester) async {
        final mobile = platform != TargetPlatform.windows;
        ui.viewport(tester, mobile);
        if (tablet) tester.view.physicalSize = const Size(1200, 1000);
        debugDefaultTargetPlatformOverride = platform;
        final db = AppDatabase(NativeDatabase.memory());
        await tester.runAsync(db.ensureBuiltInData);
        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [databaseProvider.overrideWithValue(db)],
              child: ui.app(
                const SettingsCenter(initialCategory: '导入与导出'),
                phone: mobile,
              ),
            ),
          );
          await ui.settle(tester);
          expect(find.text('导出 Excel'), mobile ? findsNothing : findsOneWidget);
          expect(find.text('导入客户'), mobile ? findsNothing : findsOneWidget);
          if (mobile) {
            expect(
              find.byKey(const ValueKey('settings-category-7')),
              findsNothing,
            );
            expect(
              find.byKey(const ValueKey('settings-category-0')),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await ui.settle(tester);
          await tester.runAsync(db.close);
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
