import 'package:fly/features/tools/container_loading/domain/models/container_loading_models.dart';
import 'package:fly/features/tools/container_loading/presentation/scene/container_scene_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CargoGroupModel group(String id, int x) => CargoGroupModel(
    id: id,
    planId: 'plan',
    cargoPackageId: 'cargo',
    quantity: 1,
    rows: 1,
    columns: 1,
    layers: 1,
    emptySlots: 0,
    boundingDimensions: const Dimensions3(100, 100, 100),
    positionXmm: x,
    positionYmm: 0,
    positionZmm: 0,
    rotationX: 0,
    rotationY: 0,
    rotationZ: 0,
    colorValue: 0xFF79A88C,
    sortOrder: 0,
    sectionId: 'section',
  );

  test('valid drag snaps and undo restores the previous position', () {
    final controller = NativeContainerSceneController(
      initialContainer: const Dimensions3(1000, 500, 500),
      initialGroups: [group('a', 0)],
      gridSnapMm: 50,
    );
    addTearDown(controller.dispose);
    controller.beginMove('a');
    controller.previewMove(224, 0, 0);
    controller.endMove();
    expect(controller.groups.single.positionXmm, 200);
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(controller.groups.single.positionXmm, 0);
    controller.redo();
    expect(controller.groups.single.positionXmm, 200);
  });

  test('overlap is rejected and dragging outside stages cargo', () {
    final controller = NativeContainerSceneController(
      initialContainer: const Dimensions3(1000, 500, 500),
      initialGroups: [group('a', 0), group('b', 200)],
      gridSnapMm: 50,
    );
    addTearDown(controller.dispose);
    controller.beginMove('a');
    controller.previewMove(200, 0, 0);
    expect(controller.invalidGroupId, 'a');
    controller.endMove();
    expect(controller.groups.first.positionXmm, 0);

    controller.beginMove('a');
    controller.previewMove(-200, 0, 0);
    controller.endMove();
    expect(controller.groups.first.positionXmm, -200);
    expect(controller.groups.first.sectionId, isNull);
    expect(controller.groups.first.needsReview, isTrue);
  });

  test(
    'orthogonal rotation permutes dimensions without escaping container',
    () {
      final controller = NativeContainerSceneController(
        initialContainer: const Dimensions3(1000, 500, 500),
        initialGroups: [
          group(
            'a',
            0,
          ).copyWith(boundingDimensions: const Dimensions3(300, 100, 200)),
        ],
      );
      addTearDown(controller.dispose);
      controller.select('a');
      controller.rotateSelectedZ();
      expect(
        controller.groups.single.boundingDimensions,
        const Dimensions3(100, 300, 200),
      );
      expect(controller.groups.single.rotationZ, 90);
    },
  );
}
