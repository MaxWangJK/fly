import '../../../../../l10n/service_error_copy.dart';
import '../../../../../l10n/tools_copy.dart';

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../shared/design_system/fly_color_scheme.dart';
import '../../../../../l10n/fly_localizations.dart';
import '../../domain/models/container_loading_models.dart';
import '../../domain/models/section_models.dart';
import '../container_loading_providers.dart';
import '../loading_editor_controller.dart';
import '../scene/container_scene_controller.dart';
import '../scene/container_scene_view.dart';
import '../scene/section_placement_editor.dart';
import 'library_editors.dart';

class ContainerLoadingPage extends ConsumerStatefulWidget {
  const ContainerLoadingPage({super.key});
  @override
  ConsumerState<ContainerLoadingPage> createState() =>
      _ContainerLoadingPageState();
}

class _ContainerLoadingPageState extends ConsumerState<ContainerLoadingPage> {
  final boundary = GlobalKey();
  String? focusEntryId;
  bool _crossSectionOpen = true;
  int _dismissedArrivalRevision = -1;
  Future<void> _pack(ContainerSection section) async {
    final editor = ref.read(loadingEditorProvider);
    if (editor.manuallyAdjustedSections.contains(section.id)) {
      if (!await confirmLoadingAction(
            context,
            context.toolsCopy('重新自动装柜将覆盖本节的手动位置。'),
            action: context.toolsCopy('重新计算'),
          ) ||
          !mounted) {
        return;
      }
    }
    for (final entry
        in editor.entries.where((e) => e.sectionId == section.id).toList()) {
      final capacity = editor.capacityFor(entry);
      if (entry.quantity > capacity && !entry.manualQuantityOverride) {
        final accepted = await confirmLoadingAction(
          context,
          context.l10n.isZh
              ? '${entry.cargo.name}：当前数量超过系统根据尺寸计算的理论容量。\n系统计算：$capacity\n用户设置：${entry.quantity}\n确认后保留设置数量；未能按尺寸摆放的部分会单独标记。'
              : '${entry.cargo.name}: requested quantity exceeds dimensional capacity.\nCalculated: $capacity\nRequested: ${entry.quantity}\nYour requested quantity will be retained; cargo that does not fit will be marked separately.',
          action: (context.l10n.isZh
              ? '仍按${entry.quantity}继续'
              : 'Continue with ${entry.quantity}'),
        );
        if (!mounted) return;
        if (!accepted) {
          setState(() => focusEntryId = entry.id);
          return;
        }
        editor.updateEntry(entry.copyWith(manualQuantityOverride: true));
      }
    }
    try {
      editor.pack(section.id);
    } catch (e) {
      _message(context.flyError(e));
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(text),
            behavior: SnackBarBehavior.floating,
            // Keep the persistent review/save controls clickable after feedback.
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          ),
        );
    }
  }

  Future<void> _save() async {
    final editor = ref.read(loadingEditorProvider);
    final name = await loadingNameDialog(
      context,
      context.toolsCopy('保存方案'),
      editor.plan?.name ?? '',
    );
    if (name == null || !mounted) return;
    try {
      await editor.save(name);
      if (!mounted) return;
      ref.read(selectedLoadingPlanIdProvider.notifier).state = editor.plan?.id;
      _message(context.toolsCopy('方案已保存'));
    } catch (e) {
      if (!mounted) return;
      _message(
        (context.l10n.isZh
            ? '保存失败：${context.flyError(e)}'
            : 'Save failed: ${context.flyError(e)}'),
      );
    }
  }

  Future<void> _reviewUnpacked() async {
    final e = ref.read(loadingEditorProvider);
    final pending = e.entries
        .where(
          (entry) =>
              e.packedFor(entry.id) < entry.quantity ||
              e.needsPacking.contains(entry.sectionId),
        )
        .toList();
    final stale = pending.any(
      (entry) => e.needsPacking.contains(entry.sectionId),
    );
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.toolsCopy('未装货物处理')),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in pending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '${context.toolsSpaceName(e.sections.firstWhere((s) => s.id == entry.sectionId).name)} · ${entry.cargo.name}\n'
                      '${context.l10n.isZh ? '设置' : 'Requested'} ${entry.quantity} · ${context.l10n.isZh ? '已摆放' : 'Placed'} ${e.packedFor(entry.id)} · ${context.l10n.isZh ? '未装' : 'Unloaded'} ${math.max(0, entry.quantity - e.packedFor(entry.id))}'
                      '${e.needsPacking.contains(entry.sectionId) ? (context.l10n.isZh ? '\n设置已更改，请先重新计算。' : '\nSettings changed. Recalculate first.') : ''}',
                    ),
                  ),
                Text(
                  stale
                      ? context.toolsCopy('先计算待更新分节，再确认实际未装数量。不会自动修改您的设置数量。')
                      : context.toolsCopy(
                          '未装货物仍在计划中，但没有计入 3D 已装数量。可返回调整数量、尺寸、间距或分节；也可确认保留，安排其他柜次。确认不会强行把货物放入柜内。',
                        ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'adjust'),
            child: Text(context.toolsCopy('返回调整')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, stale ? 'pack' : 'confirm'),
            child: Text(
              stale
                  ? context.toolsCopy('计算待更新分节')
                  : context.toolsCopy('确认保留未装数量'),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'pack') {
      for (final section
          in e.sections
              .where(
                (s) =>
                    e.needsPacking.contains(s.id) &&
                    e.entries.any((v) => v.sectionId == s.id),
              )
              .toList()) {
        await _pack(section);
        if (!mounted || e.needsPacking.contains(section.id)) return;
      }
      if (e.packedCount < e.requestedCount) await _reviewUnpacked();
    } else if (action == 'confirm') {
      e.acknowledgeUnpacked();
      _message(context.toolsCopy('已确认保留未装数量，请保存方案'));
    } else if (action == 'adjust' && pending.isNotEmpty) {
      e.focusSection(pending.first.sectionId);
      setState(() => focusEntryId = pending.first.id);
    }
  }

  Future<void> _screenshot() async {
    try {
      final target = await getSaveLocation(
        suggestedName: context.l10n.isZh
            ? 'Fly-装柜方案.png'
            : 'Fly-Loading-Plan.png',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'PNG', extensions: ['png']),
        ],
      );
      if (target == null || !mounted) return;
      final render =
          boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (render == null) return;
      final image = await render.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes != null) {
        await File(target.path).writeAsBytes(bytes.buffer.asUint8List());
        if (!mounted) return;
        _message(context.toolsCopy('截图已导出'));
      }
    } catch (e) {
      if (!mounted) return;
      _message(
        (context.l10n.isZh
            ? '截图导出失败：${context.flyError(e)}'
            : 'Screenshot export failed: ${context.flyError(e)}'),
      );
    }
  }

  Future<void> _copy() async {
    final e = ref.read(loadingEditorProvider);
    final text = StringBuffer(
      '${e.preset.name} · ${e.sections.length} ${context.l10n.isZh ? '节' : 'sections'}\n',
    );
    for (final s in e.sections) {
      text.writeln(
        '${context.toolsSpaceName(s.name)} ${(s.lengthMm / 1000).toStringAsFixed(2)}m',
      );
      for (final c in e.entries.where((c) => c.sectionId == s.id)) {
        text.writeln(
          '  ${c.cargo.name} ${context.l10n.isZh ? '设置' : 'Requested'} ${c.quantity} / ${context.l10n.isZh ? '已摆放' : 'Placed'} ${e.packedFor(c.id)}${c.manualQuantityOverride ? (context.l10n.isZh ? ' · 用户覆盖理论容量' : ' · Capacity overridden') : ''}',
        );
      }
    }
    text.writeln(
      '${context.l10n.isZh ? '总重量' : 'Total weight'} ${(e.totalWeightGrams / 1000).toStringAsFixed(1)} kg\n${context.l10n.isZh ? '未分配长度' : 'Unallocated length'} ${e.unallocatedMm} mm',
    );
    await Clipboard.setData(ClipboardData(text: text.toString()));
    if (!mounted) return;
    _message(context.toolsCopy('已复制装柜结果'));
  }

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(loadingEditorProvider);
    final cargo = ref.watch(cargoLibraryProvider).valueOrNull ?? [];
    final names = {
      for (final c in cargo) c.id: c.name,
      for (final e in editor.entries) e.cargo.id: e.cargo.name,
    };
    final types = {
      for (final c in cargo) c.id: c.type,
      for (final e in editor.entries) e.cargo.id: e.cargo.type,
    };
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            editor.scene.undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            editor.scene.redo,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      },
      child: Focus(
        autofocus: true,
        child: ColoredBox(
          color: context.flyColors.canvas,
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                SizedBox(
                  width: constraints.maxWidth < 1000 ? 330 : 370,
                  child: _editor(editor, cargo),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
                    child: Column(
                      children: [
                        _toolbar(editor),
                        const SizedBox(height: 10),
                        Expanded(
                          child: RepaintBoundary(
                            key: boundary,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: ContainerSceneView(
                                    controller: editor.scene,
                                    cargoNames: names,
                                    cargoTypes: types,
                                  ),
                                ),
                                if (editor.scene.selectedGroupId != null)
                                  Positioned(
                                    top: 12,
                                    right: 12,
                                    child: _selection(editor, names),
                                  ),
                                Positioned(
                                  left: 12,
                                  bottom: 12,
                                  right: 12,
                                  child: Text(
                                    context.toolsCopy(
                                      '拖动空白平移 · Alt 拖动旋转 · 滚轮缩放 · Shift 拖动整体平移 · 拖动货物移动',
                                    ),
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          context.toolsCopy(
                            '仅供装柜规划参考，请结合实际箱体、包装变形、装柜间隙、门尺寸及当地重量规定确认。',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _editor(
    LoadingEditorController e,
    List<CargoPackageModel> cargo,
  ) => Material(
    color: context.flyColors.surface,
    child: Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            key: const ValueKey('loading-editor-scroll'),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  e.preset.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 5),
                Text(
                  '${(e.preset.dimensions.lengthMm / 1000).toStringAsFixed(2)} × ${(e.preset.dimensions.widthMm / 1000).toStringAsFixed(2)} × ${(e.preset.dimensions.heightMm / 1000).toStringAsFixed(2)} m',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Text(
                  (context.l10n.isZh
                      ? '最大货重 ${(e.maxPayloadGrams / 1000).toStringAsFixed(0)} kg · ${e.sections.length} Sections'
                      : 'Payload ${(e.maxPayloadGrams / 1000).toStringAsFixed(0)} kg · ${e.sections.length} sections'),
                ),
                const SizedBox(height: 12),
                Text(
                  context.toolsCopy('请在纸箱尺寸中自行计入预留量'),
                  style: TextStyle(fontSize: 11),
                ),
                PopupMenuButton<String>(
                  tooltip: context.l10n.t('cargoStageAdd'),
                  onSelected: (id) => e.addCargo(
                    e.selectedSectionId ?? e.sections.first.id,
                    cargo.firstWhere((c) => c.id == id),
                    stage: true,
                  ),
                  itemBuilder: (_) => [
                    for (final c in cargo)
                      PopupMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(context.l10n.t('cargoStageAdd')),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.toolsCopy('集装箱分节'),
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _editSections(e),
                      child: Text(context.toolsCopy('调整分节')),
                    ),
                  ],
                ),
                Text(
                  e.unallocatedMm >= 0
                      ? (context.l10n.isZh
                            ? '未分配长度：${e.unallocatedMm} mm'
                            : 'Unallocated: ${e.unallocatedMm} mm')
                      : (context.l10n.isZh
                            ? '超出箱体：${-e.unallocatedMm} mm'
                            : 'Exceeds container: ${-e.unallocatedMm} mm'),
                  style: TextStyle(
                    fontSize: 12,
                    color: e.unallocatedMm < 0
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
                if (e.validation != null)
                  Text(
                    e.validation!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 12),
                for (final s in e.sections) _section(e, s, cargo),
                const SizedBox(height: 8),
                _summary(e),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${context.l10n.isZh ? '已装' : 'Loaded'} ${e.packedCount} / ${e.requestedCount}${e.dirty ? (context.l10n.isZh ? ' · 未保存' : ' · Unsaved') : ''}',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (e.packedCount < e.requestedCount)
                    Expanded(
                      child: TextButton(
                        key: const ValueKey('review-unpacked'),
                        onPressed: e.busy ? null : _reviewUnpacked,
                        child: Text(
                          (context.l10n.isZh
                              ? '处理未装 ${math.max(0, e.requestedCount - e.packedCount)} 件'
                              : 'Review ${math.max(0, e.requestedCount - e.packedCount)} unloaded'),
                        ),
                      ),
                    ),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('save-loading-plan'),
                      onPressed: e.busy ? null : _save,
                      icon: const Icon(Icons.save_outlined, size: 16),
                      label: Text(context.toolsCopy('保存方案')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _section(
    LoadingEditorController e,
    ContainerSection section,
    List<CargoPackageModel> cargo,
  ) {
    final entries = e.entries.where((v) => v.sectionId == section.id).toList();
    final groups = e.scene.groups
        .where((g) => g.sectionId == section.id)
        .toList();
    final count = groups.fold(0, (a, g) => a + g.quantity);
    final manualGroups = groups;
    final requested = e.manuallyAdjustedSections.contains(section.id)
        ? manualGroups.fold<int>(0, (sum, g) => sum + g.quantity)
        : entries.fold(0, (a, c) => a + c.quantity);
    final weight = groups.fold(
      0,
      (a, g) =>
          a +
          g.quantity *
              (e.entries
                      .where((c) => c.id == g.entryId)
                      .firstOrNull
                      ?.cargo
                      .weightGrams ??
                  0),
    );
    final volume = groups.fold(
      0,
      (a, g) =>
          a +
          g.quantity *
              (e.entries
                      .where((c) => c.id == g.entryId)
                      .firstOrNull
                      ?.cargo
                      .dimensions
                      .volumeMm3 ??
                  0),
    );
    return DragTarget<CargoPackageModel>(
      key: ValueKey('section-drop-${section.index}'),
      onAcceptWithDetails: (d) =>
          setState(() => focusEntryId = e.addCargo(section.id, d.data)),
      builder: (context, candidates, rejected) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: candidates.isNotEmpty
              ? context.flyColors.selected
              : context.flyColors.surfaceMuted,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: candidates.isNotEmpty || e.selectedSectionId == section.id
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => e.focusSection(section.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '${context.toolsSpaceName(section.name)} · ${(section.lengthMm / 1000).toStringAsFixed(2)}m',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                if (groups.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      final wasCurrent = e.selectedSectionId == section.id;
                      e.focusSection(section.id);
                      setState(() {
                        final visible =
                            _crossSectionOpen ||
                            e.sectionArrivalRevision !=
                                _dismissedArrivalRevision;
                        _crossSectionOpen = !wasCurrent || !visible;
                        _dismissedArrivalRevision = e.sectionArrivalRevision;
                      });
                    },
                    child: Text(context.l10n.isZh ? '剖面' : 'Section'),
                  ),
                Text(context.toolsCopy('实时计算'), style: TextStyle(fontSize: 11)),
              ],
            ),
            if ((_crossSectionOpen ||
                    e.sectionArrivalRevision != _dismissedArrivalRevision) &&
                e.selectedSectionId == section.id &&
                groups.isNotEmpty)
              SizedBox(
                height: 240,
                child: SectionPlacementEditor(
                  controller: e.scene,
                  sectionId: section.id,
                  names: {for (final item in cargo) item.id: item.name},
                  spaces: e.spacesFor(section.id),
                  assignedSpaceIds: entries
                      .map((e) => e.spaceId)
                      .whereType<String>()
                      .toList(),
                ),
              ),
            for (final entry in entries.where(
              (v) =>
                  v.spaceId == null &&
                  !e.manuallyAdjustedSections.contains(section.id),
            ))
              _EntryEditor(
                key: ValueKey(entry.id),
                entry: entry,
                recommended: e.gridFor(entry),
                autoFocus: entry.id == focusEntryId,
                onChanged: e.updateEntry,
                onDelete: () => e.removeEntry(entry.id),
                capacity: e.capacityFor(entry),
              ),
            if (e.manuallyAdjustedSections.contains(section.id)) ...[
              Text(context.l10n.t('cargoManualMode')),
              for (final group in manualGroups)
                _ManualCargoEditor(
                  key: ValueKey('manual-${group.id}'),
                  group: group,
                  hasConflict: e.scene.hasPlacementConflict(group),
                  name:
                      cargo
                          .where((c) => c.id == group.cargoPackageId)
                          .firstOrNull
                          ?.name ??
                      group.cargoPackageId,
                  onSelect: () => e.scene.select(group.id),
                  onResize: (rows, layers) =>
                      e.scene.resizeGroup(group.id, rows: rows, layers: layers),
                ),
            ],
            if (groups.isNotEmpty ||
                entries.any((v) => v.isBase || v.spaceId != null))
              _spaces(e, section, cargo),
            PopupMenuButton<String>(
              tooltip: context.toolsCopy('选择货物'),
              onSelected: (id) => setState(
                () => focusEntryId = e.addCargo(
                  section.id,
                  cargo.firstWhere((c) => c.id == id),
                ),
              ),
              itemBuilder: (_) => [
                for (final c in cargo)
                  PopupMenuItem(value: c.id, child: Text(c.name)),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  candidates.isNotEmpty
                      ? context.toolsCopy('松开以添加货物')
                      : context.toolsCopy('+ 选择货物 / 拖放到本节'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            if (entries.isNotEmpty)
              Text(
                (context.l10n.isZh
                    ? '已装 $count · 未装 ${math.max(0, requested - count)} · ${(weight / 1000).toStringAsFixed(1)} kg'
                    : 'Loaded $count · Unloaded ${math.max(0, requested - count)} · ${(weight / 1000).toStringAsFixed(1)} kg'),
                style: const TextStyle(fontSize: 11),
              ),
            if (entries.isNotEmpty)
              Text(
                '${context.l10n.isZh ? '空间利用率' : 'Space utilization'} ${(100 * volume / (section.lengthMm * e.preset.dimensions.widthMm * e.preset.dimensions.heightMm)).toStringAsFixed(1)}%${e.needsPacking.contains(section.id) ? (context.l10n.isZh ? ' · 设置已变更，待自动装柜' : ' · Settings changed, layout pending') : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (groups.any((g) => g.needsReview))
              Text(
                context.toolsCopy('旧方案位置需复核，请检查分节边界或重新自动装柜。'),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summary(LoadingEditorController e) {
    final weight = e.totalWeightGrams;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.toolsCopy('整柜汇总'),
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        if (e.scene.groups.any((g) => g.sectionId == null)) ...[
          Text(context.l10n.t('cargoStaging')),
          for (final group in e.scene.groups.where((g) => g.sectionId == null))
            _ManualCargoEditor(
              key: ValueKey('outside-${group.id}'),
              group: group,
              hasConflict: e.scene.hasPlacementConflict(group),
              name:
                  e.entries
                      .where((entry) => entry.id == group.entryId)
                      .firstOrNull
                      ?.cargo
                      .name ??
                  group.cargoPackageId,
              onSelect: () => e.scene.select(group.id),
              onResize: (rows, layers) =>
                  e.scene.resizeGroup(group.id, rows: rows, layers: layers),
            ),
        ],
        const SizedBox(height: 8),
        Text(
          (context.l10n.isZh
              ? '已摆放 ${e.packedCount} / 设置 ${e.requestedCount} 件'
              : 'Loaded ${e.packedCount} / Requested ${e.requestedCount}'),
        ),
        Text(
          (context.l10n.isZh
              ? '未装 ${math.max(0, e.requestedCount - e.packedCount)} 件（不计入已装）'
              : 'Unloaded ${math.max(0, e.requestedCount - e.packedCount)} (excluded from loaded total)'),
        ),
        if (e.needsPacking.any((id) => e.entries.any((v) => v.sectionId == id)))
          Text(context.toolsCopy('部分设置待重新计算'), style: TextStyle(fontSize: 11)),
        if (e.entries.any(
          (v) =>
              !e.needsPacking.contains(v.sectionId) &&
              v.manualQuantityOverride &&
              e.packedFor(v.id) < v.quantity,
        ))
          Text(
            context.toolsCopy('已确认保留的未装数量仍需另行安排'),
            style: TextStyle(fontSize: 11),
          ),
        Text(
          (context.l10n.isZh
              ? '总重量 ${(weight / 1000).toStringAsFixed(1)} kg'
              : 'Total weight ${(weight / 1000).toStringAsFixed(1)} kg'),
        ),
        Text(
          (context.l10n.isZh
              ? '剩余载重 ${((e.maxPayloadGrams - weight) / 1000).toStringAsFixed(1)} kg'
              : 'Remaining payload ${((e.maxPayloadGrams - weight) / 1000).toStringAsFixed(1)} kg'),
        ),
        if (weight > e.maxPayloadGrams)
          Text(
            context.toolsCopy('⚠ 超出载重'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (e.dirty)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              context.toolsCopy('有未保存的修改'),
              style: TextStyle(fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _spaces(
    LoadingEditorController e,
    ContainerSection section,
    List<CargoPackageModel> cargo,
  ) {
    final allSpaces = e.spacesFor(section.id);
    final spaces = LoadingSpace.suggested(
      allSpaces,
      e.entries
          .where((v) => v.sectionId == section.id)
          .map((v) => v.spaceId)
          .whereType<String>(),
    );
    final actual = e.usesPlacedSpaces(section.id);
    final crossSectionVisible =
        (_crossSectionOpen ||
            e.sectionArrivalRevision != _dismissedArrivalRevision) &&
        e.selectedSectionId == section.id &&
        e.scene.groups.any((g) => g.sectionId == section.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        if (!crossSectionVisible)
          Text(
            context.toolsCopy('分节剖面 · 面向货柜内部'),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        if (!crossSectionVisible)
          SizedBox(
            height: 150,
            child: CustomPaint(
              painter: _SpaceSectionPainter(
                e.preset.dimensions,
                spaces,
                e.scene.groups.where((g) => g.sectionId == section.id).toList(),
              ),
            ),
          ),
        Text(
          context.l10n.isZh ? '剩余空间' : 'Remaining space',
          key: ValueKey('remaining-spaces-${section.id}'),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        if (spaces.any((s) => s.needsOverhang))
          Text(
            context.toolsCopy('上方空间允许长度悬出最多1m，仅用于规划；需现场确认支撑与承重。'),
            style: TextStyle(fontSize: 10, color: Color(0xFFB87A35)),
          ),
        Text(
          context.toolsCopy('尺寸为长 × 宽 × 高；宽或高不足50cm的空闲余隙不再提示装货。'),
          style: TextStyle(fontSize: 10),
        ),
        for (final gap in allSpaces.where(
          (s) => !s.isUsefulForLoading && !spaces.any((v) => v.id == s.id),
        ))
          Text(
            '${context.l10n.isZh ? '余隙（不推荐装货）' : 'Gap (not offered for loading)'}：${gap.bounds.dimensions.widthMm} × ${gap.bounds.dimensions.heightMm} mm',
            style: const TextStyle(fontSize: 10),
          ),
        for (final space in spaces)
          Container(
            key: ValueKey('loading-space-${space.id}'),
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF9BAFB6)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () => e.focusSection(section.id),
                  child: Text(
                    context.toolsSpaceName(space.name),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${space.bounds.dimensions.lengthMm} × ${space.bounds.dimensions.widthMm} × ${space.bounds.dimensions.heightMm} mm',
                  style: const TextStyle(fontSize: 11),
                ),
                if (space.parentId != null)
                  Text(
                    '${context.l10n.isZh ? '来自' : 'From'} ${context.toolsSpaceName(spaces.firstWhere((s) => s.id == space.parentId).name)}',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                for (final entry in e.entries.where(
                  (v) => !actual && v.spaceId == space.id,
                ))
                  _EntryEditor(
                    key: ValueKey(entry.id),
                    entry: entry,
                    recommended: e.gridFor(entry),
                    onChanged: e.updateEntry,
                    onDelete: () => e.removeEntry(entry.id),
                    autoFocus: entry.id == focusEntryId,
                    capacity: e.gridFor(entry).$1 * e.gridFor(entry).$2,
                  ),
                if (!space.isUsefulForLoading)
                  Text(
                    context.toolsCopy('小空间：保留已有分配，不再建议追加货物'),
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                if (space.isUsefulForLoading)
                  PopupMenuButton<String>(
                    tooltip: (context.l10n.isZh
                        ? '为${space.name}选择货物'
                        : 'Select cargo for ${context.toolsSpaceName(space.name)}'),
                    onSelected: (id) {
                      try {
                        setState(
                          () => focusEntryId = e.addCargo(
                            section.id,
                            cargo.firstWhere((c) => c.id == id),
                            spaceId: space.id,
                          ),
                        );
                      } on StateError catch (error) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(context.flyError(error))),
                        );
                      }
                    },
                    itemBuilder: (_) => [
                      for (final c in cargo.where(
                        (c) =>
                            c.type != CargoPackageType.pallet &&
                            c.type != CargoPackageType.crate,
                      ))
                        PopupMenuItem(
                          value: c.id,
                          enabled: e.canAddToSpace(section.id, c, space),
                          child: Text(c.name),
                        ),
                    ],
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        context.toolsCopy('+ 选择本空间货物'),
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        for (final entry in e.entries.where(
          (v) =>
              !actual &&
              v.sectionId == section.id &&
              v.spaceId != null &&
              !spaces.any((s) => s.id == v.spaceId),
        )) ...[
          Text(
            context.toolsCopy('原空间已变化，请删除此分配并重新选择空间'),
            style: TextStyle(fontSize: 11, color: Colors.orange),
          ),
          _EntryEditor(
            key: ValueKey(entry.id),
            entry: entry,
            recommended: (0, 0),
            onChanged: e.updateEntry,
            onDelete: () => e.removeEntry(entry.id),
            capacity: 0,
            autoFocus: false,
          ),
        ],
      ],
    );
  }

  Widget _toolbar(LoadingEditorController e) => Wrap(
    spacing: 2,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      IconButton(
        onPressed: e.scene.resetView,
        tooltip: context.toolsCopy('重置视角'),
        icon: const Icon(Icons.center_focus_strong, size: 18),
      ),
      for (final v in [
        (ContainerCameraView.top, context.toolsCopy('顶部')),
        (ContainerCameraView.side, context.toolsCopy('侧面')),
        (ContainerCameraView.front, context.toolsCopy('正面')),
        (ContainerCameraView.perspective, '3D'),
      ])
        TextButton(
          onPressed: () => e.scene.setCameraView(v.$1),
          child: Text(v.$2, style: const TextStyle(fontSize: 12)),
        ),
      IconButton(
        onPressed: e.scene.canUndo ? e.scene.undo : null,
        tooltip: context.toolsCopy('撤销 Ctrl+Z'),
        icon: const Icon(Icons.undo, size: 18),
      ),
      IconButton(
        onPressed: e.scene.canRedo ? e.scene.redo : null,
        tooltip: context.toolsCopy('重做 Ctrl+Y'),
        icon: const Icon(Icons.redo, size: 18),
      ),
      PopupMenuButton<String>(
        tooltip: context.toolsCopy('场景显示'),
        icon: const Icon(Icons.tune, size: 18),
        itemBuilder: (_) => [
          CheckedPopupMenuItem(
            value: 'grid',
            checked: e.scene.showGrid,
            child: Text(context.toolsCopy('显示网格')),
          ),
          CheckedPopupMenuItem(
            value: 'dimensions',
            checked: e.scene.showDimensions,
            child: Text(context.toolsCopy('显示尺寸')),
          ),
          PopupMenuItem(
            value: 'opacity',
            child: Text(context.toolsCopy('箱体透明度')),
          ),
          PopupMenuItem(
            value: 'focus',
            child: Text(context.toolsCopy('显示所有节')),
          ),
        ],
        onSelected: (v) {
          if (v == 'grid') e.scene.setShowGrid(!e.scene.showGrid);
          if (v == 'dimensions') {
            e.scene.setShowDimensions(!e.scene.showDimensions);
          }
          if (v == 'focus') e.scene.focusSection(null);
          if (v == 'opacity') {
            showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(context.toolsCopy('箱体透明度')),
                content: StatefulBuilder(
                  builder: (context, setLocal) => Slider(
                    value: e.scene.containerOpacity,
                    min: .08,
                    max: .8,
                    onChanged: (n) =>
                        setLocal(() => e.scene.setContainerOpacity(n)),
                  ),
                ),
              ),
            );
          }
        },
      ),
      IconButton(
        onPressed: _copy,
        tooltip: context.toolsCopy('复制装柜结果'),
        icon: const Icon(Icons.content_copy, size: 18),
      ),
      IconButton(
        onPressed: _screenshot,
        tooltip: context.toolsCopy('导出 PNG 截图'),
        icon: const Icon(Icons.photo_camera_outlined, size: 18),
      ),
    ],
  );
  Widget _selection(LoadingEditorController e, Map<String, String> names) {
    final g = e.scene.groups
        .where((g) => g.id == e.scene.selectedGroupId)
        .firstOrNull;
    if (g == null) return const SizedBox.shrink();
    return Container(
      width: 245,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xEE1C2B3A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Theme(
        data: ThemeData.dark(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${names[g.cargoPackageId] ?? context.toolsCopy('货物')} × ${g.quantity}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${g.rows} ${context.l10n.isZh ? '排' : 'rows'} × ${g.layers} ${context.l10n.isZh ? '层' : 'layers'} · ${g.boundingDimensions.lengthMm}×${g.boundingDimensions.widthMm}×${g.boundingDimensions.heightMm} mm',
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
            Text(
              'X ${g.positionXmm}  Y ${g.positionYmm}  Z ${g.positionZmm} mm',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            Row(
              children: [
                Text(context.toolsCopy('高度'), style: TextStyle(fontSize: 11)),
                IconButton(
                  onPressed: () => _moveZ(e, g, -50),
                  tooltip: context.toolsCopy('降低 50mm'),
                  icon: const Icon(Icons.remove, size: 16),
                ),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('z-${g.id}-${g.positionZmm}'),
                    initialValue: '${g.positionZmm}',
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      suffixText: 'mm',
                      isDense: true,
                    ),
                    onFieldSubmitted: (v) {
                      final n = int.tryParse(v);
                      if (n != null) _moveZ(e, g, n - g.positionZmm);
                    },
                  ),
                ),
                IconButton(
                  onPressed: () => _moveZ(e, g, 50),
                  tooltip: context.toolsCopy('升高 50mm'),
                  icon: const Icon(Icons.add, size: 16),
                ),
              ],
            ),
            Wrap(
              spacing: 0,
              children: [
                TextButton(
                  onPressed: e.scene.rotateSelectedX,
                  child: Text(context.toolsCopy('转 X')),
                ),
                TextButton(
                  onPressed: e.scene.rotateSelectedY,
                  child: Text(context.toolsCopy('转 Y')),
                ),
                TextButton(
                  onPressed: e.scene.rotateSelectedZ,
                  child: Text(context.toolsCopy('转 Z')),
                ),
                IconButton(
                  onPressed: e.scene.resetSelected,
                  tooltip: context.toolsCopy('恢复位置'),
                  icon: const Icon(Icons.restart_alt, size: 17),
                ),
                IconButton(
                  onPressed: () => _deleteGroup(e, g),
                  tooltip: context.toolsCopy('删除货物组'),
                  icon: const Icon(Icons.delete_outline, size: 17),
                ),
              ],
            ),
            if (e.scene.invalidGroupId == g.id)
              Text(
                context.toolsCopy('位置与边界、堆叠或其它货物冲突'),
                style: TextStyle(color: Colors.orangeAccent, fontSize: 10),
              ),
          ],
        ),
      ),
    );
  }

  void _moveZ(LoadingEditorController e, CargoGroupModel g, int delta) {
    e.scene.beginMove(g.id);
    e.scene.previewMove(g.positionXmm, g.positionYmm, g.positionZmm + delta);
    final invalid = e.scene.invalidGroupId != null;
    e.scene.endMove();
    if (invalid) _message(context.toolsCopy('位置无效，已恢复原位置'));
  }

  void _deleteGroup(LoadingEditorController e, CargoGroupModel g) {
    e.scene.deleteSelected();
  }

  Future<void> _editSections(LoadingEditorController e) async {
    final lengths = await showDialog<List<int>>(
      context: context,
      builder: (_) => _SectionLayoutDialog(
        lengths: e.sections.map((s) => s.lengthMm).toList(),
        containerLength: e.preset.dimensions.lengthMm,
      ),
    );
    if (lengths == null || !mounted) return;
    if (e.sections
        .skip(lengths.length)
        .any((s) => e.entries.any((c) => c.sectionId == s.id))) {
      if (!await confirmLoadingAction(
            context,
            context.toolsCopy('减少节数会移除末尾分节及其中货物，确定继续？'),
          ) ||
          !mounted) {
        return;
      }
    }
    try {
      e.setSections(lengths);
    } catch (error) {
      _message(context.flyError(error));
    }
  }
}

class _SpaceSectionPainter extends CustomPainter {
  _SpaceSectionPainter(this.container, this.spaces, this.bases);
  final Dimensions3 container;
  final List<LoadingSpace> spaces;
  final List<CargoGroupModel> bases;
  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      (size.width - 12) / container.widthMm,
      (size.height - 12) / container.heightMm,
    );
    final ox = (size.width - container.widthMm * scale) / 2;
    Rect rect(Aabb3 b) => Rect.fromLTWH(
      ox + b.y * scale,
      size.height - 6 - b.maxZ * scale,
      b.dimensions.widthMm * scale,
      b.dimensions.heightMm * scale,
    );
    void label(String text, Rect r) {
      final p = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            fontFamily: 'Microsoft YaHei UI',
            fontSize: 10,
            color: Color(0xFF263744),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: r.width);
      p.paint(canvas, r.center - Offset(p.width / 2, p.height / 2));
    }

    const colors = [Color(0xFFD9EADB), Color(0xFFF4E7CC), Color(0xFFDCE4F1)];
    for (var i = 0; i < spaces.length; i++) {
      final r = rect(spaces[i].bounds);
      canvas.drawRect(r, Paint()..color = colors[i % colors.length]);
      canvas.drawRect(
        r,
        Paint()
          ..color = const Color(0xFF78909C)
          ..style = PaintingStyle.stroke,
      );
      if (r.width >= 16 && r.height >= 12) {
        label(spaces[i].name.split(' · ').first, r);
      }
    }
    for (final g in bases) {
      final r = rect(g.bounds);
      canvas.drawRect(r, Paint()..color = Color(g.colorValue));
      canvas.drawRect(
        r,
        Paint()
          ..color = const Color(0xFF30485D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      for (var i = 1; i < g.layers; i++) {
        final y = r.bottom - i * r.height / g.layers;
        canvas.drawLine(
          Offset(r.left, y),
          Offset(r.right, y),
          Paint()
            ..color = const Color(0xFF30485D)
            ..strokeWidth = 2,
        );
      }
      if (r.width >= 16 && r.height >= 12) label('×${g.quantity}', r);
    }
  }

  @override
  bool shouldRepaint(covariant _SpaceSectionPainter old) => true;
}

class _ManualCargoEditor extends StatefulWidget {
  const _ManualCargoEditor({
    super.key,
    required this.group,
    required this.name,
    required this.onSelect,
    required this.onResize,
    required this.hasConflict,
  });
  final CargoGroupModel group;
  final String name;
  final VoidCallback onSelect;
  final bool Function(int rows, int layers) onResize;
  final bool hasConflict;
  @override
  State<_ManualCargoEditor> createState() => _ManualCargoEditorState();
}

class _ManualCargoEditorState extends State<_ManualCargoEditor> {
  late final rows = TextEditingController(text: '${widget.group.rows}');
  late final layers = TextEditingController(text: '${widget.group.layers}');
  bool rejected = false;
  @override
  void didUpdateWidget(covariant _ManualCargoEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.rows != widget.group.rows) {
      rows.text = '${widget.group.rows}';
    }
    if (oldWidget.group.layers != widget.group.layers) {
      layers.text = '${widget.group.layers}';
    }
  }

  void resize() {
    final r = int.tryParse(rows.text);
    final l = int.tryParse(layers.text);
    final accepted =
        r != null && l != null && r > 0 && l > 0 && widget.onResize(r, l);
    setState(() => rejected = !accepted);
  }

  @override
  void dispose() {
    rows.dispose();
    layers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final zh = context.l10n.isZh;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: widget.onSelect,
            child: Row(
              children: [
                Container(width: 7, height: 24, color: Color(g.colorValue)),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${widget.name} × ${g.quantity}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (g.sectionId == null)
            Text(
              zh ? '柜外货物 · 不属于任何分节' : 'Outside · not assigned to a section',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: rows,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: zh ? '每排数量' : 'Units across',
                  ),
                  onChanged: (_) => resize(),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('×'),
              ),
              Expanded(
                child: TextField(
                  controller: layers,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: zh ? '层数' : 'Layers',
                  ),
                  onChanged: (_) => resize(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            zh
                ? '合计 ${g.quantity} 件${g.columns > 1 ? '（沿柜长 ${g.columns} 列）' : ''}'
                : 'Total ${g.quantity} units · ${g.columns} lengthwise',
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            '${g.boundingDimensions.lengthMm} × ${g.boundingDimensions.widthMm} × ${g.boundingDimensions.heightMm} mm',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (widget.hasConflict)
            Text(
              zh ? '尺寸已应用；存在重叠、超界或堆叠限制，请调整当前货物位置。' : 'Size applied; check overlap, boundaries or stacking restrictions.',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          if (rejected)
            Text(
              zh
                  ? '请输入 1–10000 的正整数。'
                  : 'Enter a whole number from 1 to 10000.',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}

class _EntryEditor extends StatefulWidget {
  const _EntryEditor({
    required this.entry,
    required this.onChanged,
    required this.onDelete,
    required this.capacity,
    required this.autoFocus,
    required this.recommended,
    super.key,
  });
  final SectionCargoEntry entry;
  final ValueChanged<SectionCargoEntry> onChanged;
  final VoidCallback onDelete;
  final int capacity;
  final bool autoFocus;
  final (int, int) recommended;
  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  late final quantity = TextEditingController(text: '${widget.entry.quantity}');
  late final perRow = TextEditingController(
    text: widget.entry.perRow?.toString() ?? '',
  );
  late final rowCount = TextEditingController(
    text: widget.entry.rowCount?.toString() ?? '',
  );
  final focus = FocusNode();
  bool expanded = false;
  @override
  void initState() {
    super.initState();
    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) focus.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _EntryEditor old) {
    super.didUpdateWidget(old);
    if (old.entry.quantity != widget.entry.quantity &&
        int.tryParse(quantity.text) != widget.entry.quantity) {
      quantity.text = '${widget.entry.quantity}';
    }
    if (widget.autoFocus && !old.autoFocus) focus.requestFocus();
  }

  @override
  void dispose() {
    quantity.dispose();
    perRow.dispose();
    rowCount.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return Padding(
      padding: const EdgeInsets.only(top: 7, bottom: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 25,
                decoration: BoxDecoration(
                  color: Color(e.colorValue),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  e.cargo.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (e.isBase)
                SizedBox(
                  width: 64,
                  child: TextField(
                    key: ValueKey('quantity-${e.id}'),
                    controller: quantity,
                    focusNode: focus,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.toolsCopy('数量'),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                    ),
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      if (n != null && n >= 0) {
                        widget.onChanged(e.copyWith(quantity: n));
                      }
                    },
                  ),
                ),
              SizedBox(
                width: 27,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.close, size: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (!e.isBase) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('per-row-${e.id}'),
                    controller: perRow,
                    focusNode: focus,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: context.toolsCopy('每排数量'),
                      hintText: (context.l10n.isZh
                          ? '推荐 ${widget.recommended.$1}'
                          : 'Suggested ${widget.recommended.$1}'),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      isDense: true,
                    ),
                    onChanged: (_) => _gridChanged(),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5),
                  child: Text('×'),
                ),
                Expanded(
                  child: TextField(
                    key: ValueKey('row-count-${e.id}'),
                    controller: rowCount,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: context.toolsCopy('纵向排数（层）'),
                      hintText: (context.l10n.isZh
                          ? '推荐 ${widget.recommended.$2}'
                          : 'Suggested ${widget.recommended.$2}'),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      isDense: true,
                    ),
                    onChanged: (_) => _gridChanged(),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text(
                (context.l10n.isZh
                    ? '合计 ${e.quantity} 件'
                    : 'Total ${e.quantity} units'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  '${e.spaceId == null ? context.toolsCopy('理论本节') : context.toolsCopy('本空间上限')} ${widget.capacity} ${context.l10n.isZh ? '件' : 'units'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              InkWell(
                onTap: () => setState(() => expanded = !expanded),
                child: Text(
                  expanded
                      ? context.toolsCopy('收起设置')
                      : context.toolsCopy('摆放设置'),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          if (e.manualQuantityOverride)
            Text(
              context.toolsCopy('⚠ 用户覆盖理论容量'),
              style: TextStyle(fontSize: 11, color: Color(0xFFB87A35)),
            ),
          if (expanded) ...[
            const SizedBox(height: 8),
            _choices<PlacementOrientation>(
              [
                (PlacementOrientation.flat, context.toolsCopy('平放')),
                (PlacementOrientation.upright, context.toolsCopy('立放')),
                (PlacementOrientation.side, context.toolsCopy('侧放')),
                (PlacementOrientation.automatic, context.toolsCopy('自动')),
              ],
              e.orientation,
              (v) => widget.onChanged(e.copyWith(orientation: v)),
            ),
            const SizedBox(height: 5),
            _choices<HorizontalPlacement>(
              [
                (HorizontalPlacement.automatic, context.toolsCopy('自动')),
                (HorizontalPlacement.left, context.toolsCopy('靠左')),
                (HorizontalPlacement.center, context.toolsCopy('居中')),
                (HorizontalPlacement.right, context.toolsCopy('靠右')),
              ],
              e.horizontalPlacement,
              (v) => widget.onChanged(e.copyWith(horizontalPlacement: v)),
            ),
            Wrap(
              children: [
                _check(
                  context.toolsCopy('放在底部'),
                  e.placeOnBottom,
                  (v) => widget.onChanged(e.copyWith(placeOnBottom: v)),
                ),
                _check(
                  context.toolsCopy('允许堆叠'),
                  e.allowStack,
                  (v) => widget.onChanged(e.copyWith(allowStack: v)),
                ),
                if (!e.isBase)
                  _check(
                    context.toolsCopy('允许长度悬出≤1m'),
                    e.allowOverhang,
                    (v) => widget.onChanged(e.copyWith(allowOverhang: v)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _choices<T>(
    List<(T, String)> options,
    T selected,
    ValueChanged<T> change,
  ) => Row(
    children: [
      for (final o in options)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 3),
            child: InkWell(
              onTap: () => change(o.$1),
              borderRadius: BorderRadius.circular(5),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: o.$1 == selected
                      ? context.flyColors.selected
                      : context.flyColors.surface,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  o.$2,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ),
        ),
    ],
  );

  void _gridChanged() {
    final a = int.tryParse(perRow.text) ?? widget.recommended.$1;
    final b = int.tryParse(rowCount.text) ?? widget.recommended.$2;
    widget.onChanged(
      widget.entry.copyWith(
        perRow: a,
        rowCount: b,
        quantity: a * b,
        manualQuantityOverride: false,
      ),
    );
  }

  Widget _check(String text, bool value, ValueChanged<bool> change) => InkWell(
    onTap: () => change(!value),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: (v) => change(v!),
          visualDensity: VisualDensity.compact,
        ),
        Text(text, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}

class _SectionLayoutDialog extends StatefulWidget {
  const _SectionLayoutDialog({
    required this.lengths,
    required this.containerLength,
  });
  final List<int> lengths;
  final int containerLength;
  @override
  State<_SectionLayoutDialog> createState() => _SectionLayoutDialogState();
}

class _SectionLayoutDialogState extends State<_SectionLayoutDialog> {
  late final controllers = [
    for (final n in widget.lengths) TextEditingController(text: '${n / 1000}'),
  ];
  final retired = <TextEditingController>[];
  String? error;
  @override
  void dispose() {
    for (final c in [...controllers, ...retired]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.toolsCopy('集装箱分节')),
    content: SizedBox(
      width: 350,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  (context.l10n.isZh
                      ? '节数 ${controllers.length}'
                      : 'Sections ${controllers.length}'),
                ),
                const Spacer(),
                IconButton(
                  onPressed: controllers.length <= 1
                      ? null
                      : () => setState(
                          () => retired.add(controllers.removeLast()),
                        ),
                  icon: const Icon(Icons.remove),
                ),
                IconButton(
                  onPressed: controllers.length >= 30
                      ? null
                      : () => setState(
                          () => controllers.add(
                            TextEditingController(text: '2.9'),
                          ),
                        ),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            for (var i = 0; i < controllers.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: controllers[i],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: (context.l10n.isZh
                        ? '第${i + 1}节'
                        : 'Section ${i + 1}'),
                    suffixText: 'm',
                  ),
                ),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.toolsCopy('取消')),
      ),
      FilledButton(
        onPressed: () {
          final ns = controllers.map((c) => double.tryParse(c.text)).toList();
          if (ns.any((v) => v == null || !v.isFinite || v * 1000 < 1)) {
            setState(() => error = context.toolsCopy('每节长度必须大于 0'));
            return;
          }
          final lengths = ns.map((n) => (n! * 1000).round()).toList();
          final total = lengths.fold(0, (a, b) => a + b);
          if (total > widget.containerLength) {
            setState(
              () => error = (context.l10n.isZh
                  ? '分节总长度 ${total / 1000}m 超过集装箱 ${widget.containerLength / 1000}m'
                  : 'Sections total ${total / 1000}m exceeds container ${widget.containerLength / 1000}m'),
            );
            return;
          }
          Navigator.pop(context, lengths);
        },
        child: Text(context.toolsCopy('应用')),
      ),
    ],
  );
}
