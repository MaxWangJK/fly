import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/fly_localizations.dart';
import '../../../shared/design_system/responsive_layout.dart';
import '../../tasks/presentation/task_providers.dart';
import '../../tasks/presentation/widgets/task_view_links.dart';
import '../data/daily_review_repository.dart';
import '../domain/review_program.dart';
import 'guided_review_providers.dart';
import 'review_answer_field.dart';
import 'review_providers.dart';

enum _ReviewView { daily, week, history }

class GuidedReviewPage extends ConsumerStatefulWidget {
  const GuidedReviewPage({
    required this.onChooseProgram,
    this.preview = false,
    this.onStart,
    super.key,
  });
  final VoidCallback onChooseProgram;
  final VoidCallback? onStart;
  final bool preview;
  @override
  ConsumerState<GuidedReviewPage> createState() => _GuidedReviewPageState();
}

class _GuidedReviewPageState extends ConsumerState<GuidedReviewPage> {
  String? selected;
  bool changing = false;
  Future<void> _date(String from, String to) async {
    if (widget.preview || changing || from == to) return;
    setState(() => changing = true);
    try {
      await ref.read(guidedReviewSessionsProvider)[from]?.flush();
      if (mounted) setState(() => selected = to);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.isZh
                  ? '请先重试保存，再切换日期。'
                  : 'Retry saving before changing the date.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => changing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(localTodayProvider);
    final day = selected ?? DailyReviewRepository.key(today);
    Widget body(ReviewSession? session) => _GuidedBody(
      key: ValueKey('guided-body-$day-${widget.preview}'),
      day: day,
      today: today,
      session: session,
      preview: widget.preview,
      changing: changing,
      onDate: (next) => _date(day, next),
      onChooseProgram: widget.onChooseProgram,
      onStart: widget.onStart,
    );
    return Column(
      children: [
        if (isPhoneLayout(context)) const TaskViewLinks(current: 'review'),
        Expanded(
          child: widget.preview
              ? body(null)
              : ref
                    .watch(guidedReviewSessionProvider(day))
                    .when(
                      loading: () => const Center(
                        child: CircularProgressIndicator.adaptive(),
                      ),
                      error: (_, _) => Center(
                        child: TextButton.icon(
                          onPressed: () =>
                              ref.invalidate(guidedReviewSessionProvider(day)),
                          icon: const Icon(Icons.refresh),
                          label: Text(context.l10n.t('reviewRetry')),
                        ),
                      ),
                      data: body,
                    ),
        ),
      ],
    );
  }
}

class _GuidedBody extends ConsumerStatefulWidget {
  const _GuidedBody({
    required this.day,
    required this.today,
    required this.session,
    required this.preview,
    required this.changing,
    required this.onDate,
    required this.onChooseProgram,
    this.onStart,
    super.key,
  });
  final String day;
  final DateTime today;
  final ReviewSession? session;
  final bool preview, changing;
  final ValueChanged<String> onDate;
  final VoidCallback onChooseProgram;
  final VoidCallback? onStart;
  @override
  ConsumerState<_GuidedBody> createState() => _GuidedBodyState();
}

class _GuidedBodyState extends ConsumerState<_GuidedBody> {
  _ReviewView view = _ReviewView.daily;
  int historyLimit = 20;
  bool working = false;
  Map<String, String> get sample => _example(zh);
  Map<String, String> get values => widget.session?.values ?? sample;
  final controllers = <String, TextEditingController>{};
  bool get zh => context.l10n.isZh;
  String t(String cn, String en) => zh ? cn : en;

  @override
  void initState() {
    super.initState();
    for (final id in [
      ...guidedPrompts.map((p) => p.id),
      ...weeklyPrompts.map((p) => p.id),
      GuidedReview.revisit,
    ]) {
      controllers[id] = TextEditingController(
        text: widget.session?.values[id] ?? '',
      );
    }
    widget.session?.addListener(_receive);
  }

