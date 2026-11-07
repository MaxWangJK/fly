import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:fly/core/database/app_database.dart';
import 'package:fly/core/storage/data_root_providers.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/files/data/platform_file_transfer.dart';
import 'package:fly/features/files/presentation/files_workspace.dart';
import 'package:fly/features/files/presentation/image_file_viewer.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/shared/attachments/attachment_providers.dart';
import 'package:fly/shared/attachments/attachment_storage.dart';
import 'package:fly/shared/data/workspace_folder_repository.dart';

import 'input_continuity_widget_test.dart' as ui;

class _Opener extends PlatformAttachmentOpener {
  final paths = <String>[];
  @override
  Future<void> open(String path) async => paths.add(path);
}

class _Fixture {
  _Fixture(this.db, this.root, this.opener, this.calls);
  final AppDatabase db;
  final Directory root;
  final _Opener opener;
  final List<MethodCall> calls;
  String owned(String id) =>
      p.join(root.path, 'FlyData', 'files', 'inbox', id, names[id]);
  static const names = {
    'photo': '产品图.png',
    'pdf': '产品说明.pdf',
    'word': '报价说明.docx',
  };
  static final image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5WQAAAAASUVORK5CYII=',
  );
}

Future<void> _withWorkspace(
  WidgetTester tester,
  Future<void> Function(_Fixture fixture) body,
) async {
  ui.viewport(tester, false);
  final root = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('fly-click-drop-'),
  ))!;
  final db = AppDatabase(NativeDatabase.memory());
  final opener = _Opener();
  final calls = <MethodCall>[];
  final fixture = _Fixture(db, root, opener, calls);
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      dataRootPathProvider.overrideWithValue('${root.path}/FlyData'),
      attachmentOpenerProvider.overrideWithValue(opener),
    ],
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(PlatformFileTransfer.channel, (call) async {
        calls.add(call);
        return false; // A cancelled OS drag must not import anything either.
      });
  try {
    await tester.runAsync(() async {
      await db.ensureBuiltInData();
      for (final entry in _Fixture.names.entries) {
        final bytes = entry.key == 'photo'
            ? _Fixture.image
            : utf8.encode('isolated ${entry.key} test file');
        final file = File(fixture.owned(entry.key));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
        await ManagedFileRepository(db).commit(
          ImportedFile(
            id: entry.key,
            relativePath: 'files/inbox/${entry.key}/${entry.value}',
            name: entry.value,
            size: bytes.length,
            sha256: sha256.convert(bytes).toString(),
          ),
        );
      }
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ui.app(const FilesWorkspace()),
      ),
    );
    await ui.settle(tester);
    await body(fixture);
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await ui.settle(tester);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PlatformFileTransfer.channel, null);
    await tester.runAsync(() async {
      await db.close();
      await root.delete(recursive: true);
    });
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<void> _drop(WidgetTester tester, List<String> paths) async {
  tester.widget<DropTarget>(find.byType(DropTarget)).onDragDone!(
    DropDoneDetails(
      files: paths.map(DropItemFile.new).toList(),
      localPosition: const Offset(100, 100),
      globalPosition: const Offset(500, 400),
    ),
  );
  for (var i = 0; i < 40; i++) {
    await ui.settle(tester);
    if (find.byType(AlertDialog).evaluate().isNotEmpty ||
        find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      return;
    }
  }
  fail('The isolated file import did not finish');
}

