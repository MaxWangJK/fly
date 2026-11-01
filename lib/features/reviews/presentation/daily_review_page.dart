import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../../../shared/design_system/responsive_layout.dart';
import '../../tasks/presentation/widgets/task_view_links.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/fly_localizations.dart';
import '../../../shared/design_system/design_tokens.dart';
import '../../../shared/design_system/fly_color_scheme.dart';
import '../../tasks/presentation/task_providers.dart';
import '../data/daily_review_repository.dart';
import 'review_providers.dart';
import 'review_answer_field.dart';

class DailyReviewPage extends ConsumerStatefulWidget {
  const DailyReviewPage({this.onChooseProgram, super.key});
  final VoidCallback? onChooseProgram;
  @override
  ConsumerState<DailyReviewPage> createState() => _DailyReviewPageState();
}

class _DailyReviewPageState extends ConsumerState<DailyReviewPage> {
  String? selected;
  bool changingDay = false;
  bool showingHistory = false;

  Future<void> toggleHistory(String day) async {
    if (changingDay) return;
    if (showingHistory) {
      setState(() => showingHistory = false);
      return;
    }
    setState(() => changingDay = true);
    try {
      await ref.read(reviewSessionsProvider)[day]?.flush();
      if (mounted) setState(() => showingHistory = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.isZh
                  ? '当前复盘未能保存，请重试后再查看历史。'
                  : 'Save failed. Retry before opening history.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => changingDay = false);
    }
  }

  Future<void> changeDay(String from, String to) async {
    if (changingDay || from == to) return;
    setState(() => changingDay = true);
    try {
      await ref.read(reviewSessionsProvider)[from]?.flush();
      if (mounted) setState(() => selected = to);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.isZh
                  ? '当前复盘未能保存，请重试后再切换日期。'
                  : 'Save failed. Retry before changing the date.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => changingDay = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(localTodayProvider);
    final todayKey = DailyReviewRepository.key(today);
    final day = selected ?? todayKey;
    final selectedDate = DateTime.parse(day);
    final recorded = ref.watch(recordedReviewDaysProvider);
    final navigationDays = {
      ...?recorded.valueOrNull,
      todayKey,
    }.where((value) => value.compareTo(todayKey) <= 0).toList()..sort();
    final previous =
        navigationDays.where((value) => value.compareTo(day) < 0).lastOrNull ??
        (selectedDate.isAfter(DateTime(2000))
            ? DailyReviewRepository.key(
                DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day - 1,
                ),
              )
            : null);
    final next = navigationDays
        .where((value) => value.compareTo(day) > 0)
        .firstOrNull;
    final text = FlyLocalizations(Localizations.localeOf(context)).t;
    final session = ref.watch(reviewSessionProvider(day));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isPhoneLayout(context)) const TaskViewLinks(current: 'review'),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                text('dailyReview'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (widget.onChooseProgram != null)
                IconButton(
                  key: const ValueKey('review-choose-program'),
                  onPressed: widget.onChooseProgram,
                  icon: const Icon(Icons.style_outlined, size: 18),
                  tooltip: context.l10n.isZh ? '复盘方案' : 'Review programs',
                ),
              TextButton.icon(
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(day),
                onPressed: changingDay || showingHistory
                    ? null
                    : () async {
                        final chosen = await showDatePicker(
                          context: context,
                          initialDate: DateTime.parse(day),
                          firstDate: DateTime(2000),
                          lastDate: today,
                        );
                        if (chosen != null && mounted) {
                          await changeDay(
                            day,
                            DailyReviewRepository.key(chosen),
                          );
                        }
                      },
              ),
              TextButton.icon(
                icon: const Icon(Icons.chevron_left, size: 18),
                label: Text(context.l10n.isZh ? '前一天' : 'Previous day'),
                onPressed:
                    changingDay ||
                        showingHistory ||
                        recorded.isLoading ||
                        previous == null
                    ? null
                    : () => changeDay(day, previous),
              ),
              TextButton.icon(
                icon: const Icon(Icons.chevron_right, size: 18),
                label: Text(context.l10n.isZh ? '后一天' : 'Next day'),
                onPressed: changingDay || showingHistory || next == null
                    ? null
                    : () => changeDay(day, next),
              ),
              TextButton.icon(
                key: const ValueKey('review-history-toggle'),
                icon: Icon(
                  showingHistory
                      ? Icons.edit_note_rounded
                      : Icons.view_stream_rounded,
                  size: 19,
                ),
                label: Text(
                  showingHistory
                      ? context.l10n.isZh
                            ? '返回编辑'
                            : 'Back to editor'
                      : context.l10n.isZh
                      ? '历史记录'
                      : 'History',
                ),
                onPressed: changingDay ? null : () => toggleHistory(day),
              ),
              if (recorded.hasError)
                TextButton(
                  onPressed: () => ref.invalidate(recordedReviewDaysProvider),
                  child: Text(text('reviewRetry')),
                ),
            ],
          ),
        ),
        Expanded(
          child: showingHistory
              ? _ReviewHistory(
                  onOpen: (target) async {
                    await changeDay(day, target);
                    if (mounted && (selected ?? todayKey) == target) {
                      setState(() => showingHistory = false);
                    }
                  },
                )
              : session.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, s) => Center(
                    child: TextButton(
                      onPressed: () =>
                          ref.invalidate(reviewSessionProvider(day)),
                      child: Text(text('reviewRetry')),
                    ),
                  ),
                  data: (value) =>
                      _ReviewEditor(key: ValueKey(day), session: value),
                ),
        ),
      ],
    );
  }
}

