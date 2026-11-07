import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/features/tools/container_loading/domain/models/container_loading_models.dart';
import 'package:fly/features/tools/container_loading/presentation/container_loading_providers.dart';
import 'package:fly/features/tools/container_loading/presentation/workspace/container_loading_page.dart';

import 'input_continuity_widget_test.dart' as ui;
import 'text_input_state_test.dart' as input;

const pvc = CargoPackageModel(
  id: 'pvc-manual-grid',
  name: 'PVC ceiling',
  dimensions: Dimensions3(2900, 250, 100),
  weightGrams: 20000,
  colorValue: 0xFF79A88C,
);

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'PVC recommended 8x26 renders manual 12x20 as one full block dark=$dark',
      (tester) async {
        ui.viewport(tester, false);
        tester.platformDispatcher.textScaleFactorTestValue = dark ? 1.3 : 1;
        final db = AppDatabase(NativeDatabase.memory());
        final scope = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)],
        );
        final boundary = GlobalKey();
        try {
          await tester.runAsync(() async {
            await db.ensureBuiltInData();
            await scope.read(containerLoadingRepositoryProvider).saveCargo(pvc);
            await ui.fonts();
          });
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: scope,
              child: RepaintBoundary(
                key: boundary,
                child: ui.app(const ContainerLoadingPage(), phone: dark),
              ),
            ),
          );
          await ui.settle(tester);
          final editor = scope.read(loadingEditorProvider);
          final section = editor.sections.first.id;
          final id = editor.addCargo(section, pvc);
          await ui.settle(tester);
          expect(editor.gridFor(editor.entries.single), (8, 26));
          final rows = find.byKey(ValueKey('per-row-$id'));
          final layers = find.byKey(ValueKey('row-count-$id'));
          await ui.reveal(tester, rows);
          await tester.enterText(rows, '');
          await input.typeAtCaret(tester, rows, '1');
          await ui.settle(tester);
          await input.typeAtCaret(tester, rows, '2');
          await ui.settle(tester);
          await tester.enterText(layers, '');
          await input.typeAtCaret(tester, layers, '2');
          await ui.settle(tester);
          await input.typeAtCaret(tester, layers, '0');
          await ui.settle(tester);
          expect(editor.requestedCount, 240);
          expect(editor.packedCount, 240);
          expect(editor.scene.loadedGroups, hasLength(1));
          final group = editor.scene.loadedGroups.single;
          expect((group.rows, group.layers, group.quantity), (12, 20, 240));
          expect(group.boundingDimensions, const Dimensions3(2900, 3000, 2000));
          expect(group.bounds.inside(editor.preset.dimensions), isFalse);
          expect(editor.totalWeightGrams, 4800000);
          expect(find.text('合计 240 件'), findsOneWidget);
          expect(
            find.byKey(ValueKey('grid-placement-warning-$id')),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('review-unpacked')), findsNothing);
          await tester.ensureVisible(
            find.byKey(const ValueKey('section-drop-0')),
          );
          await ui.settle(tester);
          await ui.capture(
            tester,
            boundary,
            'manual-grid-${dark ? 'dark' : 'light'}',
          );
          await tester.enterText(layers, '');
          await ui.settle(tester);
          expect(editor.scene.loadedGroups, isEmpty);
          await input.typeAtCaret(tester, layers, '2');
          await input.typeAtCaret(tester, layers, '0');
          await ui.settle(tester);
          expect(editor.scene.loadedGroups.single.quantity, 240);
          await tester.runAsync(() async {
            await editor.save('PVC 12x20');
            final presets = await scope
                .read(containerLoadingRepositoryProvider)
                .watchPresets()
                .first;
            await editor.open(editor.plan!.id, presets);
          });
          await ui.settle(tester);
          expect(editor.scene.loadedGroups, hasLength(1));
          expect(
            editor.scene.loadedGroups.single.boundingDimensions,
            const Dimensions3(2900, 3000, 2000),
          );
          expect(editor.packedCount, 240);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await ui.settle(tester);
          scope.dispose();
          await ui.settle(tester);
          await tester.runAsync(db.close);
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
