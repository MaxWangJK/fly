import '../../../l10n/crm_copy.dart';
import '../../../l10n/fly_localizations.dart';
import '../../../l10n/service_error_copy.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/design_system/design_tokens.dart';
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