void main() {
  test('managed drop paths respect boundaries and Windows path casing', () {
    final storage = ManagedFileStorage(
      p.join(Directory.systemTemp.path, 'FlyData'),
    );
    expect(
      storage.isManagedSourcePath(p.join(storage.root, 'files', 'a.pdf')),
      isTrue,
    );
    expect(
      storage.isManagedSourcePath(p.join(storage.root, 'attachments', 'a.pdf')),
      isTrue,
    );
    expect(
      storage.isManagedSourcePath(p.join(storage.root, 'files-copy', 'a.pdf')),
      isFalse,
    );
    expect(
      storage.isManagedSourcePath(
        p.join(storage.root, 'files', '..', 'external', 'a.pdf'),
      ),
      isFalse,
    );
    if (Platform.isWindows) {
      expect(
        storage.isManagedSourcePath(
          p.join(storage.root, 'FILES', 'a.pdf').toUpperCase(),
        ),
        isTrue,
      );
    }
  });

  for (final id in _Fixture.names.keys) {
    testWidgets('single mouse click with small movement opens $id once', (
      tester,
    ) async {
      await _withWorkspace(tester, (fixture) async {
        final point = tester.getCenter(find.byKey(ValueKey('file-item-$id')));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.down(point);
        await mouse.moveBy(const Offset(3, 1));
        await mouse.up();
        await ui.settle(tester);
        expect(
          fixture.calls,
          isEmpty,
          reason: 'A click is not an OS file drag',
        );
        expect(find.byType(AlertDialog), findsNothing);
        if (id == 'photo') {
          expect(find.byType(ImageFileViewer), findsOneWidget);
          expect(fixture.opener.paths, isEmpty);
        } else {
          expect(fixture.opener.paths, [fixture.owned(id)]);
        }
        expect(
          (await tester.runAsync(
            () => fixture.db.select(fixture.db.attachments).get(),
          ))!.length,
          3,
        );
      });
    });
  }

  testWidgets('deliberate drag still transfers once without opening the file', (
    tester,
  ) async {
    await _withWorkspace(tester, (fixture) async {
      final point = tester.getCenter(
        find.byKey(const ValueKey('file-item-pdf')),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.down(point);
      await mouse.moveBy(const Offset(24, 0));
      await tester.pump();
      await mouse.moveBy(const Offset(24, 0));
      await mouse.up();
      await ui.settle(tester);
      expect(fixture.calls.map((c) => c.method), ['drag']);
      expect(fixture.calls.single.arguments, fixture.owned('pdf'));
      expect(fixture.opener.paths, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  testWidgets('own managed files dropped back into Fly are not imported', (
    tester,
  ) async {
    await _withWorkspace(tester, (fixture) async {
      final before = (await tester.runAsync(
        () => File(fixture.owned('pdf')).readAsBytes(),
      ))!;
      await _drop(tester, [fixture.owned('pdf'), fixture.owned('photo')]);
      await ui.settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        (await tester.runAsync(
          () => fixture.db.select(fixture.db.attachments).get(),
        ))!.length,
        3,
      );
      expect(
        await tester.runAsync(() => File(fixture.owned('pdf')).readAsBytes()),
        before,
      );
    });
  });

  testWidgets('holding then dragging into a folder still moves the file', (
    tester,
  ) async {
    await _withWorkspace(tester, (fixture) async {
      final folder = (await tester.runAsync(
        () => WorkspaceFolderRepository(
          fixture.db,
          WorkspaceFolderKind.files,
        ).create('归档资料'),
      ))!;
      await tester.tap(find.text('我的文件').first);
      await ui.settle(tester);
      final file = find.byKey(const ValueKey('file-item-pdf'));
      final destination = find.byKey(ValueKey('desktop-file-folder-$folder'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.down(tester.getCenter(file));
      await tester.pump(const Duration(milliseconds: 600));
      await mouse.moveTo(tester.getCenter(destination));
      await tester.pump();
      await mouse.up();
      await ui.settle(tester);
      final moved = (await tester.runAsync(
        () => ManagedFileRepository(fixture.db).find('pdf'),
      ))!;
      expect(moved.folderId, folder);
      expect(fixture.calls, isEmpty);
      expect(fixture.opener.paths, isEmpty);
      expect(
        await tester.runAsync(() => File(fixture.owned('pdf')).exists()),
        isTrue,
      );
    });
  });

  testWidgets('mixed drop imports external files and skips managed sources', (
    tester,
  ) async {
    await _withWorkspace(tester, (fixture) async {
      final external = File('${fixture.root.path}/external/新说明.pdf');
      await tester.runAsync(() async {
        await external.parent.create(recursive: true);
        await external.writeAsString('a new external document');
      });
      await _drop(tester, [fixture.owned('pdf'), external.path]);
      await ui.settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      final records = (await tester.runAsync(
        () => fixture.db.select(fixture.db.attachments).get(),
      ))!;
      expect(records.length, 4);
      expect(records.where((r) => r.originalName == '新说明.pdf'), hasLength(1));
    });
  });

  testWidgets(
    'real external duplicate still asks before replacing or copying',
    (tester) async {
      await _withWorkspace(tester, (fixture) async {
        final external = File('${fixture.root.path}/external/产品说明.pdf');
        await tester.runAsync(() async {
          await external.parent.create(recursive: true);
          await File(fixture.owned('pdf')).copy(external.path);
        });
        await _drop(tester, [external.path]);
        await ui.settle(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('文件已存在'), findsOneWidget);
        await tester.tap(find.text('跳过'));
        await ui.settle(tester);
        expect(
          (await tester.runAsync(
            () => fixture.db.select(fixture.db.attachments).get(),
          ))!.length,
          3,
        );
      });
    },
  );

  testWidgets('hidden file workspace does not import behind the image viewer', (
    tester,
  ) async {
    await _withWorkspace(tester, (fixture) async {
      await tester.tap(find.byKey(const ValueKey('file-item-photo')));
      await ui.settle(tester);
      expect(find.byType(ImageFileViewer), findsOneWidget);
      final external = File('${fixture.root.path}/external/其他.pdf');
      await tester.runAsync(() async {
        await external.parent.create(recursive: true);
        await external.writeAsString('another document');
      });
      await _drop(tester, [external.path]);
      await ui.settle(tester);
      expect(
        (await tester.runAsync(
          () => fixture.db.select(fixture.db.attachments).get(),
        ))!.length,
        3,
      );
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byTooltip('关闭').last);
      await ui.settle(tester);
      expect(tester.widget<DropTarget>(find.byType(DropTarget)).enable, isTrue);
      await _drop(tester, [external.path]);
      expect(
        (await tester.runAsync(
          () => fixture.db.select(fixture.db.attachments).get(),
        ))!.length,
        4,
      );
    });
  });
}
