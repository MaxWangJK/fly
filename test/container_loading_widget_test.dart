import 'package:drift/native.dart';
import 'package:fly/app/app.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/features/tools/container_loading/presentation/container_loading_providers.dart';
import 'package:fly/features/tools/container_loading/presentation/loading_editor_controller.dart';
import 'package:fly/features/tools/container_loading/domain/models/section_models.dart';
import 'package:fly/features/tools/container_loading/domain/models/container_loading_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'container_actual_spaces_test.dart' as actual;

Future<(AppDatabase, ProviderContainer, LoadingEditorController)> setup(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(1700, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = AppDatabase(NativeDatabase.memory());
  await db.ensureBuiltInData();
  addTearDown(db.close);
  final container = ProviderContainer(
    overrides: [databaseProvider.overrideWithValue(db)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const FlyApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('primary-tools')));
  await tester.pumpAndSettle();
  return (db, container, container.read(loadingEditorProvider));
}

Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  testWidgets(
    'occupied section refuses generic drop while area card accepts cargo at its coordinates',
    (tester) async {
      final (_, _, editor) = await setup(tester);
      final section = editor.sections.first.id;
      editor.addCargo(section, actual.pvc);
      editor.scene.resizeGroup(
        editor.scene.groups.single.id,
        rows: 8,
        layers: 20,
      );
      await tester.pumpAndSettle();
      final source = find.byKey(const ValueKey('cargo-drag-cargo-wpc-grille'));
      final sectionFinder = find.byKey(const ValueKey('section-drop-0'));
      await tester.dragFrom(
        tester.getCenter(source),
        tester.getTopLeft(sectionFinder) +
            const Offset(40, 15) -
            tester.getCenter(source),
      );
      await tester.pumpAndSettle();
      expect(editor.scene.loadedGroups, hasLength(1));
      final top = editor
          .spacesFor(section)
          .singleWhere((s) => s.bounds.z == 2000);
      final area = find.byKey(ValueKey('space-drop-${top.id}'));
      await tester.ensureVisible(area);
      await tester.pumpAndSettle();
      await tester.dragFrom(
        tester.getCenter(source),
        tester.getCenter(area) - tester.getCenter(source),
      );
      await tester.pumpAndSettle();
      expect(editor.scene.loadedGroups, hasLength(2));
      expect(editor.scene.groups.last.positionZmm, 2000);
      expect(
        editor.scene.groups.last.bounds.overlaps(
          editor.scene.groups.first.bounds,
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );
  testWidgets(
    'V3 pallet keeps direct quantity while three spaces offer row inputs',
    (tester) async {
      final (_, _, editor) = await setup(tester);
      const pallet = CargoPackageModel(
        id: 'long-pallet',
        name: '标准托盘 2.8m',
        type: CargoPackageType.pallet,
        dimensions: Dimensions3(2800, 1200, 1000),
        weightGrams: 800000,
        colorValue: 0xFF7FA7C9,
      );
      editor.addCargo(editor.sections.first.id, pallet);
      editor.updateEntry(
        editor.entries.single.copyWith(
          quantity: 2,
          allowStack: true,
          horizontalPlacement: HorizontalPlacement.center,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('quantity-${editor.entries.single.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('remaining-spaces-${editor.sections.first.id}')),
        findsOneWidget,
      );
      final space = editor
          .spacesFor(editor.sections.first.id)
          .singleWhere((s) => s.bounds.z > 0);
      final shownSpace = LoadingSpace.suggested(
        editor.spacesFor(editor.sections.first.id),
        [],
      ).singleWhere((s) => s.id == space.id);
      final chooser = find.byTooltip('为${shownSpace.name}选择货物');
      await tester.ensureVisible(chooser);
      await tester.tap(chooser);
      await tester.pumpAndSettle();
      await tester.tap(find.text('WPC 格栅').last);
      await tester.pumpAndSettle();
      final entry = editor.entries.last;
      expect(entry.spaceId, space.id);
      final first = find.byKey(ValueKey('per-row-${entry.id}'));
      await tester.ensureVisible(first);
      await tester.enterText(first, '2');
      await tester.enterText(
        find.byKey(ValueKey('row-count-${entry.id}')),
        '3',
      );
      await tester.pumpAndSettle();
      expect(editor.entries.last.quantity, 6);
      expect(find.text('合计 6 件'), findsOneWidget);
      editor.pack(editor.sections.first.id);
      await tester.pumpAndSettle();
      expect(editor.packedFor(entry.id), 6);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );
  testWidgets(
    'carton row inputs replace clearance and pack 10 x 18 with sticky save',
    (tester) async {
      final (_, container, editor) = await setup(tester);
      final cargo = container
          .read(cargoLibraryProvider)
          .requireValue
          .firstWhere((c) => c.id == 'cargo-wpc-grille');
      editor.addCargo(editor.sections.first.id, cargo);
      await tester.pumpAndSettle();
      expect(find.text('安全间隙'), findsNothing);
      await tester.enterText(
        find.byKey(ValueKey('per-row-${editor.entries.single.id}')),
        '10',
      );
      await tester.enterText(
        find.byKey(ValueKey('row-count-${editor.entries.single.id}')),
        '18',
      );
      await tester.pumpAndSettle();
      expect(find.text('理论本节 286 件'), findsOneWidget);
      expect(find.text('合计 180 件'), findsOneWidget);
      expect(find.text('自动装柜'), findsNothing);
      await tester.pumpAndSettle();
      expect(editor.packedCount, 180);
      expect(editor.scene.groups.first.positionXmm, 0);
      expect(find.byKey(const ValueKey('review-unpacked')), findsNothing);
      await tester.drag(
        find.byKey(const ValueKey('loading-editor-scroll')),
        const Offset(0, -1800),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('save-loading-plan')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );
  testWidgets(
    'unpacked review confirms without fabricating cargo and survives save',
    (tester) async {
      final (_, container, editor) = await setup(tester);
      final cargo = container
          .read(cargoLibraryProvider)
          .requireValue
          .firstWhere((c) => c.id == 'cargo-wpc-grille');
      editor.addCargo(editor.sections.first.id, cargo);
      editor.updateEntry(editor.entries.single.copyWith(quantity: 300));
      editor.setClearance(40);
      // Exercise a weight/space shortfall not yet acknowledged by a pre-pack dialog.
      editor.pack(editor.sections.first.id);
      await tester.pumpAndSettle();
      expect(editor.packedCount, 286);
      await tester.tap(find.byKey(const ValueKey('review-unpacked')));
      await tester.pumpAndSettle();
      expect(find.textContaining('未装 14 件'), findsWidgets);
      await tester.tap(find.text('确认保留未装数量'));
      await tester.pumpAndSettle();
      expect(editor.entries.single.manualQuantityOverride, true);
      expect(editor.needsPacking, isNot(contains(editor.sections.first.id)));
      expect(editor.packedCount, 286);
      expect(editor.entries.single.quantity, 300);
      await tester.tap(find.byKey(const ValueKey('save-loading-plan')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Gap review',
      );
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, '确定'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(editor.plan?.name, 'Gap review');
      expect(editor.dirty, false);
      final saved = await tester.runAsync(
        () => container
            .read(containerLoadingRepositoryProvider)
            .loadSectionPlan(editor.plan!.id),
      );
      expect(saved!.entries.single.manualQuantityOverride, true);
      expect(saved.entries.single.quantity, 300);
      expect(saved.groups.fold(0, (n, g) => n + g.quantity), 286);
      await finish(tester);
    },
  );
  testWidgets(
    'quantity changes calculate immediately without a confirmation step',
    (tester) async {
      final (_, container, editor) = await setup(tester);
      editor.addCargo(
        editor.sections.first.id,
        container
            .read(cargoLibraryProvider)
            .requireValue
            .firstWhere((c) => c.id == 'cargo-wpc-grille'),
      );
      editor.updateEntry(editor.entries.single.copyWith(quantity: 180));
      editor.setClearance(40);
      await tester.pumpAndSettle();
      expect(find.text('确认保留未装数量'), findsNothing);
      expect(editor.packedCount, 180);
      expect(find.byKey(const ValueKey('review-unpacked')), findsNothing);
      await finish(tester);
    },
  );
  testWidgets(
    'empty scene follows mouse right and down; Alt retains rotation',
    (tester) async {
      final (_, _, editor) = await setup(tester);
      final scene = find.byKey(const ValueKey('container-3d-scene'));
      final yaw = editor.scene.yaw;
      await tester.drag(scene, const Offset(100, 60));
      await tester.pumpAndSettle();
      expect(editor.scene.panX, greaterThan(0));
      expect(editor.scene.panY, greaterThan(0));
      expect(editor.scene.yaw, yaw);
      final x = editor.scene.panX;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.drag(scene, const Offset(100, 0));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(editor.scene.yaw, isNot(yaw));
      expect(editor.scene.panX, x);
      await finish(tester);
    },
  );
  testWidgets('sidebar selects container and keeps only one save action', (
    tester,
  ) async {
    final (_, _, editor) = await setup(tester);
    expect(find.byKey(const ValueKey('container-3d-scene')), findsOneWidget);
    expect(find.text('未分配长度：300 mm'), findsOneWidget);
    expect(find.text('加入装柜方案'), findsNothing);
    expect(find.text('保存方案'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('preset-container-20gp')));
    await tester.pumpAndSettle();
    expect(editor.sections, hasLength(2));
    expect(editor.scene.container.lengthMm, 5800);
    await finish(tester);
  });
  testWidgets('cargo drag focuses row input and auto pack respects 12 x 22', (
    tester,
  ) async {
    final (_, _, editor) = await setup(tester);
    final source = find.byKey(const ValueKey('cargo-drag-cargo-wpc-grille'));
    final target = find.byKey(const ValueKey('section-drop-0'));
    await tester.dragFrom(
      tester.getCenter(source),
      tester.getCenter(target) - tester.getCenter(source),
    );
    await tester.pumpAndSettle();
    expect(editor.entries, hasLength(1));
    expect(editor.entries.single.quantity, 286);
    final entry = editor.entries.single;
    await tester.enterText(find.byKey(ValueKey('per-row-${entry.id}')), '12');
    expect(find.text('自动装柜'), findsNothing);
    await tester.pumpAndSettle();
    expect(editor.packedCount, 264);
    expect(editor.entries.single.quantity, 264);
    await tester.tap(find.text('摆放设置'));
    await tester.pumpAndSettle();
    expect(find.text('靠左'), findsOneWidget);
    expect(find.text('允许堆叠'), findsOneWidget);
    await finish(tester);
  });
  testWidgets('recent plans collapse to five and expand on demand', (
    tester,
  ) async {
    final (_, container, _) = await setup(tester);
    final repo = container.read(containerLoadingRepositoryProvider);
    final preset = container.read(containerPresetsProvider).requireValue.first;
    for (var i = 0; i < 7; i++) {
      await tester.runAsync(
        () => repo.createPlan(name: 'Plan-$i', container: preset),
      );
    }
    await tester.pumpAndSettle();
    expect(find.text('Plan-0'), findsNothing);
    expect(find.text('Plan-6'), findsOneWidget);
    await tester.tap(find.text('更多 >'));
    await tester.pumpAndSettle();
    expect(find.text('Plan-0'), findsOneWidget);
    await finish(tester);
  });
  testWidgets('override is confirmed once and retained on subsequent packing', (
    tester,
  ) async {
    final (_, container, editor) = await setup(tester);
    final cargo = container
        .read(cargoLibraryProvider)
        .requireValue
        .firstWhere((c) => c.id == 'cargo-wpc-grille');
    editor.addCargo(editor.sections.first.id, cargo);
    editor.updateEntry(editor.entries.single.copyWith(quantity: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('review-unpacked')));
    await tester.pumpAndSettle();
    expect(find.text('确认保留未装数量'), findsOneWidget);
    await tester.tap(find.text('确认保留未装数量'));
    await tester.pumpAndSettle();
    expect(editor.entries.single.manualQuantityOverride, true);
    expect(editor.entries.single.quantity, 300);
    expect(editor.packedCount, 286);
    editor.pack(editor.sections.first.id);
    await tester.pumpAndSettle();
    expect(find.text('仍按300继续'), findsNothing);
    await finish(tester);
  });
}
