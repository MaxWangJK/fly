import '../../../l10n/crm_copy.dart';
import '../../../l10n/fly_localizations.dart';
import '../../../l10n/service_error_copy.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/design_system/design_tokens.dart';
import '../../../shared/design_system/fly_color_scheme.dart';
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
                      context.l10n.isZh
                          ? 'Dashboard 读取失败：${context.flyError(error)}'
                          : 'Unable to load dashboard: ${context.flyError(error)}',
                    ),
                  ),
                  data: (data) => _DashboardOverview(data: data),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardOverview extends StatelessWidget {
  const _DashboardOverview({required this.data});

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
                return _DashboardMetricCard(
                  title: item.$1,
                  value: item.$2,
                  icon: item.$3,
                  prominent: index == 0,
                  onTap: () => context.go(item.$4),
                );
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 212,
              child: _DashboardDistributionCard(data: data),
            ),
            const SizedBox(height: 16),
            if (width >= 660)
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 196,
                      child: _DashboardListCard(
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
                      child: _DashboardListCard(
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
                child: _DashboardListCard(
                  title: context.crmCopy('今天需跟进客户'),
                  entries: data.todayCustomers,
                  onTap: () => context.go('/customers/today'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 196,
                child: _DashboardListCard(
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

class _DashboardMetricCard extends StatelessWidget {
  const _DashboardMetricCard({
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

/// These bars compare current work counts; they are not a historical trend.
class _DashboardDistributionCard extends StatelessWidget {
  const _DashboardDistributionCard({required this.data});

  final DashboardSnapshot data;

  @override
  Widget build(BuildContext context) {
    final colors = context.flyColors;
    final values = [
      (
        context.crmCopy('今天需跟进客户'),
        data.todayCustomers.length,
        '/customers/today',
      ),
      (context.crmCopy('今天任务'), data.todayTasks.length, '/tasks/today'),
      (
        context.crmCopy('待收款订单'),
        data.outstandingOrders.length,
        '/orders/outstanding',
      ),
      (context.crmCopy('紧急订单'), data.urgentOrders.length, '/orders/urgent'),
      (
        context.l10n.isZh ? '重要且紧急' : 'Important & urgent',
        data.importantUrgentTasks.length,
        '/matrix',
      ),
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final chart = SizedBox(
                    width: constraints.maxWidth < 560
                        ? 560
                        : constraints.maxWidth,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < values.length; i++)
                          Expanded(
                            child: InkWell(
                              key: ValueKey('dashboard-distribution-$i'),
                              borderRadius: BorderRadius.circular(FlyRadius.sm),
                              onTap: () => context.go(values[i].$3),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    '${values[i].$2}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge,
                                  ),
                                  const SizedBox(height: 5),
                                  Container(
                                    width: 34,
                                    height: highest == 0
                                        ? 4
                                        : values[i].$2 / highest * 60 + 4,
                                    decoration: BoxDecoration(
                                      color: i == 4
                                          ? colors.warning
                                          : i.isEven
                                          ? colors.accent
                                          : colors.success,
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                  return constraints.maxWidth < 560
                      ? SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: chart,
                        )
                      : chart;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardListCard extends StatelessWidget {
  const _DashboardListCard({
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
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
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

String _currencyTotals(Map<String, int> values) => values.entries
    .map(
      (entry) =>
          '${entry.key == 'CNY' ? 'RMB' : entry.key} ${(entry.value / 100).toStringAsFixed(2)}',
    )
    .join(' · ');
