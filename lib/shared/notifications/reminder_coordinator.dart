import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/customers/presentation/customer_providers.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/orders/presentation/order_providers.dart';
import '../../features/tasks/presentation/task_providers.dart';
import 'notification_providers.dart';
import 'notification_service.dart';

class ReminderCoordinator extends ConsumerStatefulWidget {
  const ReminderCoordinator({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ReminderCoordinator> createState() =>
      _ReminderCoordinatorState();
}

class _ReminderCoordinatorState extends ConsumerState<ReminderCoordinator>
    with WidgetsBindingObserver {
  Timer? _timer;
  StreamSubscription<String>? _tapSubscription;
  late DateTime _day;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = DateTime.now();
    _day = DateTime(now.year, now.month, now.day);
    _tapSubscription = notificationTapStream.stream.listen(_openPayload);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (!mounted || _checking) return;
    _checking = true;
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    if (day != _day) {
      _day = day;
      ref.invalidate(todayTasksProvider);
      ref.invalidate(upcomingTasksProvider);
      ref.invalidate(customerListProvider);
      ref.invalidate(dashboardProvider);
    }
    try {
      await ref.read(notificationServiceProvider).checkAndDeliver();
    } on Object {
      // Reminders are best effort; the delivery log prevents retry duplicates.
    } finally {
      _checking = false;
    }
  }

  void _openPayload(String payload) {
    if (!mounted) return;
    final separator = payload.indexOf(':');
    if (separator <= 0) return;
    final type = payload.substring(0, separator);
    final id = payload.substring(separator + 1);
    switch (type) {
      case 'review':
        ref.read(selectedTaskIdProvider.notifier).state = null;
        context.go('/tasks/review');
      case 'customer':
        ref.read(selectedCustomerIdProvider.notifier).state = id;
        context.go('/customers/today');
      case 'order':
        ref.read(selectedOrderIdProvider.notifier).state = id;
        context.go('/orders/all');
      case 'task':
        ref.read(selectedTaskIdProvider.notifier).state = id;
        context.go('/tasks/today');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tapSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
