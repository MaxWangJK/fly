import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics/analytics_service.dart';
import '../core/updates/update_controller.dart';
import 'idle_maintenance_scheduler.dart';

/// Mounted only by the configured application runtime, after normal startup.
class StartupServicesRuntime extends ConsumerStatefulWidget {
  const StartupServicesRuntime({
    required this.analyticsFactory,
    required this.child,
    this.backup,
    super.key,
  });
  final Future<AnalyticsService> Function() analyticsFactory;
  final Widget child;
  final Future<void> Function()? backup;
  @override
  ConsumerState<StartupServicesRuntime> createState() =>
      _StartupServicesRuntimeState();
}

class _StartupServicesRuntimeState extends ConsumerState<StartupServicesRuntime>
    with WidgetsBindingObserver {
  Future<AnalyticsService>? _analytics;
  late final IdleMaintenanceScheduler _maintenance;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _maintenance = IdleMaintenanceScheduler(run: _maintain)..request();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_pointerActivity);
    HardwareKeyboard.instance.addHandler(_keyActivity);
  }

  void _pointerActivity(PointerEvent event) => _maintenance.activity();

  bool _keyActivity(KeyEvent event) {
    _maintenance.activity();
    return false;
  }

  Future<void> _maintain() async {
    if (!mounted) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      await widget.backup?.call();
    }
    if (!mounted) return;
    await _report();
    if (mounted) await ref.read(updateControllerProvider).check(silent: true);
  }

  Future<void> _report() async {
    try {
      final analytics = await (_analytics ??= widget.analyticsFactory());
      await analytics.initialize();
    } on Object {
      _analytics =
          null; // A temporary local configuration failure can retry later.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maintenance.resume();
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _maintenance.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointerActivity);
    HardwareKeyboard.instance.removeHandler(_keyActivity);
    _maintenance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
