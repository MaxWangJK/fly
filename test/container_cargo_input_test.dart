import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/tools/container_loading/data/container_loading_repository.dart';
import 'package:fly/features/tools/container_loading/presentation/loading_editor_controller.dart';

import 'container_actual_spaces_test.dart' as f;

void main() {
  test('three PVC groups 80+16+4 keep the first and third when the middle input is cleared and removed', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final editor = LoadingEditorController(DriftContainerLoadingRepository(db));
    try {
      await db.ensureBuiltInData();
      final section = editor.sections.first.id;
      editor.addCargo(section, f.pvc);
      final first = editor.scene.groups.single;
      editor.scene.resizeGroup(first.id, rows: 8, layers: 10);
      editor.addCargo(
        section,
        f.pvc,
        spaceId: editor
            .spacesFor(section)
            .firstWhere((s) => s.bounds.z == 1000)
            .id,
      );
      final second = editor.scene.groups.last;
      editor.scene.resizeGroup(second.id, rows: 8, layers: 2);
      editor.addCargo(
        section,
        f.pvc,
        spaceId: editor
            .spacesFor(section)
            .firstWhere((s) => s.bounds.z == 1200)
            .id,
      );
      final third = editor.scene.groups.last;
      editor.scene.resizeGroup(third.id, rows: 4, layers: 1);
      expect(editor.packedCount, 100);
      editor.scene.resizeGroup(second.id, rows: 0, layers: 0);
      expect((editor.packedCount, editor.requestedCount), (84, 84));
      expect(editor.scene.loadedGroups.map((g) => g.id), [first.id, third.id]);
      editor.removeCargoGroup(second.id);
      expect(editor.scene.groups.map((g) => g.id), [first.id, third.id]);
      expect(editor.scene.groups.map((g) => (g.quantity, g.positionZmm)), [
        (80, 0),
        (4, 1200),
      ]);
      expect(
        editor.entries.singleWhere((e) => e.id == third.entryId).quantity,
        4,
      );
    } finally {
      editor.dispose();
      await db.close();
    }
  });
  test('clearing a second PVC group updates counts, spaces and saved drafts; refill and remove are undoable', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = DriftContainerLoadingRepository(db);
    final editor = LoadingEditorController(repo);
    try {
      await db.ensureBuiltInData();
      await repo.saveCargo(f.pvc);
      final section = editor.sections.first.id;
      final firstEntry = editor.addCargo(section, f.pvc);
      final first = editor.scene.groups.single;
      editor.scene.resizeGroup(first.id, rows: 8, layers: 10);
      final top = editor
          .spacesFor(section)
          .firstWhere((s) => s.bounds.z == 1000);
      final secondEntry = editor.addCargo(section, f.pvc, spaceId: top.id);
      final second = editor.scene.groups.last;
      editor.scene.resizeGroup(second.id, rows: 8, layers: 2);
      expect(editor.packedCount, 96);
      expect(
        editor.entries.singleWhere((e) => e.id == secondEntry).quantity,
        16,
      );
      editor.scene.resizeGroup(second.id, rows: 0, layers: 2);
      expect(editor.scene.groups.last.quantity, 0);
      expect(editor.scene.loadedGroups.map((g) => g.id), [first.id]);
      expect((editor.packedCount, editor.requestedCount), (80, 80));
      expect(
        editor.entries.singleWhere((e) => e.id == secondEntry).quantity,
        0,
      );
      expect(editor.spacesFor(section).map((s) => s.id), contains(top.id));
      await editor.save('Empty second group');
      await editor.open(editor.plan!.id, await repo.watchPresets().first);
      expect(editor.manuallyAdjustedSections, contains(section));
      expect(editor.scene.groups.last.quantity, 0);
      expect((editor.packedCount, editor.requestedCount), (80, 80));
      editor.scene.resizeGroup(second.id, rows: 4, layers: 1);
      expect((editor.packedCount, editor.requestedCount), (84, 84));
      expect(
        editor.scene.groups.firstWhere((g) => g.id == first.id).quantity,
        80,
      );
      editor.removeCargoGroup(second.id);
      expect(editor.scene.groups.map((g) => g.id), [first.id]);
      expect(
        editor.entries.singleWhere((e) => e.id == secondEntry).quantity,
        0,
      );
      expect(
        editor.entries.singleWhere((e) => e.id == firstEntry).quantity,
        80,
      );
      editor.scene.undo();
      expect(editor.scene.groups.last.quantity, 4);
      expect(
        editor.entries.singleWhere((e) => e.id == secondEntry).quantity,
        4,
      );
      editor.scene.redo();
      await editor.save('Removed second group');
      await editor.open(editor.plan!.id, await repo.watchPresets().first);
      expect(editor.packedCount, 80);
      expect(editor.scene.groups.map((g) => g.id), [first.id]);
      editor.pack(section);
      expect(editor.packedCount, 80);
      expect(editor.packedFor(secondEntry), 0);
      expect(
        (await repo.watchCargoLibrary().first).any((c) => c.id == f.pvc.id),
        isTrue,
      );
    } finally {
      editor.dispose();
      await db.close();
    }
  });

  test('zero drafts do not block placement, and refilling checks the new live geometry', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final editor = LoadingEditorController(DriftContainerLoadingRepository(db));
    try {
      await db.ensureBuiltInData();
      final section = editor.sections.first.id;
      editor.addCargo(section, f.pvc);
      final first = editor.scene.groups.single;
      editor.scene.resizeGroup(first.id, rows: 8, layers: 10);
      final top = editor
          .spacesFor(section)
          .firstWhere((s) => s.bounds.z == 1000);
      editor.addCargo(section, f.pvc, spaceId: top.id);
      final pending = editor.scene.groups.last;
      editor.scene.resizeGroup(pending.id, rows: 0, layers: 0);
      final replacement = editor.addCargo(section, f.pvc, spaceId: top.id);
      final active = editor.scene.groups.singleWhere(
        (g) => g.entryId == replacement,
      );
      expect(editor.scene.hasPlacementConflict(active), isFalse);
      expect(editor.scene.loadedGroups.length, 2);
      expect(editor.scene.resizeGroup(pending.id, rows: 1, layers: 1), isTrue);
      expect(
        editor.scene.hasPlacementConflict(
          editor.scene.groups.singleWhere((g) => g.id == pending.id),
        ),
        isTrue,
      );
      expect(editor.scene.loadedGroups.length, 3);
    } finally {
      editor.dispose();
      await db.close();
    }
  });

  test('clearing and removing staged cargo leaves no loaded or requested ghost counts', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final editor = LoadingEditorController(DriftContainerLoadingRepository(db));
    try {
      await db.ensureBuiltInData();
      final section = editor.sections.first.id;
      final entry = editor.addCargo(section, f.pvc, stage: true);
      final group = editor.scene.groups.single;
      editor.scene.resizeGroup(group.id, rows: 4, layers: 2);
      expect((editor.packedCount, editor.requestedCount), (0, 8));
      editor.scene.resizeGroup(group.id, rows: 0, layers: 2);
      expect(editor.scene.loadedGroups, isEmpty);
      expect((editor.packedCount, editor.requestedCount), (0, 0));
      editor.removeCargoGroup(group.id);
      expect(editor.scene.groups, isEmpty);
      expect(editor.entries.singleWhere((e) => e.id == entry).quantity, 0);
      editor.scene.undo();
      expect(editor.scene.groups.single.quantity, 0);
      editor.scene.resizeGroup(group.id, rows: 2, layers: 2);
      expect((editor.packedCount, editor.requestedCount), (0, 4));
    } finally {
      editor.dispose();
      await db.close();
    }
  });
}
