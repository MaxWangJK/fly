import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/app/app.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/core/storage/data_root_providers.dart';
import 'package:fly/features/knowledge/presentation/knowledge_providers.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';

void main() {
  testWidgets(
    'primary Knowledge route opens original articles and private notes',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fly-knowledge-ui-'),
      ))!;
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await db.close();
        await root.delete(recursive: true);
      });
      await tester.runAsync(db.ensureBuiltInData);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dataRootPathProvider.overrideWithValue(root.path),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const FlyApp()),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.byKey(const ValueKey('primary-notes')));
      await tester.runAsync(
        () => container.read(knowledgeCatalogProvider.future),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('外贸SOP总览'), findsWidgets);
      expect(
        find.byKey(const ValueKey('knowledge-sidebar-sop')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('knowledge-sidebar-notes')));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const ValueKey('new-note-title')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    },
  );
}
