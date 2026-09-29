import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/fly_localizations.dart';
import '../../../shared/design_system/fly_color_scheme.dart';
import '../../tasks/presentation/task_providers.dart';
import '../data/daily_review_repository.dart';
import 'review_providers.dart';

class DailyReviewPage extends ConsumerStatefulWidget {
  const DailyReviewPage({super.key});
  @override
  ConsumerState<DailyReviewPage> createState() => _DailyReviewPageState();
}

class _DailyReviewPageState extends ConsumerState<DailyReviewPage> {
  String? selected;
  bool changingDay = false;

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
    final days = List.generate(
      7,
      (i) => DailyReviewRepository.key(
        DateTime(today.year, today.month, today.day - i),
      ),
    );
    final day = selected ?? days.first;
    final recorded = ref.watch(recordedReviewDaysProvider);
    final navigationDays = {
      ...?recorded.valueOrNull,
      days.first,
    }.where((value) => value.compareTo(days.first) <= 0).toList()..sort();
    final previous = navigationDays
        .where((value) => value.compareTo(day) < 0)
        .lastOrNull;
    final next = navigationDays
        .where((value) => value.compareTo(day) > 0)
        .firstOrNull;
    final text = FlyLocalizations(Localizations.localeOf(context)).t;
    final session = ref.watch(reviewSessionProvider(day));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
              TextButton.icon(
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(day),
                onPressed: changingDay
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
                onPressed: changingDay || previous == null
                    ? null
                    : () => changeDay(day, previous),
              ),
              TextButton.icon(
                icon: const Icon(Icons.chevron_right, size: 18),
                label: Text(context.l10n.isZh ? '后一天' : 'Next day'),
                onPressed: changingDay || next == null
                    ? null
                    : () => changeDay(day, next),
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
          child: session.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Center(
              child: TextButton(
                onPressed: () => ref.invalidate(reviewSessionProvider(day)),
                child: Text(text('reviewRetry')),
              ),
            ),
            data: (value) => _ReviewEditor(key: ValueKey(day), session: value),
          ),
        ),
      ],
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
  void dispose() {
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
      builder: (context, _) => LayoutBuilder(
        builder: (context, viewport) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
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
                  onPressed: () =>
                      ref.invalidate(reviewSummaryProvider(widget.session.day)),
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
                text(widget.session.saving ? 'reviewSaving' : 'reviewSaved'),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 700;
                final height = ((viewport.maxHeight - 240) / 2).clamp(
                  230.0,
                  600.0,
                );
                final colors = context.flyColors;
                const sections = [
                  (1, [1, 2]),
                  (2, [3, 4]),
                  (3, [5, 6, 7]),
                  (4, [8, 10, 11]),
                ];
                Widget card((int, List<int>) section) => Container(
                  key: ValueKey('review-section-${section.$1}'),
                  constraints: BoxConstraints(minHeight: height),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: [
                      colors.accent,
                      colors.warning,
                      colors.success,
                      colors.textSecondary,
                    ][section.$1 - 1].withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        text('reviewSection${section.$1}'),
                        style: Theme.of(context).textTheme.titleSmall,
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
                                    Expanded(child: card(sections[index])),
                                    const SizedBox(width: 16),
                                    Expanded(child: card(sections[index + 1])),
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
    );
  }

  Widget _question(
    int question,
    String Function(String) text, {
    bool summary = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      key: ValueKey('review-q$question'),
      controller: controllers['q$question'],
      minLines: summary ? 6 : 2,
      maxLines: null,
      maxLength: 20000,
      decoration: InputDecoration(
        labelText: text('reviewQ$question'),
        counterText: '',
        isDense: true,
      ),
      onChanged: (value) => widget.session.edit('q$question', value),
    ),
  );
}
