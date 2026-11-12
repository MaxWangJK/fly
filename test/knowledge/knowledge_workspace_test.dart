import 'package:fly/app/settings/navigation_settings.dart';

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/app/app.dart';
import 'package:fly/config/feature_flags.dart';
import 'package:fly/shared/search/global_search_providers.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/core/storage/data_root_providers.dart';
import 'package:fly/features/knowledge/presentation/fly_book_providers.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';

void main() {
  testWidgets('desktop library exposes book import and hides personal notes', (
    tester,
  ) async {
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
    await tester.runAsync(() async {
      final nav = container.read(navigationSettingsProvider);
      await nav.ready;
      await nav.update(nav.value.copyWith(knowledgeVisible: true));
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const FlyApp()),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const ValueKey('primary-notes')));
    if (enableKnowledgeHub) {
      await tester.runAsync(() => container.read(flyBooksProvider.future));
    }
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (enableKnowledgeHub) {
      expect(find.byKey(const ValueKey('book-import')), findsOneWidget);
      expect(find.byKey(const ValueKey('new-note-title')), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(container.read(globalSearchServiceProvider).knowledge, isNull);
      container.read(appRouterProvider).go('/knowledge?view=notes');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('new-note-title')), findsNothing);
    } else {
      expect(find.text('外贸SOP总览'), findsNothing);
      expect(
        find.byKey(const ValueKey('knowledge-sidebar-home')),
        findsNothing,
      );
      expect(container.read(globalSearchServiceProvider).knowledge, isNull);
      final router = container.read(appRouterProvider);
      expect(router.routeInformationProvider.value.uri.path, '/notes');
      router.go('/knowledge?article=quote-followup&id=legacy-note');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/notes');
      expect(
        router.routeInformationProvider.value.uri.queryParameters['id'],
        'legacy-note',
      );
      router.go('/notes');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('primary-settings')));
      await tester.pumpAndSettle();
      expect(find.text('资料库'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('settings-category-9')));
      await tester.pumpAndSettle();
      expect(find.text('关于'), findsWidgets);
      await tester.tap(find.byTooltip('关闭设置'));
      await tester.pumpAndSettle();
    }
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.byKey(const ValueKey('new-note-title')),
      enableKnowledgeHub ? findsNothing : findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}
