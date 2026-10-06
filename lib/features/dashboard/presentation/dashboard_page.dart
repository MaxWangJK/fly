import 'dart:math' as math;

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
import 'dashboard_focus_board.dart';

final dashboardServiceProvider = Provider<DashboardService>(
  (ref) => DashboardService(ref.watch(databaseProvider)),
);
final dashboardProvider = StreamProvider.autoDispose<DashboardSnapshot>((ref) {
  ref.watch(localTodayProvider);
  return ref.watch(dashboardServiceProvider).watch();
});

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  bool historyOpen = false;

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(dashboardProvider);
    final day = ref.watch(localTodayProvider);
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, bounds) => Stack(
            children: [
              Positioned.fill(
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
                          loading: () => const Center(
                            child: CircularProgressIndicator.adaptive(),
                          ),
                          error: (error, stack) => Center(
                            child: Text(
                              context.l10n.isZh
                                  ? 'Dashboard 读取失败：${context.flyError(error)}'
                                  : 'Unable to load dashboard: ${context.flyError(error)}',
                            ),
                          ),
                          data: (data) => _DashboardOverview(
                            data: data,
                            day: day,
                            onHistory: () => setState(() => historyOpen = true),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (historyOpen) ...[
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => historyOpen = false),
                    child: ColoredBox(
                      color: context.flyColors.textPrimary.withValues(
                        alpha: .08,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  width: math.min(390, bounds.maxWidth),
                  child: DashboardFocusHistoryPanel(
                    onClose: () => setState(() => historyOpen = false),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardOverview extends StatelessWidget {
  const _DashboardOverview({
    required this.data,
    required this.day,
    required this.onHistory,
  });

  final DashboardSnapshot data;
  final DateTime day;
  final VoidCallback onHistory;

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
            DashboardFocusBoard(day: day, onHistory: onHistory),
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

String _currencyTotals(Map<String, int> values) => values.entries
    .map(
      (entry) =>
          '${entry.key == 'CNY' ? 'RMB' : entry.key} ${(entry.value / 100).toStringAsFixed(2)}',
    )
    .join(' · ');
