import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/tasks/presentation/task_providers.dart';
import '../data/container_loading_repository.dart';
import '../domain/models/container_loading_models.dart';
import 'loading_editor_controller.dart';

final loadingEditorProvider = ChangeNotifierProvider<LoadingEditorController>((
  ref,
) {
  final editor = LoadingEditorController(
    ref.watch(containerLoadingRepositoryProvider),
  );
  ref.listen(containerPresetsProvider, (_, next) {
    final preset = next.valueOrNull
        ?.where((p) => p.id == editor.preset.id)
        .firstOrNull;
    if (preset != null) editor.syncPreset(preset);
  });
  return editor;
});

final containerLoadingRepositoryProvider = Provider<ContainerLoadingRepository>(
  (ref) => DriftContainerLoadingRepository(ref.watch(databaseProvider)),
);

final containerPresetsProvider = StreamProvider<List<ContainerPresetModel>>(
  (ref) => ref.watch(containerLoadingRepositoryProvider).watchPresets(),
);

final cargoLibraryProvider = StreamProvider<List<CargoPackageModel>>(
  (ref) => ref.watch(containerLoadingRepositoryProvider).watchCargoLibrary(),
);

final loadingPlansProvider = StreamProvider<List<LoadingPlanModel>>(
  (ref) => ref.watch(containerLoadingRepositoryProvider).watchPlans(),
);

final selectedLoadingPlanIdProvider = StateProvider<String?>((ref) => null);

final loadingPlanGroupsProvider =
    StreamProvider.family<List<CargoGroupModel>, String>(
      (ref, id) =>
          ref.watch(containerLoadingRepositoryProvider).watchGroups(id),
    );