class _ReviewHistory extends ConsumerStatefulWidget {
  const _ReviewHistory({required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  ConsumerState<_ReviewHistory> createState() => _ReviewHistoryState();
}

class _ReviewHistoryState extends ConsumerState<_ReviewHistory> {
  final scrollController = ScrollController();

  double _preferredCardWidth(ReviewHistoryEntry entry) {
    final answers = entry.answers.values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final total = answers.fold<int>(
      0,
      (sum, value) => sum + value.runes.length,
    );
    final longest = answers.fold<int>(
      0,
      (length, value) => math.max(length, value.runes.length),
    );
    return (235 +
            answers.length * 14 +
            math.min(total / 8, 110) +
            math.min(longest / 6, 90))
        .clamp(250, 520)
        .toDouble();
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(reviewHistoryProvider);
    return history.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (error, stack) => Center(
        child: TextButton.icon(
          onPressed: () => ref.invalidate(reviewHistoryProvider),
          icon: const Icon(Icons.refresh),
          label: Text(context.l10n.t('reviewRetry')),
        ),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return Center(
            child: Text(
              context.l10n.isZh
                  ? '还没有写过复盘，完成第一篇后会显示在这里。'
                  : 'Your reflections will appear here after you write one.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            const gap = FlySpacing.md;
            final contentWidth = math.max(0.0, constraints.maxWidth - 40);
            final columns = math.min(
              entries.length,
              ((contentWidth + gap) / (250 + gap)).floor().clamp(1, 5),
            );
            final groups = List.generate(
              columns,
              (_) => <ReviewHistoryEntry>[],
            );
            for (var index = 0; index < entries.length; index++) {
              groups[index % columns].add(entries[index]);
            }
            final available = math.max(0.0, contentWidth - gap * (columns - 1));
            final minimum = math.min(250.0, available / columns);
            final widths = List<double>.filled(columns, minimum);
            final desired = [
              for (final group in groups)
                group.map(_preferredCardWidth).reduce(math.max),
            ];
            final extra = math.max(0.0, available - minimum * columns);
            final demand = desired.fold<double>(
              0,
              (sum, width) => sum + math.max(0.0, width - minimum),
            );
            if (demand > 0) {
              for (var index = 0; index < columns; index++) {
                widths[index] +=
                    math.max(0.0, desired[index] - minimum) *
                    math.min(1.0, extra / demand);
              }
            }
            return Scrollbar(
              controller: scrollController,
              thumbVisibility: true,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.touch,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        context.l10n.isZh
                            ? '写过的每一天，都会留在这里'
                            : 'Every reflection, in one place',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: FlySpacing.xs),
                      Text(
                        context.l10n.isZh
                            ? '按日期倒序 · 点击卡片可回到当天编辑'
                            : 'Newest first · Select a card to edit that day',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: FlySpacing.lg),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var index = 0; index < columns; index++) ...[
                            if (index > 0) const SizedBox(width: gap),
                            SizedBox(
                              width: widths[index],
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final entry in groups[index]) ...[
                                    SizedBox(
                                      width: math.min(
                                        widths[index],
                                        _preferredCardWidth(entry),
                                      ),
                                      child: _ReviewHistoryCard(
                                        entry: entry,
                                        onTap: () => widget.onOpen(entry.day),
                                      ),
                                    ),
                                    const SizedBox(height: FlySpacing.md),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ReviewHistoryCard extends StatefulWidget {
  const _ReviewHistoryCard({required this.entry, required this.onTap});

  final ReviewHistoryEntry entry;
  final VoidCallback onTap;

  @override
  State<_ReviewHistoryCard> createState() => _ReviewHistoryCardState();
}

class _ReviewHistoryCardState extends State<_ReviewHistoryCard> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.flyColors;
    final text = context.l10n.t;
    final dark = Theme.of(context).brightness == Brightness.dark;
    const sections = [
      (1, [1, 2]),
      (2, [3, 4]),
      (3, [5, 6, 7]),
      (4, [8, 10, 11]),
      (5, [9]),
    ];
    final sectionColors = [
      colors.accent,
      colors.warning,
      Theme.of(context).colorScheme.tertiary,
      colors.success,
      colors.textSecondary,
    ];
    final visibleSections = <(int, List<int>)>[
      for (final section in sections)
        if (section.$2.any(
          (question) =>
              widget.entry.answers['q$question']?.trim().isNotEmpty ?? false,
        ))
          section,
    ];
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedContainer(
        key: ValueKey('review-history-${widget.entry.day}'),
        duration: FlyMotion.fast,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FlyRadius.lg),
          border: Border.all(
            color: hovered
                ? colors.accent.withValues(alpha: .55)
                : colors.divider,
          ),
          boxShadow: hovered
              ? [
                  BoxShadow(
                    color: colors.accent.withValues(alpha: .09),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(FlyRadius.lg),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(FlySpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 22,
                        decoration: BoxDecoration(
                          color: colors.accent,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: FlySpacing.sm),
                      Expanded(
                        child: Text(
                          widget.entry.day,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Icon(
                        Icons.arrow_outward_rounded,
                        size: 16,
                        color: colors.textSecondary,
                      ),
                    ],
                  ),
                  if (visibleSections.isNotEmpty)
                    const SizedBox(height: FlySpacing.sm),
                  for (
                    var index = 0;
                    index < visibleSections.length;
                    index++
                  ) ...[
                    if (index > 0) const SizedBox(height: FlySpacing.xs),
                    _section(
                      context,
                      visibleSections[index],
                      sectionColors[visibleSections[index].$1 - 1],
                      dark,
                      text,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context,
    (int, List<int>) section,
    Color tone,
    bool dark,
    String Function(String) text,
  ) {
    final colors = context.flyColors;
    final answers = [
      for (final question in section.$2)
        if (widget.entry.answers['q$question']?.trim().isNotEmpty ?? false)
          (question, widget.entry.answers['q$question']!.trim()),
    ];
    return Container(
      key: ValueKey('review-history-section-${widget.entry.day}-${section.$1}'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: FlySpacing.sm,
        vertical: FlySpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          tone.withValues(alpha: dark ? .13 : .08),
          colors.surface,
        ),
        borderRadius: BorderRadius.circular(FlyRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: FlySpacing.xs),
              Flexible(
                child: Text(
                  section.$1 == 5
                      ? text('reviewQ9')
                      : text('reviewSection${section.$1}'),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: FlySpacing.xxs),
          for (var index = 0; index < answers.length; index++) ...[
            if (index > 0) const SizedBox(height: FlySpacing.xxs),
            if (section.$1 == 5)
              Text(
                answers[index].$2,
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: 7,
                overflow: TextOverflow.ellipsis,
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 60,
                    child: Tooltip(
                      message: text('reviewQ${answers[index].$1}'),
                      child: Text(
                        text('reviewHistoryQ${answers[index].$1}'),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(width: FlySpacing.xs),
                  Expanded(
                    child: Text(
                      answers[index].$2,
                      style: Theme.of(context).textTheme.bodyMedium,
                      maxLines: 7,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _ReviewEditor extends ConsumerStatefulWidget {
  const _ReviewEditor({required this.session, super.key});
  final ReviewSession session;
  @override
  ConsumerState<_ReviewEditor> createState() => _ReviewEditorState();
}

class _ReviewEditorState extends ConsumerState<_ReviewEditor> {
  late final controllers = {
    for (var i = 1; i <= 11; i++)
      'q$i': TextEditingController(text: widget.session.values['q$i'] ?? ''),
  };
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_refreshAnswers);
  }

  void _refreshAnswers() {
    for (final entry in controllers.entries) {
      final value = widget.session.values[entry.key] ?? '';
      if (entry.value.text != value) entry.value.text = value;
    }
  }

  @override
  void didUpdateWidget(covariant _ReviewEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.session, widget.session)) return;
    oldWidget.session.removeListener(_refreshAnswers);
    widget.session.addListener(_refreshAnswers);
    _refreshAnswers();
  }

  @override
  void dispose() {
    widget.session.removeListener(_refreshAnswers);
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = FlyLocalizations(Localizations.localeOf(context)).t;
    final summary = ref.watch(reviewSummaryProvider(widget.session.day));
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Material(
            key: ValueKey('review-today-card-${widget.session.day}'),
            color: context.flyColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: context.flyColors.divider),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      for (final item
                          in summary.valueOrNull?.entries ??
                              <MapEntry<String, int>>[])
                        Text(
                          '${text('reviewStat_${item.key}')} ${item.value}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      IconButton(
                        tooltip: text('reviewRefresh'),
                        onPressed: () => ref.invalidate(
                          reviewSummaryProvider(widget.session.day),
                        ),
                        icon: const Icon(Icons.refresh, size: 18),
                      ),
                    ],
                  ),
                  if (summary.hasError) Text(text('reviewSummaryError')),
                  if (widget.session.error != null)
                    TextButton(
                      onPressed: () async {
                        try {
                          await widget.session.flush();
                        } catch (_) {
                          /* Error remains visible. */
                        }
                      },
                      child: Text(text('reviewRetry')),
                    )
                  else
                    Text(
                      text(
                        widget.session.saving ? 'reviewSaving' : 'reviewSaved',
                      ),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final twoColumns = constraints.maxWidth >= 700;
                      final colors = context.flyColors;
                      const sections = [
                        (1, [1, 2]),
                        (2, [3, 4]),
                        (3, [5, 6, 7]),
                        (4, [8, 10, 11]),
                      ];
                      Widget card((int, List<int>) section) => Padding(
                        key: ValueKey('review-section-${section.$1}'),
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              text('reviewSection${section.$1}'),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: colors.accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            for (final question in section.$2)
                              _question(question, text),
                          ],
                        ),
                      );
                      return Column(
                        children: [
                          for (
                            var index = 0;
                            index < sections.length;
                            index += twoColumns ? 2 : 1
                          )
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: twoColumns
                                  ? IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            child: card(sections[index]),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: card(sections[index + 1]),
                                          ),
                                        ],
                                      ),
                                    )
                                  : SizedBox(
                                      width: double.infinity,
                                      child: card(sections[index]),
                                    ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _question(9, text, summary: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _question(
    int question,
    String Function(String) text, {
    bool summary = false,
  }) => ReviewAnswerField(
    key: ValueKey('review-answer-field-q$question'),
    field: 'q$question',
    label: text('reviewQ$question'),
    controller: controllers['q$question']!,
    summary: summary,
    doneLabel: context.l10n.isZh ? '完成' : 'Done',
    editLabel: context.l10n.isZh ? '编辑' : 'Edit',
    onChanged: (value) => widget.session.edit('q$question', value),
  );
}
