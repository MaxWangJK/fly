import '../../../l10n/crm_copy.dart';
import '../../../l10n/fly_localizations.dart';
import '../../../l10n/service_error_copy.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/design_system/design_tokens.dart';
import '../../../shared/design_system/fly_color_scheme.dart';
import '../../../shared/design_system/workspace_empty_state.dart';
import '../../tasks/presentation/task_providers.dart';
import '../data/dashboard_service.dart';
import '../domain/dashboard_snapshot.dart';

final dashboardServiceProvider = Provider<DashboardService>(
  (ref) => DashboardService(ref.watch(databaseProvider)),
);
final dashboardProvider = StreamProvider.autoDispose<DashboardSnapshot>((ref) {
  ref.watch(localTodayProvider);
  return ref.watch(dashboardServiceProvider).watch();
});

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(dashboardProvider);
    final clarityStyle = ref.watch(flyPaletteProvider) == FlyPaletteId.clarity;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dashboard',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                context.crmCopy('今天最值得关注的五件事'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              Expanded(
                child: value.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator.adaptive()),
                  error: (error, stack) => Center(
                    child: Text(
                      (context.l10n.isZh
                          ? 'Dashboard 读取失败：${context.flyError(error)}'
                          : 'Unable to load dashboard: ${context.flyError(error)}'),
                    ),
                  ),
                  data: (data) => !data.hasBusinessData
                      ? WorkspaceEmptyState(
                          icon: Icons.home_outlined,
                          title: context.l10n.isZh
                              ? '从第一件事开始'
                              : 'Start with your first task',
                          actionLabel: context.l10n.t('addTask'),
                          onCreate: () => context.go('/tasks/today'),
                        )
                      : clarityStyle
                      ? _ClarityDashboard(data: data)
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth >= 980 ? 3 : 2;
                            return GridView.count(
                              crossAxisCount: columns,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              childAspectRatio: columns == 3 ? 1.55 : 1.7,
                              children: [
                                _DashboardCard(
                                  title: context.crmCopy('今天需跟进客户'),
                                  value: '${data.todayCustomers.length}',
                                  icon: Icons.people_outline,
                                  entries: data.todayCustomers,
                                  onTap: () => context.go('/customers/today'),
                                ),
                                _DashboardCard(
                                  title: context.crmCopy('今天任务'),
                                  value: '${data.todayTasks.length}',
                                  icon: Icons.check_box_outlined,
                                  entries: data.todayTasks,
                                  onTap: () => context.go('/tasks/today'),
                                ),
                                _DashboardCard(
                                  title: context.crmCopy('待收款订单'),
                                  value: '${data.outstandingOrders.length}',
                                  subtitle: _currencyTotals(
                                    data.outstandingByCurrency,
                                  ),
                                  icon: Icons.account_balance_wallet_outlined,
                                  entries: data.outstandingOrders,
                                  onTap: () =>
                                      context.go('/orders/outstanding'),
                                ),
                                _DashboardCard(
                                  title: context.crmCopy('紧急订单'),
                                  value: '${data.urgentOrders.length}',
                                  icon: Icons.priority_high_rounded,
                                  entries: data.urgentOrders,
                                  onTap: () => context.go('/orders/urgent'),
                                ),
                                _DashboardCard(
                                  title: context.crmCopy('本月利润'),
                                  value:
                                      'RMB ${(data.monthProfitRmb / 100).toStringAsFixed(2)}',
                                  subtitle: data.monthMissingRateCount == 0
                                      ? context.crmCopy('按订单日期统计')
                                      : (context.l10n.isZh
                                            ? '另有 ${data.monthMissingRateCount} 个订单缺少汇率'
                                            : '${data.monthMissingRateCount} other orders have no exchange rate'),
                                  icon: Icons.trending_up_rounded,
                                  entries: const [],
                                  onTap: () => context.go('/orders/all'),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact overview for the Clarity palette. The bars compare current work
/// counts only; they intentionally do not imply a historical trend.
class _ClarityDashboard extends StatelessWidget {
  const _ClarityDashboard({required this.data});

  final DashboardSnapshot data;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = width >= 1120
          ? 5
          : width >= 720
          ? 3
          : width >= 440
          ? 2
          : 1;
      final metrics = [
        (
          context.crmCopy('今天需跟进客户'),
          '${data.todayCustomers.length}',
          Icons.people_outline,
          '/customers/today',
        ),
        (
          context.crmCopy('今天任务'),
          '${data.todayTasks.length}',
          Icons.check_box_outlined,
          '/tasks/today',
        ),
        (
          context.crmCopy('待收款订单'),
          '${data.outstandingOrders.length}',
          Icons.account_balance_wallet_outlined,
          '/orders/outstanding',
        ),
        (
          context.crmCopy('紧急订单'),
          '${data.urgentOrders.length}',
          Icons.priority_high_rounded,
          '/orders/urgent',
        ),
        (
          context.crmCopy('本月利润'),
          'RMB ${(data.monthProfitRmb / 100).toStringAsFixed(2)}',
          Icons.trending_up_rounded,
          '/orders/all',
        ),
      ];
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: 128,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: metrics.length,
              itemBuilder: (context, index) {
                final item = metrics[index];
                return _ClarityMetricCard(
                  title: item.$1,
                  value: item.$2,
                  icon: item.$3,
                  prominent: index == 0,
                  onTap: () => context.go(item.$4),
                );
              },
            ),
            const SizedBox(height: 16),
            SizedBox(height: 212, child: _ClarityDistributionCard(data: data)),
            const SizedBox(height: 16),
            if (width >= 660)
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 196,
                      child: _ClarityListCard(
                        title: context.crmCopy('今天需跟进客户'),
                        entries: data.todayCustomers,
                        onTap: () => context.go('/customers/today'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 196,
                      child: _ClarityListCard(
                        title: context.crmCopy('紧急订单'),
                        entries: data.urgentOrders,
                        onTap: () => context.go('/orders/urgent'),
                      ),
                    ),
                  ),
                ],
              )
            else ...[
              SizedBox(
                height: 196,
                child: _ClarityListCard(
                  title: context.crmCopy('今天需跟进客户'),
                  entries: data.todayCustomers,
                  onTap: () => context.go('/customers/today'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 196,
                child: _ClarityListCard(
                  title: context.crmCopy('紧急订单'),
                  entries: data.urgentOrders,
                  onTap: () => context.go('/orders/urgent'),
                ),
              ),
            ],
            if (data.outstandingByCurrency.isNotEmpty ||
                data.monthMissingRateCount > 0) ...[
              const SizedBox(height: 12),
              Text(
                [
                  if (data.outstandingByCurrency.isNotEmpty)
                    '${context.crmCopy('待收款订单')} · ${_currencyTotals(data.outstandingByCurrency)}',
                  if (data.monthMissingRateCount > 0)
                    context.l10n.isZh
                        ? '${data.monthMissingRateCount} 个订单缺少汇率'
                        : '${data.monthMissingRateCount} orders have no exchange rate',
                ].join('    '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _ClarityMetricCard extends StatelessWidget {
  const _ClarityMetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.onTap,
    required this.prominent,
  });

  final String title;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final colors = context.flyColors;
    return Material(
      color: prominent
          ? Color.alphaBlend(
              colors.success.withValues(alpha: .085),
              colors.surface,
            )
          : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FlyRadius.md),
        side: BorderSide(
          color: prominent
              ? colors.success.withValues(alpha: .28)
              : colors.divider,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: (prominent ? colors.success : colors.accent)
                          .withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      icon,
                      size: 17,
                      color: prominent ? colors.success : colors.accent,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_outward_rounded,
                    size: 15,
                    color: colors.textSecondary,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: value.length > 9 ? 19 : 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClarityDistributionCard extends StatelessWidget {
  const _ClarityDistributionCard({required this.data});

  final DashboardSnapshot data;

  @override
  Widget build(BuildContext context) {
    final colors = context.flyColors;
    final values = [
      (context.crmCopy('今天需跟进客户'), data.todayCustomers.length),
      (context.crmCopy('今天任务'), data.todayTasks.length),
      (context.crmCopy('待收款订单'), data.outstandingOrders.length),
      (context.crmCopy('紧急订单'), data.urgentOrders.length),
    ];
    final highest = values
        .map((item) => item.$2)
        .reduce((a, b) => a > b ? a : b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.isZh ? '当前工作分布' : 'Current work overview',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 3),
            Text(
              context.l10n.isZh
                  ? '按当前待处理数量比较，不代表历史趋势'
                  : 'Current counts only, not a historical trend',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < values.length; i++)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '${values[i].$2}',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 5),
                          Container(
                            width: 34,
                            height: highest == 0
                                ? 4
                                : (values[i].$2 / highest * 60 + 4),
                            decoration: BoxDecoration(
                              color: i.isEven ? colors.accent : colors.success,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            values[i].$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
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

class _ClarityListCard extends StatelessWidget {
  const _ClarityListCard({
    required this.title,
    required this.entries,
    required this.onTap,
  });

  final String title;
  final List<DashboardEntry> entries;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FlyRadius.md),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 17,
                  color: context.flyColors.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Text(
                context.l10n.isZh ? '当前没有待处理项目' : 'Nothing to handle now',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              for (final entry in entries.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: context.flyColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    ),
  );
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.entries,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final List<DashboardEntry> entries;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(FlyRadius.lg),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FlyRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(FlyRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 12),
              ],
            ),
            const SizedBox(height: 11),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(subtitle!, style: Theme.of(context).textTheme.labelSmall),
            const Spacer(),
            for (final entry in entries.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '• ${entry.title}${entry.subtitle.isEmpty ? '' : ' · ${entry.subtitle}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

String _currencyTotals(Map<String, int> values) => values.entries
    .map(
      (entry) =>
          '${entry.key == 'CNY' ? 'RMB' : entry.key} ${(entry.value / 100).toStringAsFixed(2)}',
    )
    .join(' · ');
