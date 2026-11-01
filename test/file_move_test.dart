import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/core/storage/data_root_providers.dart';
import 'package:fly/features/files/data/file_browser_query.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/files/presentation/files_workspace.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/data/workspace_folder_repository.dart';
import 'package:fly/shared/design_system/app_theme.dart';

void main() {
  for (final scenario in [
    (const Size(1400, 900), false, false, 1.0),
    (const Size(390, 844), true, false, 1.0),
    (const Size(844, 390), true, true, 1.0),
    (const Size(320, 720), true, true, 1.3),
  ]) {
    final (size, phone, dark, textScale) = scenario;
    testWidgets(
      'single and batch moves preserve selection and file access at $size',
      (tester) async {
        debugDefaultTargetPlatformOverride = phone
            ? TargetPlatform.android
            : TargetPlatform.windows;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final db = AppDatabase(NativeDatabase.memory());
        final root = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('fly-file-move-'),
        ))!;
        final repository = ManagedFileRepository(db);
        final folders = WorkspaceFolderRepository(
          db,
          WorkspaceFolderKind.files,
        );
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dataRootPathProvider.overrideWithValue(root.path),
          ],
        );
        final boundary = GlobalKey();
        late String source, target, child;
        late AttachmentRecord original;
        final imageBytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAeklEQVR4nO3PUQkAIBTAwFfRXJYymiH8OITBAtxm7fN1wwUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWPHYBqDvBeK6ZIhcAAAAASUVORK5CYII=',
        );

        Future<void> settle() async {
          for (var i = 0; i < 10; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump(const Duration(milliseconds: 80));
          }
        }

        Future<void> openMove() async {
          final file = find.byKey(const ValueKey('file-item-photo'));
          if (phone) {
            await tester.longPress(file);
          } else {
            await tester.tap(file, buttons: kSecondaryMouseButton);
          }
          await settle();
          expect(find.text('移动'), findsOneWidget);
          await tester.tap(find.text('移动'));
          await settle();
          expect(
            find.byKey(const ValueKey('file-move-dialog')),
            findsOneWidget,
          );
        }

        Finder folder(String id) =>
            find.byKey(ValueKey('file-move-folder-$id'));
        final confirm = find.byKey(const ValueKey('file-move-confirm'));
        Future<void> enterDestination() async {
          await tester.ensureVisible(folder(target));
          await settle();
          await tester.tap(folder(target));
          await settle();
          await tester.ensureVisible(folder(child));
          await settle();
          await tester.tap(folder(child));
          await settle();
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('file-move-path')))
                .data,
            '我的文件 / 产品资料 / 相册',
          );
        }

        try {
          await tester.runAsync(() async {
            await db.ensureBuiltInData();
            source = await folders.create('原目录');
            target = await folders.create('产品资料');
            child = await folders.create('相册', parentId: target);
            final file = File('${root.path}/files/photo.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(imageBytes);
            await repository.commit(
              ImportedFile(
                id: 'photo',
                relativePath: 'files/photo.png',
                name: 'Product photo.png',
                size: imageBytes.length,
                sha256: 'synthetic-image',
              ),
              folderId: source,
            );
            final tag = await repository.createTag('Sample');
            await repository.setTag('photo', tag, true);
            original = (await repository.find('photo'))!;
            if (const bool.fromEnvironment('FLY_FILE_MOVE_CAPTURE')) {
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
            }
          });
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: RepaintBoundary(
                key: boundary,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: dark ? FlyTheme.dark() : FlyTheme.light(),
                  locale: const Locale('zh', 'CN'),
                  supportedLocales: FlyLocalizations.supportedLocales,
                  localizationsDelegates: const [
                    FlyLocalizationsDelegate(),
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  home: const Scaffold(
                    body: FilesWorkspace(initialFileId: 'photo'),
                  ),
                ),
              ),
            ),
          );
          await settle();
          await openMove();
          await tester.tap(folder(source));
          await settle();
          expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
          await tester.tap(find.byKey(const ValueKey('file-move-root')));
          await settle();
          await enterDestination();
          if (const bool.fromEnvironment('FLY_FILE_MOVE_CAPTURE')) {
            await tester.runAsync(() async {
              final picture =
                  await (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage();
              try {
                final bytes = await picture.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File('build/file-move-${size.width.toInt()}.png')
                    .writeAsBytes(bytes!.buffer.asUint8List());
              } finally {
                picture.dispose();
              }
            });
          }
          await tester.tap(
            find.descendant(
              of: find.byKey(const ValueKey('file-move-dialog')),
              matching: find.text('取消'),
            ),
          );
          await settle();
          expect(
            (await tester.runAsync(() => repository.find('photo')))!.folderId,
            source,
          );

          await openMove();
          await enterDestination();
          await tester.tap(confirm);
          await settle();
          var moved = (await tester.runAsync<AttachmentRecord?>(
            () => repository.find('photo'),
          ))!;
          expect(moved.folderId, child);
          expect(moved.id, original.id);
          expect(moved.relativePath, original.relativePath);
          expect(moved.sha256, original.sha256);
          expect(moved.ownerType, original.ownerType);
          expect(moved.ownerId, original.ownerId);
          expect(
            (await tester.runAsync(() => repository.watchLinks().first))!,
            hasLength(1),
          );
          expect(find.text('文件已移动'), findsOneWidget);

          await openMove();
          await tester.tap(confirm);
          await settle();
          moved = (await tester.runAsync<AttachmentRecord?>(
            () => repository.find('photo'),
          ))!;
          expect(moved.folderId, isNull);
          final entries = await tester.runAsync(
            () =>
                FileBrowserQuery(db)
                    .watch(collection: FileCollection.folder)
                    .first,
          );
          expect(entries!.map((e) => e.file.id), contains('photo'));
          expect(
            await tester.runAsync(
              () => File('${root.path}/${moved.relativePath}').readAsBytes(),
            ),
            imageBytes,
          );

          await tester.tap(find.byKey(const ValueKey('file-item-photo')));
          await settle();
          expect(
            find.byKey(const ValueKey('image-file-viewer')),
            findsOneWidget,
          );
          expect(
            find.text(
              const FlyLocalizations(Locale('zh')).t('fileImageUnavailable'),
            ),
            findsNothing,
          );
          await tester.tap(find.byTooltip('关闭'));
          await settle();

          await openMove();
          expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
          await enterDestination();
          await tester.runAsync(() => folders.remove(child));
          await settle();
          expect(find.text('文件夹已不可用，请重新选择'), findsOneWidget);
          expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
          await tester.tap(
            find.descendant(
              of: find.byKey(const ValueKey('file-move-dialog')),
              matching: find.text('取消'),
            ),
          );
          await settle();
          // Start from a real folder result so successful moves disappear from
          // the source while the batch still processes its original selection.
          await tester.runAsync(() => folders.restore(child));
          await settle();
          await tester.runAsync(() => repository.move('photo', source));
          await settle();
          await tester.runAsync(() async {
            await File('${root.path}/files/report.pdf')
                .writeAsBytes([37, 80, 68, 70]);
            await repository.commit(
              const ImportedFile(
                id: 'report',
                relativePath: 'files/report.pdf',
                name: 'Product report.pdf',
                size: 4,
                sha256: 'synthetic-report',
              ),
              folderId: source,
            );
          });
          if (phone) {
            await tester.tap(find.byKey(const ValueKey('mobile-files-back')));
            await settle();
            await tester.tap(
              find.byKey(ValueKey('mobile-file-folder-$source')),
            );
          } else {
            await tester.tap(find.text('我的文件').first);
            await settle();
            await tester.tap(
              find.byKey(ValueKey('desktop-file-folder-$source')),
            );
          }
          await settle();

          Future<void> selectBoth() async {
            if (phone) {
              await tester.longPress(
                find.byKey(const ValueKey('file-item-photo')),
              );
              await settle();
              await tester.ensureVisible(find.text('选择'));
              await settle();
              await tester.tap(find.text('选择'));
            } else {
              await tester.tap(
                find.byKey(const ValueKey('files-multi-select')),
              );
            }
            await settle();
            await tester.tap(find.byKey(const ValueKey('files-select-all')));
            await settle();
            expect(find.text('已选 2 项'), findsOneWidget);
          }

          await selectBoth();
          if (const bool.fromEnvironment('FLY_FILE_MOVE_CAPTURE')) {
            await tester.runAsync(() async {
              final picture =
                  await (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage();
              try {
                final bytes = await picture.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File('build/file-batch-move-${size.width.toInt()}.png')
                    .writeAsBytes(bytes!.buffer.asUint8List());
              } finally {
                picture.dispose();
              }
            });
          }
          final batchMove = find.byKey(const ValueKey('files-batch-move'));
          await tester.tap(batchMove);
          await settle();
          expect(find.text('已选 2 个文件'), findsOneWidget);
          await enterDestination();
          await tester.tap(
            find.descendant(
              of: find.byKey(const ValueKey('file-move-dialog')),
              matching: find.text('取消'),
            ),
          );
          await settle();
          expect(find.text('已选 2 项'), findsOneWidget);
          expect(
            (await tester.runAsync(() => repository.find('photo')))!.folderId,
            source,
          );
          expect(
            (await tester.runAsync(() => repository.find('report')))!.folderId,
            source,
          );

          await tester.tap(batchMove);
          await settle();
          await enterDestination();
          await tester.tap(confirm);
          await settle();
          for (final id in ['photo', 'report']) {
            expect(
              (await tester.runAsync(() => repository.find(id)))!.folderId,
              child,
            );
            expect(find.byKey(ValueKey('file-item-$id')), findsNothing);
          }
          expect(
            find.byKey(const ValueKey('files-selection-bar')),
            findsNothing,
          );
          expect(find.text('已移动 2 项'), findsOneWidget);

          if (phone) {
            await tester.tap(find.byKey(const ValueKey('mobile-files-back')));
            await settle();
            await tester.tap(
              find.byKey(ValueKey('mobile-file-folder-$target')),
            );
            await settle();
            await tester.tap(find.byKey(ValueKey('mobile-file-folder-$child')));
          } else {
            await tester.tap(find.text('我的文件').first);
            await settle();
            await tester.tap(
              find.byKey(ValueKey('desktop-file-folder-$target')),
            );
            await settle();
            await tester.tap(
              find.byKey(ValueKey('desktop-file-folder-$child')),
            );
          }
          await settle();
          await selectBoth();
          await tester.tap(batchMove);
          await settle();
          await tester.tap(confirm);
          await settle();
          for (final id in ['photo', 'report']) {
            expect(
              (await tester.runAsync(() => repository.find(id)))!.folderId,
              isNull,
            );
          }

          // Mixed selections keep protected attachments selected and explain
          // every failure without blocking the ordinary file in the batch.
          await tester.runAsync(() async {
            await (db.update(
              db.attachments,
            )..where((f) => f.id.equals('report'))).write(
              const AttachmentsCompanion(
                ownerType: Value('note'),
                ownerId: Value('synthetic-note'),
              ),
            );
          });
          if (phone) {
            await tester.tap(find.byKey(const ValueKey('mobile-files-back')));
            await settle();
            await tester.tap(find.byKey(const ValueKey('mobile-files-back')));
            await settle();
            await tester.enterText(
              find.byKey(const ValueKey('file-search-input')),
              'Product',
            );
            await tester.testTextInput.receiveAction(TextInputAction.search);
          } else {
            await tester.tap(find.text('最近'));
          }
          await settle();
          await selectBoth();
          await tester.tap(batchMove);
          await settle();
          expect(find.text('其中 1 个关联附件将保留在所属记录'), findsOneWidget);
          expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
          await enterDestination();
          await tester.tap(confirm);
          await settle();
          expect(find.text('已移动 1 项，1 项未移动'), findsOneWidget);
          expect(find.text('已选 1 项'), findsOneWidget);
          expect(tester.widget<TextButton>(batchMove).onPressed, isNull);
          expect(
            (await tester.runAsync(() => repository.find('report')))!.ownerId,
            'synthetic-note',
          );
          await tester.tap(find.text('详情'));
          await settle();
          expect(find.text('未能移动的文件'), findsOneWidget);
          expect(find.text('Product report.pdf'), findsWidgets);
          await tester.tap(find.text('关闭'));
          await settle();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
          await settle();
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
