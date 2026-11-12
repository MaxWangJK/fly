import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/app/app.dart';
import 'package:fly/app/settings/navigation_settings.dart';
import 'package:fly/app/settings/settings_center.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/core/storage/data_root_providers.dart';
import 'package:fly/features/files/data/file_browser_preferences.dart';
import 'package:fly/features/files/data/file_browser_query.dart';
import 'package:fly/features/files/data/file_clipboard.dart';
import 'package:fly/features/files/presentation/file_providers.dart';
import 'package:fly/features/notes/data/note_repository.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/shared/data/workspace_folder_repository.dart';
import 'package:fly/shared/search/global_search_service.dart';

import 'input_continuity_widget_test.dart' as ui;

Future<List<AttachmentRecord>> _inFolder(
  ProviderContainer container,
  String id,
) async =>
    (await container.read(managedFileRepositoryProvider).watchAll().first)
        .where((file) => file.folderId == id && file.deletedAt == null)
        .toList();

class _Clipboard extends FileClipboard {
  List<String> paths = [];
  @override
  Future<List<String>> readFiles() async => List.of(paths);
}

Finder _choice(String key) => find.byWidgetPredicate(
  (widget) => widget is CheckboxMenuButton && widget.key == ValueKey(key),
);

Future<void> _context(WidgetTester tester) async {
  final area = tester.getRect(
    find.byKey(const ValueKey('desktop-files-blank')),
  );
  await tester.tapAt(
    Offset(area.right - 130, area.bottom - 20),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await ui.settle(tester);
}

Future<void> _name(WidgetTester tester, String text) async {
  await ui.settle(tester);
  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ),
    text,
  );
  await tester.tap(find.widgetWithText(FilledButton, '确认'));
  await ui.settle(tester);
}

Future<void> _finishPaste(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await ui.settle(tester);
    if (find.byType(AlertDialog).evaluate().isNotEmpty ||
        find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      return;
    }
  }
  fail('The isolated clipboard import did not finish');
}

