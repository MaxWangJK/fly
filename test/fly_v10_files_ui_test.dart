import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/app/app.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/core/storage/data_root_providers.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/files/presentation/file_entry_content.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/shared/data/workspace_folder_repository.dart';
import 'package:fly/shared/attachments/attachment_providers.dart';
import 'package:fly/shared/attachments/attachment_storage.dart';

class _Opener extends PlatformAttachmentOpener {
  final paths = <String>[];
  @override
  Future<void> open(String path) async => paths.add(path);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('FLY_V10_FILES_CAPTURE')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('files-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('artifacts/v10-files-$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  test('file sizes use appropriate desktop units', () {
    expect(fileSizeLabel(24), '24 B');
    expect(fileSizeLabel(2048), '2.0 KB');
    expect(fileSizeLabel(2621440), '2.5 MB');
    expect(fileSizeLabel(3221225472), '3.0 GB');
  });

  testWidgets(
    'small/medium/list preserve selection and parent tree remains independent',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fly-v10-files-ui-'),
      ))!;
      late String parent;
      await tester.runAsync(() async {
        await db.ensureBuiltInData();
        final folders = WorkspaceFolderRepository(
          db,
          WorkspaceFolderKind.files,
        );
        parent = await folders.create('产品资料');
        final child = await folders.create('室内产品', parentId: parent);
        final repo = ManagedFileRepository(db);
        for (final item in [
          ('price', '产品价格表.pdf', parent),
          ('child', '安装手册.pdf', child),
        ]) {
          await repo.commit(
            ImportedFile(
              id: item.$1,
              relativePath: 'files/${item.$1}.pdf',
              name: item.$2,
              size: 2621440,
              sha256: item.$1,
            ),
            folderId: item.$3,
          );
        }
        final tag = await repo.createTag('报价');
        await repo.setTag('price', tag, true);
        if (const bool.fromEnvironment('FLY_V10_FILES_CAPTURE')) {
          for (final pair in [
            ('Ahem', r'C:\Windows\Fonts\msyh.ttc'),
            ('Microsoft YaHei UI', r'C:\Windows\Fonts\msyh.ttc'),
            (
              'MaterialIcons',
              r'D:\ProgramData\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
            ),
          ]) {
            await (FontLoader(pair.$1)..addFont(
                  File(pair.$2).readAsBytes().then(ByteData.sublistView),
                ))
                .load();
          }
        }
      });
      final opener = _Opener();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          attachmentOpenerProvider.overrideWithValue(opener),
          dataRootPathProvider.overrideWithValue(root.path),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const RepaintBoundary(
            key: ValueKey('files-capture'),
            child: FlyApp(),
          ),
        ),
      );
      await settle(tester);
      container.read(appRouterProvider).go('/files');
      await settle(tester);
      final browser = find.byKey(const ValueKey('file-browser-background'));
      expect(
        tester.widget<ColoredBox>(browser).color,
        Theme.of(tester.element(browser)).colorScheme.surface,
      );
      expect(
        tester
            .widget<FileEntryContent>(find.byType(FileEntryContent).first)
            .mode,
        FileViewMode.list,
      );
      await tester.tap(find.text('产品资料'));
      await settle(tester);
      expect(find.text('产品价格表.pdf'), findsOneWidget);
      expect(find.text('安装手册.pdf'), findsNothing);
      await tester.tap(find.byTooltip('展开'));
      await settle(tester);
      expect(find.text('室内产品'), findsOneWidget);
      await tester.tap(find.text('产品资料'));
      await settle(tester);
      expect(find.text('室内产品'), findsOneWidget);
      await tester.tap(find.byTooltip('收起'));
      await settle(tester);
      expect(find.text('室内产品'), findsNothing);
      await tester.tap(find.byTooltip('视图模式'));
      await settle(tester);
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<FileViewMode>, '小图标'),
      );
      await settle(tester);
      expect(
        tester
            .widget<FileEntryContent>(find.byType(FileEntryContent).first)
            .mode,
        FileViewMode.small,
      );
      await capture(tester, 'small');
      await tester.tap(find.text('产品价格表.pdf'));
      await settle(tester);
      expect(find.byKey(const ValueKey('file-preview-price')), findsNothing);
      expect(opener.paths.single, endsWith('price.pdf'));
      expect(find.text('使用系统程序打开'), findsNothing);
      await capture(tester, 'preview');
      await tester.tap(find.byTooltip('视图模式'));
      await settle(tester);
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<FileViewMode>, '中图标'),
      );
      await settle(tester);
      expect(
        tester
            .widget<FileEntryContent>(find.byType(FileEntryContent).first)
            .mode,
        FileViewMode.medium,
      );
      expect(find.byKey(const ValueKey('file-preview-price')), findsNothing);
      await tester.tap(find.byTooltip('视图模式'));
      await settle(tester);
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<FileViewMode>, '列表'),
      );
      await settle(tester);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('file-list-row-price')))
            .height,
        38,
      );
      for (final text in tester.widgetList<Text>(
        find.descendant(
          of: find.byType(FileEntryContent),
          matching: find.byType(Text),
        ),
      )) {
        expect(text.maxLines, 1);
        expect(text.data, isNot(contains('\n')));
      }
      await capture(tester, 'list');
      tester.view.physicalSize = const Size(440, 850);
      await settle(tester);
      expect(find.byKey(const ValueKey('file-preview-price')), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, 'narrow');
      expect(find.byKey(const ValueKey('file-preview-price')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await settle(tester);
      await tester.runAsync(() async {
        await db.close();
        await root.delete(recursive: true);
      });
    },
  );
}
