import '../../../l10n/service_error_copy.dart';
import '../../../l10n/tools_copy.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/design_system/fly_color_scheme.dart';
import '../../../l10n/fly_localizations.dart';
import '../container_loading/domain/models/container_loading_models.dart';
import '../container_loading/presentation/container_loading_providers.dart';
import '../container_loading/presentation/workspace/library_editors.dart';

class ToolsSidebar extends ConsumerStatefulWidget {
  const ToolsSidebar({super.key});
  @override
  ConsumerState<ToolsSidebar> createState() => _ToolsSidebarState();
}

class _ToolsSidebarState extends ConsumerState<ToolsSidebar> {
  bool allPlans = false;
  Future<bool> _discard() async =>
      !ref.read(loadingEditorProvider).dirty ||
      await confirmLoadingAction(
        context,
        context.toolsCopy('当前方案有未保存的修改。确定切换并放弃这些修改？'),
        action: context.toolsCopy('切换'),
      );
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.l10n.isZh ? '操作失败' : 'Operation failed'}: ${context.flyError(e)}',
            ),
          ),
        );
      }
    }
  }

  void _navigate() {
    if (mounted) context.go('/tools/container-loading');
  }

  Future<void> _editPreset([ContainerPresetModel? preset]) async {
    final value = await showDialog<ContainerPresetModel>(
      context: context,
      builder: (_) => ContainerPresetEditor(preset: preset),
    );
    if (value != null) {
      await _guard(() async {
        await ref.read(containerLoadingRepositoryProvider).savePreset(value);
      });
    }
  }

  Future<void> _editCargo([
    CargoPackageModel? cargo,
    bool duplicate = false,
  ]) async {
    final value = await showDialog<CargoPackageModel>(
      context: context,
      builder: (_) => CargoLibraryEditor(cargo: cargo, duplicate: duplicate),
    );
    if (value != null) {
      await _guard(() async {
        await ref.read(containerLoadingRepositoryProvider).saveCargo(value);
      });
    }
  }

  Future<void> _open(LoadingPlanModel plan) async {
    if (!await _discard() || !mounted) return;
    await _guard(() async {
      await ref
          .read(loadingEditorProvider)
          .open(plan.id, ref.read(containerPresetsProvider).valueOrNull ?? []);
      ref.read(selectedLoadingPlanIdProvider.notifier).state = plan.id;
      _navigate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(loadingEditorProvider);
    final presets = ref.watch(containerPresetsProvider).valueOrNull ?? [];
    final plans = ref.watch(loadingPlansProvider).valueOrNull ?? [];
    final cargo = ref.watch(cargoLibraryProvider).valueOrNull ?? [];
    return Material(
      key: const ValueKey('tools-secondary-sidebar'),
      color: context.flyColors.secondarySidebar,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                context.l10n.t('tools'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            _SideRow(
              label: context.l10n.t('containerLoading'),
              icon: Icons.view_in_ar_outlined,
              selected: true,
              onTap: _navigate,
            ),
            _heading(context.toolsCopy('集装箱')),
            for (final preset in presets)
              _SideRow(
                key: ValueKey('preset-${preset.id}'),
                label: preset.name,
                icon: Icons.inventory_2_outlined,
                selected: editor.preset.id == preset.id,
                onTap: () async {
                  if (!await _discard() || !mounted) return;
                  editor.choosePreset(preset);
                  ref.read(selectedLoadingPlanIdProvider.notifier).state = null;
                  _navigate();
                },
                actions: {
                  context.toolsCopy('编辑尺寸'): () => _editPreset(preset),
                  if (preset.isBuiltIn)
                    context.toolsCopy('恢复默认值'): () async {
                      if (!await confirmLoadingAction(
                            context,
                            context.l10n.isZh
                                ? '恢复 ${preset.name} 的默认尺寸和载重？'
                                : 'Restore the default dimensions and payload for ${preset.name}?',
                          ) ||
                          !mounted) {
                        return;
                      }
                      final hq = preset.id == 'container-40hq';
                      await _guard(
                        () => ref
                            .read(containerLoadingRepositoryProvider)
                            .savePreset(
                              ContainerPresetModel(
                                id: preset.id,
                                name: hq ? '40HQ' : '20GP',
                                dimensions: hq
                                    ? const Dimensions3(11900, 2200, 2690)
                                    : const Dimensions3(5800, 2200, 2320),
                                maxPayloadGrams: 28000000,
                                colorValue: preset.colorValue,
                                isBuiltIn: true,
                              ),
                            ),
                      );
                    },
                },
              ),
            _add(context.toolsCopy('添加集装箱'), () => _editPreset()),
            _heading(context.toolsCopy('保存的方案')),
            if (plans.isEmpty)
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  context.toolsCopy('暂无保存方案'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            for (final plan in allPlans ? plans : plans.take(5))
              _SideRow(
                label: plan.name,
                icon: Icons.description_outlined,
                selected: editor.plan?.id == plan.id,
                onTap: () => _open(plan),
                actions: {
                  context.toolsCopy('打开方案'): () => _open(plan),
                  context.toolsCopy('编辑方案'): () => _open(plan),
                  context.toolsCopy('重命名'): () async {
                    final name = await loadingNameDialog(
                      context,
                      context.toolsCopy('重命名方案'),
                      plan.name,
                    );
                    if (name != null && name.trim().isNotEmpty) {
                      await _guard(
                        () => ref
                            .read(loadingEditorProvider)
                            .rename(plan.id, name),
                      );
                    }
                  },
                  context.toolsCopy('删除方案'): () async {
                    if (!await confirmLoadingAction(
                          context,
                          context.l10n.isZh
                              ? '确定删除装柜方案“${plan.name}”？'
                              : 'Delete loading plan “${plan.name}”?',
                          action: context.toolsCopy('删除'),
                        ) ||
                        !mounted) {
                      return;
                    }
                    await _guard(
                      () => ref
                          .read(containerLoadingRepositoryProvider)
                          .deletePlan(plan.id),
                    );
                    if (editor.plan?.id == plan.id) {
                      editor.choosePreset(editor.preset);
                      ref.read(selectedLoadingPlanIdProvider.notifier).state =
                          null;
                    }
                  },
                },
              ),
            if (plans.length > 5)
              TextButton(
                onPressed: () => setState(() => allPlans = !allPlans),
                child: Text(
                  allPlans
                      ? context.toolsCopy('收起')
                      : context.toolsCopy('更多 >'),
                ),
              ),
            _heading(context.toolsCopy('货物')),
            for (final item in cargo)
              Draggable<CargoPackageModel>(
                data: item,
                feedback: Material(
                  elevation: 5,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inventory_2,
                          color: Color(item.colorValue),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(item.name),
                      ],
                    ),
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: .35,
                  child: Text(item.name),
                ),
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: _SideRow(
                    key: ValueKey('cargo-drag-${item.id}'),
                    label: item.name,
                    icon: item.type == CargoPackageType.pallet
                        ? Icons.pallet
                        : Icons.view_in_ar,
                    color: Color(item.colorValue),
                    onTap: () => _editCargo(item),
                    actions: {
                      context.toolsCopy('编辑'): () => _editCargo(item),
                      context.toolsCopy('复制规格'): () => _editCargo(item, true),
                      context.toolsCopy('删除'): () async {
                        if (!await confirmLoadingAction(
                              context,
                              context.l10n.isZh
                                  ? '从货物库删除“${item.name}”？已保存方案中的规格会保留。'
                                  : 'Delete “${item.name}” from the cargo library? Specifications in saved plans will be retained.',
                              action: context.toolsCopy('删除'),
                            ) ||
                            !mounted) {
                          return;
                        }
                        await _guard(
                          () => ref
                              .read(containerLoadingRepositoryProvider)
                              .deleteCargo(item.id),
                        );
                      },
                    },
                  ),
                ),
              ),
            _add(context.toolsCopy('添加货物'), () => _editCargo()),
          ],
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 20, 4, 7),
    child: Text(text, style: Theme.of(context).textTheme.labelSmall),
  );
  Widget _add(String text, VoidCallback action) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: action,
      icon: const Icon(Icons.add, size: 15),
      label: Text(text),
    ),
  );
}

class _SideRow extends StatelessWidget {
  const _SideRow({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.color,
    this.actions = const {},
    super.key,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final Color? color;
  final Map<String, VoidCallback> actions;
  Future<void> _menu(BuildContext context, Offset position) async {
    if (actions.isEmpty) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        for (final name in actions.keys)
          PopupMenuItem(value: name, child: Text(name)),
      ],
    );
    if (choice != null) actions[choice]?.call();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
    child: ListTile(
      dense: true,
      minTileHeight: 36,
      contentPadding: const EdgeInsets.only(left: 10),
      selected: selected,
      selectedTileColor: context.flyColors.selected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      leading: Icon(icon, size: 17, color: color),
      minLeadingWidth: 17,
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      onTap: onTap,
      trailing: actions.isEmpty
          ? null
          : PopupMenuButton<String>(
              tooltip: context.toolsCopy('更多'),
              icon: const Icon(Icons.more_horiz, size: 16),
              itemBuilder: (_) => [
                for (final name in actions.keys)
                  PopupMenuItem(value: name, child: Text(name)),
              ],
              onSelected: (value) => actions[value]?.call(),
            ),
    ),
  );
}
