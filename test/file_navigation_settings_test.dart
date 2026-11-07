import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/app/app.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/core/storage/data_root_providers.dart';
import 'package:fly/features/files/data/file_browser_preferences.dart';
import 'package:fly/features/files/data/file_browser_query.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/files/presentation/file_grid_visuals.dart';
import 'package:fly/features/files/presentation/file_name_label.dart';
import 'package:fly/features/files/presentation/file_path_bar.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/shared/data/workspace_folder_repository.dart';

import 'input_continuity_widget_test.dart' as ui;

void main() {
  testWidgets(
    'deep paths keep Home and the current folder reachable on small screens',
    (tester) async {
      ui.viewport(tester, true);
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final path = [
        for (var i = 0; i < 8; i++)
          WorkspaceFolder(id: '$i', name: '第${i + 1}层产品资料', sortOrder: i),
      ];
      var home = false;
      for (final width in [430.0, 320.0]) {
        tester.view.physicalSize = Size(width, 600);
        await tester.pumpWidget(
          ui.app(
            FilePathBar(
              path: path,
              onHome: () => home = true,
              onFolder: (_) {},
            ),
          ),
        );
        await ui.settle(tester);
        expect(
          find.byKey(const ValueKey('file-path-folder-7')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('file-path-home')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byKey(const ValueKey('file-path-home')));
      expect(home, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
  for (final width in [100.0, 180.0, 320.0]) {
    testWidgets('filename retains both ends and extension at $width', (
      tester,
    ) async {
      await tester.runAsync(ui.fonts);
      const name = '产品照片👨‍👩‍👧‍👦-客户确认的铁门安装效果与包装方案20261107-final.PDF';
      for (final scale in [1.0, 1.5]) {
        await tester.pumpWidget(
          ui.app(
            Center(
              child: SizedBox(
                width: width,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: const FileNameLabel(
                    name: name,
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ),
          ),
        );
        final text = tester.widget<Text>(
          find.descendant(
            of: find.byType(FileNameLabel),
            matching: find.byType(Text),
          ),
        );
        expect(text.data, startsWith('产'));
        if (width >= 180) expect(text.data, startsWith('产品'));
        expect(text.data, endsWith('l.PDF'));
        expect(text.data, contains('....'));
        expect(find.byTooltip(name), findsOneWidget);
        expect(text.data, isNot(contains('\uFFFD')));
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('short names remain complete and resizing recalculates text', (
    tester,
  ) async {
    for (final width in [400.0, 90.0, 400.0]) {
      await tester.pumpWidget(
        ui.app(
          Center(
            child: SizedBox(
              width: width,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FileNameLabel(name: '门.png'),
                  FileNameLabel(name: 'English-contract-final-20261107.xlsx'),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('门.png'), findsOneWidget);
      final texts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(FileNameLabel),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data!)
          .toList();
      expect(texts.last, endsWith('.xlsx'));
      expect(texts.last.contains('....'), width == 90);
      expect(tester.takeException(), isNull);
    }
  });

  for (final phone in [false, true]) {
    testWidgets(
      'path navigation, Settings and folder moves preserve descendants phone=$phone',
      (tester) async {
        ui.viewport(tester, phone);
        if (!phone) tester.view.physicalSize = const Size(1264, 850);
        final db = AppDatabase(NativeDatabase.memory());
        final root = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('fly-file-path-'),
        ))!;
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dataRootPathProvider.overrideWithValue(root.path),
          ],
        );
        final capture = GlobalKey();
        final folders = WorkspaceFolderRepository(
          db,
          WorkspaceFolderKind.files,
        );
        late String door, wood, steel, nested, archive;
        const name = '客户木门安装与包装确认照片-20261107-final.pdf';
        try {
          await tester.runAsync(() async {
            await db.ensureBuiltInData();
            await ui.fonts();
            door = await folders.create('门');
            wood = await folders.create('木门', parentId: door);
            steel = await folders.create('铁门', parentId: door);
            nested = await folders.create('安装资料', parentId: wood);
            archive = await folders.create('归档');
            await ManagedFileRepository(db).commit(
              const ImportedFile(
                id: 'manual',
                name: name,
                relativePath: 'files/manual.pdf',
                size: 8,
                sha256: 'same-content',
              ),
              folderId: wood,
            );
            final file = File('${root.path}/files/manual.pdf');
            await file.parent.create(recursive: true);
            await file.writeAsString('PDF-test');
            await FileBrowserPreferencesStore(db, phone: phone).save(
              const FileBrowserPreferences(
                view: 'small',
                collection: FileCollection.folder,
                includeChildren: true,
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
          container.read(appRouterProvider).go('/files');
          await ui.settle(tester);
          Finder folder(String id) => find.byKey(
            ValueKey(
              phone ? 'mobile-file-folder-$id' : 'desktop-file-folder-$id',
            ),
          );
          Finder target(String id) =>
              find.byKey(ValueKey('file-move-folder-$id'));
          final settings = find.byKey(
            ValueKey(phone ? 'file-more-menu' : 'files-settings'),
          );
          Future<void> menu(String id) async {
            if (phone) {
              await tester.longPress(folder(id));
            } else {
              await tester.tapAt(
                tester.getCenter(folder(id)),
                kind: PointerDeviceKind.mouse,
                buttons: kSecondaryMouseButton,
              );
            }
            await ui.settle(tester);
            await tester.tap(find.byKey(const ValueKey('folder-context-move')));
            await ui.settle(tester);
            expect(find.text('移动文件夹'), findsOneWidget);
          }

          expect(find.text('包含子文件夹'), findsNothing);
          expect(find.byKey(const ValueKey('file-item-manual')), findsNothing);
          if (!phone) {
            final toolbar = find.byKey(const ValueKey('desktop-files-toolbar'));
            expect(
              find.descendant(of: toolbar, matching: find.text('我的文件')),
              findsNothing,
            );
            expect(
              find.descendant(of: toolbar, matching: find.text('标签筛选')),
              findsNothing,
            );
            final right = tester.getRect(settings).right;
            expect(right, closeTo(tester.getRect(toolbar).right, 1));
            expect(
              tester.getRect(find.byKey(const ValueKey('files-import'))).right,
              lessThanOrEqualTo(tester.getRect(settings).left),
            );
          }
          final searchField = find.byKey(const ValueKey('file-search-input'));
          await tester.enterText(searchField, '包装');
          await ui.settle(tester);
          expect(
            find.byKey(const ValueKey('file-item-manual')),
            findsOneWidget,
          );
          if (phone) {
            await tester.tap(find.byKey(const ValueKey('files-search-clear')));
          } else {
            await tester.tap(find.byKey(const ValueKey('file-path-home')));
          }
          await ui.settle(tester);
          expect(
            tester.widget<TextField>(searchField).controller!.text,
            isEmpty,
          );
          expect(find.byKey(const ValueKey('file-item-manual')), findsNothing);
          await tester.tap(folder(door));
          await ui.settle(tester);
          await tester.tap(folder(wood));
          await ui.settle(tester);
          final path = find.byKey(const ValueKey('file-path-bar'));
          expect(
            find.descendant(of: path, matching: find.text('门')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: path, matching: find.text('木门')),
            findsOneWidget,
          );
          expect(
            tester.getTopLeft(path).dy,
            greaterThanOrEqualTo(
              tester
                  .getBottomLeft(
                    find.byKey(const ValueKey('file-search-input')),
                  )
                  .dy,
            ),
          );
          final label = find.descendant(
            of: find.byKey(const ValueKey('file-item-manual')),
            matching: find.byType(FileNameLabel),
          );
          expect(
            tester
                .widget<Text>(
                  find.descendant(of: label, matching: find.byType(Text)),
                )
                .data,
            endsWith('l.pdf'),
          );
          if (!phone) {
            await tester.tapAt(
              tester.getCenter(find.byKey(const ValueKey('file-item-manual'))),
              kind: PointerDeviceKind.mouse,
              buttons: kSecondaryMouseButton,
            );
            await ui.settle(tester);
            expect(find.text('任务详情'), findsNothing);
            await tester.tap(find.text('文件详情'));
            await ui.settle(tester);
            expect(
              find.byKey(const ValueKey('file-details-dialog')),
              findsOneWidget,
            );
            await tester.tap(find.text('关闭').last);
            await ui.settle(tester);
          }
          await ui.capture(
            tester,
            capture,
            phone ? 'file-path-phone' : 'file-path-desktop',
          );
          await tester.tap(find.byKey(ValueKey('file-path-folder-$door')));
          await ui.settle(tester);
          await tester.tap(settings);
          await ui.settle(tester);
          final list = find.byKey(const ValueKey('files-settings-view-list'));
          if (phone) {
            await tester.tap(
              find.widgetWithText(CheckedPopupMenuItem<String>, '列表'),
            );
          } else {
            await tester.tap(list);
          }
          await ui.settle(tester);
          expect(
            find.descendant(
              of: folder(wood),
              matching: find.byWidgetPredicate(
                (w) => w is FileFolderVisual && w.compact && w.seed == wood,
              ),
            ),
            findsOneWidget,
          );
          await ui.capture(
            tester,
            capture,
            phone ? 'file-list-phone' : 'file-list-desktop',
          );
          await tester.tap(settings);
          await ui.settle(tester);
          final sortByName = phone
              ? find.widgetWithText(CheckedPopupMenuItem<String>, '名称')
              : find.byKey(const ValueKey('files-settings-sort-name'));
          await tester.ensureVisible(sortByName);
          await tester.tap(sortByName);
          await ui.settle(tester);
          await menu(wood);
          expect(target(door), findsOneWidget);
          await tester.tap(target(door));
          await ui.settle(tester);
          expect(target(wood), findsNothing);
          expect(target(nested), findsNothing);
          expect(target(steel), findsOneWidget);
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const ValueKey('file-move-confirm')),
                )
                .onPressed,
            isNull,
          );
          await tester.tap(find.byKey(const ValueKey('file-move-root')));
          await ui.settle(tester);
          await tester.tap(target(archive));
          await ui.settle(tester);
          await tester.tap(find.byKey(const ValueKey('file-move-confirm')));
          await ui.settle(tester);
          expect(folder(wood), findsNothing);
          await tester.tap(find.byKey(const ValueKey('file-path-home')));
          await ui.settle(tester);
          await tester.tap(folder(archive));
          await ui.settle(tester);
          expect(folder(wood), findsOneWidget);
          await menu(wood);
          await tester.tap(find.byKey(const ValueKey('file-move-confirm')));
          await ui.settle(tester);
          await tester.tap(find.byKey(const ValueKey('file-path-home')));
          await ui.settle(tester);
          expect(folder(wood), findsOneWidget);
          await tester.runAsync(() async {
            final all = await folders.all();
            expect(all.firstWhere((f) => f.id == wood).parentId, isNull);
            expect(all.firstWhere((f) => f.id == nested).parentId, wood);
            final file = (await ManagedFileRepository(db).find('manual'))!;
            expect(file.folderId, wood);
            expect(file.relativePath, 'files/manual.pdf');
            expect(file.sha256, 'same-content');
            expect(
              await File('${root.path}/files/manual.pdf').readAsString(),
              'PDF-test',
            );
            expect(
              (await FileBrowserPreferencesStore(db, phone: phone).load()).view,
              'list',
            );
            expect(
              (await FileBrowserPreferencesStore(db, phone: phone).load()).sort,
              FileSort.name,
            );
          });
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
