import 'package:drift/native.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/tools/container_loading/data/container_loading_repository.dart';
import 'package:fly/features/tools/container_loading/domain/models/container_loading_models.dart';
import 'package:fly/features/tools/container_loading/domain/models/section_models.dart';
import 'package:fly/features/tools/container_loading/presentation/loading_editor_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'container_loading_v2_test.dart' as f;
import 'container_loading_v3_test.dart' as v3;

void main() {
  for (final rows in [6, 3]) {
    test('V5 partial grid $rows x 18 exposes disjoint recursive spaces', () {
      final base = f.entry(
        f.pallet,
        1,
        bottom: true,
        position: HorizontalPlacement.left,
      );
      final roots = f.pack([base]).spaces;
      final wpc = f
          .entry(f.wpc, rows * 18)
          .copyWith(spaceId: roots[0].id, perRow: rows, rowCount: 18);
      final pvc = f
          .entry(v3.pvc, 40)
          .copyWith(spaceId: roots[1].id, perRow: 4, rowCount: 10);
      final result = f.pack([base, wpc, pvc]);
      expect(result.packedByEntry[wpc.id], rows * 18);
      expect(result.packedByEntry[pvc.id], 40);
      f.valid(result, f.section);
      final free = result.spaces.where((s) => s.parentId != null).toList();
      final top = free.where((s) => s.name.contains('上方')).toList();
      expect(top.length, 2);
      expect(top[0].name.startsWith('03'), true);
      expect(top[1].name.startsWith('04'), true);
      expect(top.first.bounds.dimensions, Dimensions3(2900, rows * 160, 530));
      if (rows == 3) {
        expect(
          free.any(
            (s) =>
                s.parentId == roots[0].id &&
                s.bounds.dimensions.widthMm == 520 &&
                s.bounds.z == 0,
          ),
          true,
        );
      }
      for (var i = 0; i < free.length; i++) {
        expect(free[i].bounds.inside(f.box), true);
        expect(
          result.groups.any((g) => g.bounds.overlaps(free[i].bounds)),
          false,
        );
        for (var j = i + 1; j < free.length; j++) {
          expect(free[i].bounds.overlaps(free[j].bounds), false);
        }
      }
      final child = f
          .entry(v3.pvc, 2, id: 'child')
          .copyWith(spaceId: top.first.id, perRow: 2, rowCount: 1);
      final filled = f.pack([base, wpc, pvc, child]);
      expect(filled.packedByEntry['child'], 2);
      expect(filled.spaces.any((s) => s.parentId == top.first.id), true);
      f.valid(filled, f.section);
      final changed = f.pack([
        base,
        wpc.copyWith(quantity: rows * 17, rowCount: 17),
        pvc,
        child,
      ]);
      expect(changed.packedByEntry['child'], 0);
      expect(changed.requestedByEntry['child'], 2);
    });
  }
  test(
    'V5 cargo colors and recursive assignments survive save and reopen',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureBuiltInData();
      final repo = DriftContainerLoadingRepository(db);
      await repo.saveCargo(f.pallet);
      await repo.saveCargo(f.wpc);
      await repo.saveCargo(v3.pvc);
      final editor = LoadingEditorController(repo);
      addTearDown(editor.dispose);
      final section = editor.sections.first.id;
      editor.addCargo(section, f.pallet);
      editor.updateEntry(
        editor.entries.single.copyWith(
          quantity: 1,
          horizontalPlacement: HorizontalPlacement.left,
        ),
      );
      final roots = editor.spacesFor(section);
      editor.addCargo(section, f.wpc, spaceId: roots[0].id);
      editor.updateEntry(
        editor.entries.last.copyWith(perRow: 3, rowCount: 18, quantity: 54),
      );
      editor.addCargo(section, v3.pvc, spaceId: roots[1].id);
      editor.updateEntry(
        editor.entries.last.copyWith(perRow: 4, rowCount: 10, quantity: 40),
      );
      expect(
        editor.entries[1].colorValue != editor.entries[2].colorValue,
        true,
      );
      final top = editor
          .spacesFor(section)
          .firstWhere(
            (s) => s.parentId == roots[0].id && s.name.contains('上方'),
          );
      editor.addCargo(section, v3.pvc, spaceId: top.id);
      expect(editor.entries[2].colorValue, editor.entries[3].colorValue);
      final before = editor.packedCount;
      await editor.save('Recursive spaces');
      await editor.open(editor.plan!.id, await repo.watchPresets().first);
      expect(editor.entries[1].quantity, 54);
      expect(editor.entries[2].quantity, 40);
      expect(editor.entries[3].spaceId, top.id);
      expect(editor.packedCount, before);
      for (final g in editor.scene.groups) {
        expect(
          g.colorValue,
          editor.entries.firstWhere((e) => e.id == g.entryId).colorValue,
        );
      }
      editor.pack(section);
      expect(editor.packedCount, before);
    },
  );
}