  void _receive() {
    for (final entry in controllers.entries) {
      final text = values[entry.key] ?? '';
      if (entry.value.text != text) entry.value.text = text;
    }
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _GuidedBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.session, widget.session)) return;
    oldWidget.session?.removeListener(_receive);
    widget.session?.addListener(_receive);
    _receive();
  }

  @override
  void dispose() {
    widget.session?.removeListener(_receive);
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save({bool close = false, bool task = false}) async {
    if (working || widget.preview) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => working = true);
    try {
      final session = widget.session!;
      await session.flush();
      if (task) {
        final id = await ref
            .read(guidedReviewActionsProvider)
            .createNextTask(widget.day);
        session.receive({...session.values, GuidedReview.taskId: id});
      }
      if (close) {
        session.edit(GuidedReview.closed, 'true');
        await session.flush();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                '保存未完成，内容已留在当前页面，请重试。',
                'Save did not finish. Your edits are still here; please retry.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.preview
        ? AsyncValue<List<ReviewHistoryEntry>>.data([
            ReviewHistoryEntry(day: widget.day, answers: sample),
          ])
        : ref.watch(guidedReviewHistoryProvider);
    final entries = history.valueOrNull ?? [];
    final date = DailyReviewRepository.date(widget.day);
    final completed = GuidedReview.completed(values);
    final colors = Theme.of(context).colorScheme;
    return ListView(
      key: PageStorageKey(
        'guided-${widget.preview}-${view.name}-${widget.day}',
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      t('航向复盘', 'Compass review'),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    TextButton.icon(
                      key: const ValueKey('review-choose-program'),
                      onPressed: working ? null : widget.onChooseProgram,
                      icon: Icon(
                        widget.preview
                            ? Icons.arrow_back
                            : Icons.style_outlined,
                        size: 18,
                      ),
                      label: Text(
                        widget.preview
                            ? t('返回方案', 'Back to programs')
                            : t('复盘方案', 'Review programs'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _notice(
                  widget.preview
                      ? t(
                          '示例浏览 · 以下为演示内容，不会写入你的记录。',
                          'Example only · These answers will not be saved to your records.',
                        )
                      : t(
                          '进阶方案 · 当前免费体验，可保存真实记录，不产生费用。',
                          'Pro open preview · Save real reflections at no charge.',
                        ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: t('前一天', 'Previous day'),
                      onPressed:
                          widget.preview ||
                              widget.changing ||
                              !date.isAfter(DateTime(2000))
                          ? null
                          : () => widget.onDate(
                              DailyReviewRepository.key(
                                DateTime(date.year, date.month, date.day - 1),
                              ),
                            ),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    TextButton.icon(
                      key: const ValueKey('guided-date'),
                      onPressed: widget.preview || widget.changing
                          ? null
                          : () async {
                              final next = await showDatePicker(
                                context: context,
                                initialDate: date,
                                firstDate: date.isBefore(DateTime(2000))
                                    ? date
                                    : DateTime(2000),
                                lastDate: date.isAfter(widget.today)
                                    ? date
                                    : widget.today,
                              );
                              if (next != null && mounted) {
                                widget.onDate(DailyReviewRepository.key(next));
                              }
                            },
                      icon: const Icon(Icons.calendar_today_outlined, size: 17),
                      label: Text(widget.day),
                    ),
                    IconButton(
                      tooltip: t('后一天', 'Next day'),
                      onPressed:
                          widget.preview ||
                              widget.changing ||
                              widget.day.compareTo(
                                    DailyReviewRepository.key(widget.today),
                                  ) >=
                                  0
                          ? null
                          : () => widget.onDate(
                              DailyReviewRepository.key(
                                DateTime(date.year, date.month, date.day + 1),
                              ),
                            ),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SegmentedButton<_ReviewView>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: _ReviewView.daily,
                      label: Text(t('每日航向', 'Daily')),
                    ),
                    ButtonSegment(
                      value: _ReviewView.week,
                      label: Text(t('七日校准', '7 days')),
                    ),
                    ButtonSegment(
                      value: _ReviewView.history,
                      label: Text(t('航向历史', 'History')),
                    ),
                  ],
                  selected: {view},
                  onSelectionChanged: (next) {
                    FocusManager.instance.primaryFocus?.unfocus();
                    setState(() => view = next.single);
                  },
                ),
                const SizedBox(height: 20),
                if (!widget.preview) _saveStatus(),
                if (view == _ReviewView.daily) ...[
                  Text(
                    t('看见变化，试一小步', 'Notice a change. Try a small step.'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t(
                      '约 5 分钟 · 允许留白，先写最值得回看的事。',
                      'About 5 minutes · Start with what matters. You can leave prompts blank.',
                    ),
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t(
                      '已记录 $completed / 5 个提示',
                      '$completed / 5 prompts explored',
                    ),
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: completed / 5,
                    semanticsLabel: t('记录进度', 'Reflection progress'),
                  ),
                  const SizedBox(height: 16),
                  if (values[GuidedReview.closed] == 'true' && !widget.preview)
                    _reflectionCard(
                      ReviewHistoryEntry(day: widget.day, answers: values),
                      editing: true,
                    )
                  else ...[
                    _revisit(entries),
                    _contextChoices(),
                    for (var i = 0; i < guidedPrompts.length; i++)
                      _prompt(guidedPrompts[i], '${i + 1}'.padLeft(2, '0')),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('guided-close'),
                          onPressed: working || widget.preview || completed == 0
                              ? null
                              : () => _save(close: true),
                          icon: const Icon(Icons.check_rounded),
                          label: Text(t('收好今天', 'Keep this reflection')),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('guided-create-task'),
                          onPressed:
                              working ||
                                  widget.preview ||
                                  (values[GuidedReview.experiment]
                                          ?.trim()
                                          .isEmpty ??
                                      true) ||
                                  (values[GuidedReview.taskId]?.isNotEmpty ??
                                      false)
                              ? null
                              : () => _save(task: true),
                          icon: const Icon(Icons.add_task),
                          label: Text(
                            (values[GuidedReview.taskId]?.isNotEmpty ?? false)
                                ? t('已加入任务', 'Task created')
                                : t(
                                    '小实验加入次日任务',
                                    'Add experiment to next-day tasks',
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ] else if (view == _ReviewView.week)
                  _week(history)
                else
                  _history(history),
                if (widget.preview)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: FilledButton.icon(
                      key: const ValueKey('guided-preview-start'),
                      onPressed: widget.onStart,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(
                        t('开始免费体验，写我的复盘', 'Try it free with my own reflection'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _saveStatus() {
    final session = widget.session!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: session.error != null
          ? _notice(
              t(
                '保存失败，当前内容仍保留。',
                'Save failed. Your current edits are preserved.',
              ),
              action: TextButton(
                onPressed: working ? null : _save,
                child: Text(t('重试保存', 'Retry save')),
              ),
            )
          : Text(
              session.saving
                  ? t('正在保存…', 'Saving…')
                  : t('已保存到本机', 'Saved on this device'),
              style: Theme.of(context).textTheme.labelSmall,
            ),
    );
  }

  Widget _notice(String message, {Widget? action}) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
        ),
        ?action,
      ],
    ),
  );

  Widget _contextChoices() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        t('今天从哪个角度看？', 'Choose a lens for today'),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final item in [
            ('work', t('工作', 'Work')),
            ('life', t('生活', 'Life')),
            ('growth', t('成长', 'Growth')),
            ('connection', t('关系与陪伴', 'Connection')),
          ])
            ChoiceChip(
              label: Text(item.$2),
              selected: values[GuidedReview.lens] == item.$1,
              onSelected: widget.preview
                  ? null
                  : (selected) => widget.session!.edit(
                      GuidedReview.lens,
                      selected ? item.$1 : '',
                    ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        t('此刻的精力', 'Your energy now'),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final item in [
            ('low', t('需要恢复', 'Need rest')),
            ('steady', t('平稳', 'Steady')),
            ('high', t('充足', 'Energized')),
          ])
            ChoiceChip(
              label: Text(item.$2),
              selected: values[GuidedReview.energy] == item.$1,
              onSelected: widget.preview
                  ? null
                  : (selected) => widget.session!.edit(
                      GuidedReview.energy,
                      selected ? item.$1 : '',
                    ),
            ),
        ],
      ),
      const SizedBox(height: 8),
    ],
  );

  Widget _prompt(ReviewPrompt prompt, String number) => Card(
    key: ValueKey('guided-prompt-${prompt.id}'),
    margin: const EdgeInsets.only(top: 12),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                number,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  zh ? prompt.zh : prompt.en,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            zh ? prompt.hintZh : prompt.hintEn,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          if (widget.preview)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                sample[prompt.id] ?? '',
                style: const TextStyle(height: 1.7),
              ),
            )
          else
            ReviewAnswerField(
              field: prompt.id,
              label: t('你的记录', 'Your reflection'),
              controller: controllers[prompt.id]!,
              onChanged: (text) => widget.session!.edit(prompt.id, text),
              doneLabel: t('完成', 'Done'),
              editLabel: t('编辑', 'Edit'),
            ),
        ],
      ),
    ),
  );

  Widget _revisit(List<ReviewHistoryEntry> history) {
    final source = values[GuidedReview.revisitDay];
    final previous = history
        .where(
          (entry) =>
              entry.day.compareTo(widget.day) < 0 &&
              (source == null || source.isEmpty || source == entry.day) &&
              (entry.answers[GuidedReview.experiment]?.trim().isNotEmpty ??
                  false),
        )
        .firstOrNull;
    if (previous == null) return const SizedBox.shrink();
    return Card(
      key: const ValueKey('guided-revisit'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('回看上一次小实验', 'Revisit your last experiment'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${previous.day} · ${previous.answers[GuidedReview.experiment]}',
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final result in [
                  ('helped', t('有帮助', 'Helped')),
                  ('adjust', t('调整后再试', 'Adjust and retry')),
                  ('not_yet', t('还没尝试', 'Not yet')),
                ])
                  ChoiceChip(
                    label: Text(result.$2),
                    selected: values[GuidedReview.outcome] == result.$1,
                    onSelected: widget.preview
                        ? null
                        : (selected) {
                            widget.session!.edit(
                              GuidedReview.revisitDay,
                              previous.day,
                            );
                            widget.session!.edit(
                              GuidedReview.outcome,
                              selected ? result.$1 : '',
                            );
                          },
                  ),
              ],
            ),
            if (!widget.preview)
              ReviewAnswerField(
                field: GuidedReview.revisit,
                label: t(
                  '发生了什么，下次怎样调整？（可选）',
                  'What happened? What would you adjust? (optional)',
                ),
                controller: controllers[GuidedReview.revisit]!,
                onChanged: (text) {
                  widget.session!.edit(GuidedReview.revisitDay, previous.day);
                  widget.session!.edit(GuidedReview.revisit, text);
                },
                doneLabel: t('完成', 'Done'),
                editLabel: t('编辑', 'Edit'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _week(AsyncValue<List<ReviewHistoryEntry>> history) {
    final date = DailyReviewRepository.date(widget.day);
    final from = DailyReviewRepository.key(
      DateTime(date.year, date.month, date.day - 6),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t('七日校准', 'Seven-day checkpoint'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text('$from — ${widget.day}'),
        const SizedBox(height: 8),
        Text(
          t(
            '回看所选日期及之前六天。抓住一个有效做法，给下一周减一点阻力。',
            'Review the selected date and the six days before it. Keep one useful practice and reduce one friction.',
          ),
        ),
        const SizedBox(height: 16),
        history.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => _historyError(),
          data: (all) {
            final entries = all
                .where(
                  (e) =>
                      e.day.compareTo(from) >= 0 &&
                      e.day.compareTo(widget.day) <= 0,
                )
                .toList();
            final reflected = entries
                .where((e) => GuidedReview.completed(e.answers) > 0)
                .length;
            final experiments = entries
                .where(
                  (e) =>
                      e.answers[GuidedReview.experiment]?.trim().isNotEmpty ??
                      false,
                )
                .length;
            final revisits = entries
                .where(
                  (e) => e.answers[GuidedReview.outcome]?.isNotEmpty ?? false,
                )
                .length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _notice(
                  t(
                    '$reflected 天留下观察 · $experiments 个小实验 · $revisits 次结果回看',
                    '$reflected days reflected · $experiments experiments · $revisits revisits',
                  ),
                ),
                const SizedBox(height: 12),
                for (var offset = 6; offset >= 0; offset--)
                  Builder(
                    builder: (context) {
                      final key = DailyReviewRepository.key(
                        DateTime(date.year, date.month, date.day - offset),
                      );
                      final entry = entries
                          .where((e) => e.day == key)
                          .firstOrNull;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          entry == null ? Icons.circle_outlined : Icons.circle,
                          size: 12,
                        ),
                        title: Text(key),
                        subtitle: Text(
                          entry?.answers[GuidedReview.progress]
                                      ?.trim()
                                      .isNotEmpty ??
                                  false
                              ? entry!.answers[GuidedReview.progress]!
                              : t(
                                  '留白的一天，也可以继续补记',
                                  'A blank day; you can return to it',
                                ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: widget.preview || widget.changing
                            ? null
                            : () {
                                setState(() => view = _ReviewView.daily);
                                widget.onDate(key);
                              },
                      );
                    },
                  ),
              ],
            );
          },
        ),
        for (var i = 0; i < weeklyPrompts.length; i++)
          _prompt(weeklyPrompts[i], '${i + 1}'.padLeft(2, '0')),
        const SizedBox(height: 12),
        Text(
          t(
            '校准笔记保存在所选日期，之后仍可修改。',
            'Checkpoint notes are saved on the selected date and remain editable.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _history(AsyncValue<List<ReviewHistoryEntry>> history) => history.when(
    loading: () => const LinearProgressIndicator(),
    error: (_, _) => _historyError(),
    data: (entries) => entries.isEmpty
        ? _notice(
            t(
              '第一份航向复盘会留在这里。基础复盘的历史仍在基础方案中。',
              'Your first Compass reflection will appear here. Basic history is still in the everyday program.',
            ),
          )
        : Column(
            children: [
              for (final entry in entries.take(historyLimit))
                _reflectionCard(entry),
              if (entries.length > historyLimit)
                TextButton(
                  onPressed: () => setState(() => historyLimit += 20),
                  child: Text(t('显示更多记录', 'Show more reflections')),
                ),
            ],
          ),
  );
  Widget _historyError() => TextButton.icon(
    onPressed: () => ref.invalidate(guidedReviewHistoryProvider),
    icon: const Icon(Icons.refresh),
    label: Text(t('重试载入历史', 'Retry history')),
  );

  Widget _reflectionCard(
    ReviewHistoryEntry entry, {
    bool editing = false,
  }) => Card(
    key: ValueKey('guided-history-${entry.day}'),
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(entry.day, style: Theme.of(context).textTheme.titleMedium),
          if (_contextLabels(entry.answers).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _contextLabels(entry.answers).join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          for (final prompt in [...guidedPrompts, ...weeklyPrompts])
            if (entry.answers[prompt.id]?.trim().isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      zh ? prompt.zh : prompt.en,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.answers[prompt.id]!,
                      style: const TextStyle(height: 1.6),
                    ),
                  ],
                ),
              ),
          if (entry.answers[GuidedReview.revisit]?.trim().isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                '${t('实验回看', 'Experiment revisit')} · ${entry.answers[GuidedReview.revisit]}',
              ),
            ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.preview || widget.changing
                  ? null
                  : editing
                  ? () => widget.session!.edit(GuidedReview.closed, 'false')
                  : () {
                      setState(() => view = _ReviewView.daily);
                      widget.onDate(entry.day);
                    },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(
                editing
                    ? t('继续编辑', 'Continue editing')
                    : t('打开这一天', 'Open this day'),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  List<String> _contextLabels(Map<String, String> answers) => [
    ?{
      'work': t('工作', 'Work'),
      'life': t('生活', 'Life'),
      'growth': t('成长', 'Growth'),
      'connection': t('关系与陪伴', 'Connection'),
    }[answers[GuidedReview.lens]],
    ?{
      'low': t('需要恢复', 'Need rest'),
      'steady': t('精力平稳', 'Steady energy'),
      'high': t('精力充足', 'Energized'),
    }[answers[GuidedReview.energy]],
    ?{
      'helped': t('上次实验有帮助', 'Last experiment helped'),
      'adjust': t('上次实验需调整', 'Adjust last experiment'),
      'not_yet': t('上次实验待尝试', 'Last experiment not tried yet'),
    }[answers[GuidedReview.outcome]],
  ];
}

Map<String, String> _example(bool zh) => {
  GuidedReview.lens: 'work',
  GuidedReview.energy: 'steady',
  GuidedReview.progress: zh ? '把一份复杂报价整理成了两个清晰方案，客户终于给出了交期要求。' : 'Turned a complicated quote into two clear options. The customer shared a delivery requirement.',
  GuidedReview.facts: zh ? '原本希望今天确认订单，实际只收到一句“再看看”。我还没有确认对方的采购时间。' : 'I expected an order decision, but got “let me think.” I had not checked the buying timeline.',
  GuidedReview.insight: zh ? '目前只知道对方在比较方案，不能把沉默直接理解为没兴趣。我能改变的是提问的具体程度。' : 'I know they are comparing options. Silence alone does not mean no interest. I can ask a more specific question.',
  GuidedReview.experiment: zh ? '明早跟进时，只确认一个问题：最晚需要在哪天收到货？' : 'Tomorrow morning, ask one question: what is the latest acceptable delivery date?',
  GuidedReview.signal: zh ? '明天下午回看，是否拿到了明确日期；没有答复，就记录下来并调整联系时机。' : 'Tomorrow afternoon, check for a concrete date. If there is no reply, record it and reconsider timing.',
  GuidedReview.keep: zh
      ? '把开放式催问换成一个清晰的小问题。'
      : 'Replace a vague follow-up with one clear question.',
  GuidedReview.adjust: zh
      ? '不再根据短暂沉默判断客户意愿，先核实事实。'
      : 'Check facts before interpreting a short silence.',
  GuidedReview.direction: zh
      ? '为三个重点客户确认真实的采购时间。'
      : 'Confirm the actual buying timeline for three priority customers.',
};