void main() {
  test('legacy navigation defaults library off and persists explicit opt-in without deleting notes', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureBuiltInData();
    final note = await NoteRepository(db).create('Legacy library research');
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: NavigationSettingsController.key,
            value: '{"dashboardVisible":true,"crmVisible":false,"toolsVisible":false}',
            updatedAt: DateTime.now(),
          ),
        );
    final nav = NavigationSettingsController(db);
    await nav.ready;
    expect(nav.value.knowledgeVisible, isFalse);
    expect(nav.value.dashboardVisible, isTrue);
    expect(nav.value.crmVisible, isFalse);
    expect(StartupWorkspaceResolver.allowed('/knowledge', nav.value), isFalse);
    expect(StartupWorkspaceResolver.allowed('/notes', nav.value), isFalse);
    final hiddenSearch = GlobalSearchService(db, includeWorkspaceNotes: false);
    expect(
      (await hiddenSearch.search('Legacy library research'))
          .where((r) => r.type == SearchResultType.workspaceNote),
      isEmpty,
    );
    await nav.update(nav.value.copyWith(knowledgeVisible: true));
    await nav.update(nav.value.copyWith(toolsVisible: true));
    expect(nav.value.knowledgeVisible, isTrue);
    nav.dispose();
    final restored = NavigationSettingsController(db);
    await restored.ready;
    expect(restored.value.knowledgeVisible, isTrue);
    expect(
      StartupWorkspaceResolver.allowed('/knowledge', restored.value),
      isTrue,
    );
    expect(
      (await GlobalSearchService(db).search('Legacy library research'))
          .any((r) => r.entityId == note),
      isTrue,
    );
    restored.dispose();
  });

  testWidgets(
    'library can be enabled in navigation settings and hidden again while open',
    (tester) async {
      ui.viewport(tester, false);
      final db = AppDatabase(NativeDatabase.memory());
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fly-library-default-'),
      ))!;
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dataRootPathProvider.overrideWithValue(root.path),
        ],
      );
      try {
        await tester.runAsync(() async {
          await db.ensureBuiltInData();
          await ui.fonts();
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const FlyApp(),
          ),
        );
        await ui.settle(tester);
        expect(find.byKey(const ValueKey('primary-notes')), findsNothing);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: ui.app(const SettingsCenter(initialCategory: '导航')),
          ),
        );
        await ui.settle(tester);
        final toggle = find.byKey(const ValueKey('knowledge-visible'));
        await ui.reveal(tester, toggle);
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        await tester.tap(toggle);
        await ui.settle(tester);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const FlyApp(),
          ),
        );
        await ui.settle(tester);
        expect(find.byKey(const ValueKey('primary-notes')), findsOneWidget);
        container.read(appRouterProvider).go('/knowledge');
        await ui.settle(tester);
        expect(find.byKey(const ValueKey('book-import')), findsOneWidget);
        await tester.runAsync(
          () => container
              .read(navigationSettingsProvider)
              .update(
                container
                    .read(navigationSettingsProvider)
                    .value
                    .copyWith(knowledgeVisible: false),
              ),
        );
        await ui.settle(tester);
        expect(find.byKey(const ValueKey('primary-notes')), findsNothing);
        expect(find.byKey(const ValueKey('book-import')), findsNothing);
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

  for (final size in [
    const Size(1264, 850),
    const Size(900, 600),
    const Size(640, 480),
  ]) {
    testWidgets(
      'desktop create, cascading views, sorting and clipboard file paste at $size',
      (tester) async {
        ui.viewport(tester, false);
        final shadows = debugDisableShadows;
        debugDisableShadows = false;
        tester.view.physicalSize = size;
        final dark = size.width < 1000;
        tester.platformDispatcher.textScaleFactorTestValue = dark ? 1.3 : 1;
        final db = AppDatabase(NativeDatabase.memory());
        final root = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('fly-file-context-'),
        ))!;
        final clipboard = _Clipboard();
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dataRootPathProvider.overrideWithValue(root.path),
            fileClipboardProvider.overrideWithValue(clipboard),
          ],
        );
        final capture = GlobalKey();
        final folders = container.read(fileFolderRepositoryProvider);
        try {
          late String alpha, zulu;
          final source = File('${root.path}/clipboard-source.txt');
          await tester.runAsync(() async {
            await db.ensureBuiltInData();
            await ui.fonts();
            zulu = await folders.create('Zulu');
            alpha = await folders.create('Alpha');
            await source.writeAsString('Clipboard file contents');
            await FileBrowserPreferencesStore(db, phone: false).save(
              const FileBrowserPreferences(
                view: 'small',
                collection: FileCollection.folder,
              ),
            );
          });
          if (dark) {
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
          final fab = find.byKey(const ValueKey('desktop-new-folder'));
          final bounds = tester.getRect(
            find.byKey(const ValueKey('desktop-files-blank')),
          );
          final button = tester.getRect(fab);
          expect(button.right, lessThanOrEqualTo(bounds.right - 12));
          expect(button.bottom, lessThanOrEqualTo(bounds.bottom - 12));
          expect(button.left, greaterThan(bounds.center.dx));

          await _context(tester);
          expect(
            tester
                .widget<MenuItemButton>(
                  find.byKey(const ValueKey('files-context-paste')),
                )
                .onPressed,
            isNull,
          );
          await tester.tap(find.byKey(const ValueKey('files-context-view')));
          await ui.settle(tester);
          expect(
            tester
                .widget<CheckboxMenuButton>(_choice('files-context-view-small'))
                .value,
            isTrue,
          );
          await ui.capture(
            tester,
            capture,
            size.width < 800
                ? 'files-context-compact'
                : dark
                ? 'files-context-dark'
                : 'files-context-light',
          );
          await tester.tap(_choice('files-context-view-list'));
          await ui.settle(tester);
          expect(
            find.byKey(ValueKey('desktop-folder-list-$alpha')),
            findsOneWidget,
          );
          await _context(tester);
          await tester.tap(find.byKey(const ValueKey('files-context-sort')));
          await ui.settle(tester);
          await tester.tap(_choice('files-context-sort-name'));
          await ui.settle(tester);
          expect(
            tester
                .getTopLeft(find.byKey(ValueKey('desktop-folder-list-$alpha')))
                .dy,
            lessThan(
              tester
                  .getTopLeft(find.byKey(ValueKey('desktop-folder-list-$zulu')))
                  .dy,
            ),
          );
          final saved = (await tester.runAsync(
            () => FileBrowserPreferencesStore(db, phone: false).load(),
          ))!;
          expect(saved.view, 'list');
          expect(saved.sort, FileSort.name);

          await tester.tap(find.byKey(ValueKey('desktop-file-folder-$alpha')));
          await ui.settle(tester);
          await tester.tap(fab);
          await _name(tester, 'Child collection');
          final child = (await tester.runAsync(folders.all))!
              .singleWhere((f) => f.name == 'Child collection');
          expect(child.parentId, alpha);
          clipboard.paths = [
            root.path,
            source.path,
            source.path,
            '${root.path}/missing.txt',
          ];
          await _context(tester);
          expect(
            (await tester.runAsync(() => _inFolder(container, child.id)))!,
            isEmpty,
          );
          await tester.tap(find.byKey(const ValueKey('files-context-paste')));
          await _finishPaste(tester);
          final imported = (await tester.runAsync(
            () => _inFolder(container, child.id),
          ))!.single;
          expect(imported.originalName, 'clipboard-source.txt');
          expect(find.text('仅支持粘贴文件，已跳过文件夹或不可用项目'), findsOneWidget);
          ScaffoldMessenger.of(
            tester.element(find.byKey(const ValueKey('desktop-files-blank'))),
          ).removeCurrentSnackBar();
          await ui.settle(tester);
          expect(
            await tester.runAsync(
              () => File(
                container
                    .read(managedFileStorageProvider)
                    .absolute(imported.relativePath),
              ).readAsString(),
            ),
            'Clipboard file contents',
          );
          expect(
            await tester.runAsync(source.readAsString),
            'Clipboard file contents',
          );

          // Explicit paste, unlike a simple click/drop, retains duplicate confirmation.
          clipboard.paths = [source.path];
          await _context(tester);
          await tester.tap(find.byKey(const ValueKey('files-context-paste')));
          await _finishPaste(tester);
          expect(find.byType(AlertDialog), findsOneWidget);
          await tester.tap(find.widgetWithText(TextButton, '保留副本'));
          await _finishPaste(tester);
          expect(
            (await tester.runAsync(() => _inFolder(container, child.id)))!,
            hasLength(2),
          );

          await tester.tapAt(
            tester.getCenter(find.byKey(ValueKey('file-item-${imported.id}'))),
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton,
          );
          await ui.settle(tester);
          await tester.ensureVisible(find.text('剪切（在 Fly 文件夹粘贴）'));
          await ui.settle(tester);
          await tester.tap(find.text('剪切（在 Fly 文件夹粘贴）'));
          await ui.settle(tester);
          await tester.tap(find.byKey(const ValueKey('file-path-home')));
          await ui.settle(tester);
          await tester.tap(find.byKey(ValueKey('desktop-file-folder-$zulu')));
          await ui.settle(tester);
          clipboard.paths = [];
          await _context(tester);
          await tester.tap(find.byKey(const ValueKey('files-context-paste')));
          await ui.settle(tester);
          final moved = (await tester.runAsync(
            () =>
                container.read(managedFileRepositoryProvider).find(imported.id),
          ))!;
          expect(moved.folderId, zulu);
          expect(moved.relativePath, imported.relativePath);
          if (!dark) {
            await tester.tap(find.text('客户文件').first);
            await ui.settle(tester);
            await tester.tap(fab);
            await _name(tester, 'Customer collection');
            final customerFolder = (await tester.runAsync(folders.all))!
                .singleWhere((f) => f.name == 'Customer collection');
            expect(
              customerFolder.parentId,
              WorkspaceFolderRepository.customerFilesRootId,
            );
            await tester.tap(find.text('最近删除').first);
            await ui.settle(tester);
            expect(fab, findsNothing);
            await _context(tester);
            expect(
              find.byKey(const ValueKey('files-context-new-folder')),
              findsNothing,
            );
            expect(
              find.byKey(const ValueKey('files-context-paste')),
              findsNothing,
            );
            expect(
              find.byKey(const ValueKey('files-context-refresh')),
              findsOneWidget,
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
          debugDisableShadows = shadows;
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
