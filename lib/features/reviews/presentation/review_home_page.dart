import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/fly_localizations.dart';
import '../../../shared/design_system/responsive_layout.dart';
import '../../tasks/presentation/widgets/task_view_links.dart';
import '../domain/review_program.dart';
import 'daily_review_page.dart';
import 'guided_review_page.dart';
import 'guided_review_providers.dart';
import 'review_providers.dart';

/// Onboarding lives outside the existing basic editor and its history cards.
class ReviewHomePage extends ConsumerStatefulWidget {
  const ReviewHomePage({super.key});
  @override
  ConsumerState<ReviewHomePage> createState() => _ReviewHomePageState();
}

class _ReviewHomePageState extends ConsumerState<ReviewHomePage> {
  ReviewProgram? selected;
  bool choosing = false, preview = false, busy = false;

  Future<void> _flush() async {
    for (final session in [
      ...ref.read(reviewSessionsProvider).values,
      ...ref.read(guidedReviewSessionsProvider).values,
    ]) {
      await session.flush();
    }
  }

  void _error() => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        context.l10n.isZh ? '保存未完成，内容仍保留在编辑页。请重试。' : 'Save did not finish. Your edits are still in the editor. Please retry.',
      ),
    ),
  );

  Future<void> _choose(ReviewProgram program) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await _flush();
      await ref.read(reviewProgramRepositoryProvider).select(program);
      if (!mounted) return;
      setState(() {
        selected = program;
        choosing = false;
        preview = false;
      });
      ref.invalidate(reviewProgramPreferenceProvider);
    } catch (_) {
      if (mounted) _error();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _programs() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await _flush();
      if (mounted) setState(() => choosing = true);
    } catch (_) {
      if (mounted) _error();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preference = ref.watch(reviewProgramPreferenceProvider);
    final current = selected ?? preference.valueOrNull;
    final canReturn = preview || (choosing && current != null);
    return PopScope(
      canPop: !canReturn,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !busy) {
          setState(() {
            if (preview) {
              preview = false;
            } else {
              choosing = false;
            }
          });
        }
      },
      child: preview
          ? GuidedReviewPage(
              preview: true,
              onChooseProgram: () => setState(() => preview = false),
              onStart: busy ? null : () => _choose(ReviewProgram.guided),
            )
          : current != null && !choosing
          ? switch (current) {
              ReviewProgram.classic => DailyReviewPage(
                onChooseProgram: _programs,
              ),
              ReviewProgram.guided => GuidedReviewPage(
                onChooseProgram: _programs,
              ),
            }
          : preference.isLoading && selected == null
          ? const Center(child: CircularProgressIndicator.adaptive())
          : preference.hasError && selected == null
          ? Center(
              child: TextButton.icon(
                onPressed: () =>
                    ref.invalidate(reviewProgramPreferenceProvider),
                icon: const Icon(Icons.refresh),
                label: Text(
                  context.l10n.isZh ? '重新载入复盘方案' : 'Retry loading programs',
                ),
              ),
            )
          : _ProgramChooser(
              busy: busy,
              onClassic: () => _choose(ReviewProgram.classic),
              onGuided: () => _choose(ReviewProgram.guided),
              onPreview: () => setState(() => preview = true),
              onBack: current == null
                  ? null
                  : () => setState(() => choosing = false),
            ),
    );
  }
}

