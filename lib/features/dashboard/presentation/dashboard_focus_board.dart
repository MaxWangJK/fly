import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/dashboard_focus_copy.dart';
import '../../../shared/design_system/design_tokens.dart';
import '../../../shared/design_system/fly_color_scheme.dart';
import '../../tasks/presentation/task_providers.dart';
import '../data/dashboard_focus_repository.dart';
import '../domain/dashboard_focus.dart';

final dashboardFocusRepositoryProvider = Provider<DashboardFocusRepository>(
  (ref) => DashboardFocusRepository(ref.watch(databaseProvider)),
);

final dashboardFocusProvider = FutureProvider.autoDispose
    .family<DashboardFocusSnapshot, DateTime>(
      (ref, day) => ref.watch(dashboardFocusRepositoryProvider).read(day),
    );

final dashboardFocusHistoryProvider =
    FutureProvider.autoDispose<List<DashboardFocusHistoryEntry>>(
      (ref) => ref.watch(dashboardFocusRepositoryProvider).history(),
    );

class DashboardFocusBoard extends ConsumerWidget {
  const DashboardFocusBoard({
    required this.day,
    required this.onHistory,
    super.key,
  });

  final DateTime day;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.flyColors;
    final value = ref.watch(dashboardFocusProvider(day));
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FlyRadius.md),
        side: BorderSide(color: colors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 17, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.focusCopy('我的聚焦'),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('dashboard-focus-history'),
                  onPressed: onHistory,
                  icon: const Icon(Icons.history_rounded, size: 17),
                  label: Text(context.focusCopy('历史')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            value.when(
              loading: () => const SizedBox(
                height: 130,
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
              error: (_, _) => SizedBox(
                height: 130,
                child: Center(
                  child: TextButton.icon(
                    onPressed: () =>
                        ref.invalidate(dashboardFocusProvider(day)),
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(context.focusCopy('重试')),
                  ),
                ),
              ),
              data: (snapshot) => Column(
                children: [
                  _FocusSection(
                    key: const ValueKey('focus-section-mainMission'),
                    type: DashboardFocusType.mainMission,
                    content: snapshot.mainMission,
                    day: day,
                  ),
                  Divider(height: 22, color: colors.divider),
                  _FocusSection(
                    key: const ValueKey('focus-section-weeklyFocus'),
                    type: DashboardFocusType.weeklyFocus,
                    content: snapshot.weeklyFocus,
                    day: day,
                  ),
                  Divider(height: 22, color: colors.divider),
                  _FocusSection(
                    key: const ValueKey('focus-section-todayFocus'),
                    type: DashboardFocusType.todayFocus,
                    content: snapshot.todayFocus,
                    day: day,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusSection extends ConsumerStatefulWidget {
  const _FocusSection({
    required this.type,
    required this.content,
    required this.day,
    super.key,
  });

  final DashboardFocusType type;
  final String content;
  final DateTime day;

  @override
  ConsumerState<_FocusSection> createState() => _FocusSectionState();
}

class _FocusSectionState extends ConsumerState<_FocusSection> {
  final controller = TextEditingController();
  final focusNode = FocusNode();
  bool editing = false;
  bool saving = false;
  bool hovering = false;
  String? error;

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  String _label(BuildContext context) =>
      context.focusCopy(switch (widget.type) {
        DashboardFocusType.mainMission => '人生主线',
        DashboardFocusType.weeklyFocus => '本周重点',
        DashboardFocusType.todayFocus => '今日提醒',
      });

  String _placeholder(BuildContext context) =>
      context.focusCopy(switch (widget.type) {
        DashboardFocusType.mainMission => '点击这里写下你当前最重要的长期目标',
        DashboardFocusType.weeklyFocus => '这周最重要的一件事是什么？',
        DashboardFocusType.todayFocus => '今天必须完成什么？',
      });

  void _beginEdit() {
    if (saving) return;
    controller.text = widget.content;
    error = null;
    setState(() => editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusNode.requestFocus();
    });
  }

  void _cancel() {
    if (saving) return;
    focusNode.unfocus();
    setState(() {
      editing = false;
      error = null;
    });
  }

  Future<void> _save() async {
    if (!editing || saving) return;
    final next = controller.text.trim();
    if (next == widget.content) {
      _cancel();
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref
          .read(dashboardFocusRepositoryProvider)
          .save(type: widget.type, content: next, day: widget.day);
      if (!mounted) return;
      ref.invalidate(dashboardFocusProvider(widget.day));
      ref.invalidate(dashboardFocusHistoryProvider);
      focusNode.unfocus();
      setState(() {
        editing = false;
        saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = context.focusCopy('保存失败，请重试');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flyColors;
    final type = widget.type;
    final prominent = type == DashboardFocusType.mainMission;
    final accent = type == DashboardFocusType.todayFocus
        ? colors.warning
        : colors.accent;
    final contentStyle =
        (prominent
                ? Theme.of(context).textTheme.titleLarge
                : Theme.of(context).textTheme.titleMedium)
            ?.copyWith(
              fontSize: prominent
                  ? 21
                  : type == DashboardFocusType.weeklyFocus
                  ? 17
                  : 16,
              fontWeight: prominent ? FontWeight.w600 : FontWeight.w500,
              height: 1.35,
              color: colors.textPrimary,
            );
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 9),
        decoration: BoxDecoration(
          color: type == DashboardFocusType.weeklyFocus
              ? colors.surface
              : Color.alphaBlend(
                  accent.withValues(alpha: .045),
                  colors.surface,
                ),
          border: Border(
            left: BorderSide(color: accent.withValues(alpha: .55), width: 3),
          ),
          borderRadius: BorderRadius.circular(FlyRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _label(context),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: 30,
                  height: 26,
                  child: hovering && !editing
                      ? IconButton(
                          tooltip: context.focusCopy('编辑'),
                          padding: EdgeInsets.zero,
                          onPressed: _beginEdit,
                          icon: Icon(
                            Icons.edit_outlined,
                            size: 16,
                            color: colors.textSecondary,
                          ),
                        )
                      : null,
                ),
              ],
            ),
            if (editing)
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.enter): _save,
                  const SingleActivator(
                    LogicalKeyboardKey.enter,
                    control: true,
                  ): _save,
                  const SingleActivator(LogicalKeyboardKey.escape): _cancel,
                },
                child: TextField(
                  key: ValueKey('focus-editor-${type.name}'),
                  controller: controller,
                  focusNode: focusNode,
                  maxLines: 3,
                  maxLength: 800,
                  textInputAction: TextInputAction.newline,
                  onTapOutside: (_) => _save(),
                  decoration: InputDecoration(
                    hintText: _placeholder(context),
                    isDense: true,
                    errorText: error,
                    helperText: saving ? context.focusCopy('保存中…') : null,
                    counterText: '',
                  ),
                ),
              )
            else
              Semantics(
                button: true,
                label: '${context.focusCopy('编辑')} ${_label(context)}',
                child: InkWell(
                  key: ValueKey('focus-content-${type.name}'),
                  onTap: _beginEdit,
                  borderRadius: BorderRadius.circular(FlyRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(
                      widget.content.isEmpty
                          ? _placeholder(context)
                          : widget.content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: widget.content.isEmpty
                          ? contentStyle?.copyWith(
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w400,
                            )
                          : contentStyle,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DashboardFocusHistoryPanel extends ConsumerWidget {
  const DashboardFocusHistoryPanel({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.flyColors;
    final history = ref.watch(dashboardFocusHistoryProvider);
    return Material(
      color: colors.surface,
      elevation: FlyElevation.popup,
      child: Column(
        children: [
          SizedBox(
            height: 68,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.focusCopy('聚焦历史'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: context.focusCopy('关闭历史'),
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: colors.divider),
          Expanded(
            child: history.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator.adaptive()),
              error: (_, _) => Center(
                child: TextButton.icon(
                  onPressed: () =>
                      ref.invalidate(dashboardFocusHistoryProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(context.focusCopy('重试')),
                ),
              ),
              data: (entries) => entries.isEmpty
                  ? Center(
                      child: Text(
                        context.focusCopy('暂无历史'),
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: colors.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      key: const ValueKey('dashboard-focus-history-list'),
                      padding: const EdgeInsets.all(20),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 18),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final label = context.focusCopy(switch (entry.type) {
                          DashboardFocusType.mainMission => '人生主线',
                          DashboardFocusType.weeklyFocus => '本周重点',
                          DashboardFocusType.todayFocus => '今日提醒',
                        });
                        return Semantics(
                          label:
                              '${DateFormat('yyyy-MM-dd').format(entry.effectiveDate)} $label',
                          child: Column(
                            key: ValueKey('focus-history-${entry.id}'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat('yyyy-MM-dd')
                                    .format(entry.effectiveDate),
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 7),
                              Text(
                                label,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(color: colors.accent),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                entry.content,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              if (!entry.id.startsWith('day-'))
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    context.focusCopy('旧版本'),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: colors.textSecondary),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
