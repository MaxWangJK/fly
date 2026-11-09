import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics/analytics_service.dart';
import '../core/updates/update_controller.dart';

/// Mounted only by the configured application runtime, after normal startup.
class StartupServicesRuntime extends ConsumerStatefulWidget {
  const StartupServicesRuntime({
    required this.analyticsFactory,
    required this.child,
    super.key,
  });
  final Future<AnalyticsService> Function() analyticsFactory;
  final Widget child;
  @override
  ConsumerState<StartupServicesRuntime> createState() =>
      _StartupServicesRuntimeState();
}

class _StartupServicesRuntimeState extends ConsumerState<StartupServicesRuntime>
    with WidgetsBindingObserver {
  Future<AnalyticsService>? _analytics;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_report());
      unawaited(ref.read(updateControllerProvider).check(silent: true));
    });
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
    if (state == AppLifecycleState.resumed) unawaited(_report());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