class _ProgramChooser extends StatelessWidget {
  const _ProgramChooser({
    required this.busy,
    required this.onClassic,
    required this.onGuided,
    required this.onPreview,
    this.onBack,
  });
  final bool busy;
  final VoidCallback onClassic, onGuided, onPreview;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final zh = context.l10n.isZh;
    final theme = Theme.of(context);
    return Column(
      children: [
        if (isPhoneLayout(context)) const TaskViewLinks(current: 'review'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (onBack != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: busy ? null : onBack,
                            icon: const Icon(Icons.arrow_back),
                            label: Text(zh ? '返回当前复盘' : 'Back to my review'),
                          ),
                        ),
                      Text(
                        zh ? '选择你的复盘方式' : 'Choose how you reflect',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        zh ? '保留今天的收获，也为明天留一个方向。两套记录独立，随时可以切换。' : 'Keep what today taught you. Leave tomorrow a direction. Each program keeps its own answers.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 24),
                      LayoutBuilder(
                        builder: (context, size) {
                          final cards = [
                            _ChoiceCard(
                              cardKey: 'review-program-classic',
                              number: '01',
                              icon: Icons.edit_note_rounded,
                              title: zh ? '基础复盘' : 'Everyday review',
                              badge: zh ? '默认 · 免费' : 'Default · Free',
                              description: zh ? '熟悉的提问，轻松记录每一天。' : 'Familiar prompts for an everyday reflection.',
                              features: zh
                                  ? ['保留现有全部题目', '填写后收起为复盘卡片', '原有历史记录完整保留']
                                  : [
                                      'All your existing prompts',
                                      'Answers become readable cards',
                                      'Your original history stays intact',
                                    ],
                              actions: [
                                FilledButton(
                                  key: const ValueKey('review-start-classic'),
                                  onPressed: busy ? null : onClassic,
                                  child: Text(
                                    zh ? '使用基础复盘' : 'Use everyday review',
                                  ),
                                ),
                              ],
                            ),
                            _ChoiceCard(
                              cardKey: 'review-program-guided',
                              number: '02',
                              icon: Icons.explore_outlined,
                              title: zh ? '航向复盘' : 'Compass review',
                              badge: zh
                                  ? '进阶 · 当前免费体验'
                                  : 'Pro · Free to explore',
                              description: zh ? '从一个真实变化，走到一个可验证的行动。' : 'Turn one real observation into an experiment.',
                              features: zh
                                  ? [
                                      '五步引导，工作与生活都适用',
                                      '小实验可加入任务，并回看结果',
                                      '七日校准，找到值得继续的做法',
                                    ]
                                  : [
                                      'Five prompts for work and life',
                                      'Turn an experiment into a task',
                                      'A seven-day checkpoint to find patterns',
                                    ],
                              actions: [
                                OutlinedButton(
                                  key: const ValueKey('review-preview-guided'),
                                  onPressed: busy ? null : onPreview,
                                  child: Text(zh ? '浏览示例' : 'View example'),
                                ),
                                FilledButton(
                                  key: const ValueKey('review-start-guided'),
                                  onPressed: busy ? null : onGuided,
                                  child: Text(zh ? '免费体验' : 'Try it free'),
                                ),
                              ],
                            ),
                          ];
                          return size.maxWidth >= 760
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: cards[0]),
                                    const SizedBox(width: 20),
                                    Expanded(child: cards[1]),
                                  ],
                                )
                              : Column(
                                  children: [
                                    cards[0],
                                    const SizedBox(height: 16),
                                    cards[1],
                                  ],
                                );
                        },
                      ),
                      const SizedBox(height: 20),
                      Text(
                        zh ? '进阶方案未来将收费；目前体验可保存记录，不产生费用，无需绑定支付方式。' : 'The advanced program is planned as a paid feature. You can save during this open preview, with no charge or payment details.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.6,
                        ),
                      ),
                      if (busy)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.cardKey,
    required this.number,
    required this.icon,
    required this.title,
    required this.badge,
    required this.description,
    required this.features,
    required this.actions,
  });
  final String cardKey, number, title, badge, description;
  final IconData icon;
  final List<String> features;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Card(
      key: ValueKey(cardKey),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 28, color: colors.primary),
                const Spacer(),
                Text(
                  number,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colors.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              badge,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(description, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 14),
            for (final feature in features)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_rounded, color: colors.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(feature, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      ),
    );
  }
}
