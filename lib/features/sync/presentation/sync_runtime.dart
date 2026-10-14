import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/data_root_providers.dart';
import 'sync_controller.dart';

class SyncRuntime extends ConsumerStatefulWidget {
  const SyncRuntime({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<SyncRuntime> createState() => _SyncRuntimeState();
}

class _SyncRuntimeState extends ConsumerState<SyncRuntime>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(dataRootPathProvider) != null) {
      unawaited(ref.read(syncControllerProvider).resume());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (ref.read(dataRootPathProvider) != null) {
        unawaited(ref.read(syncControllerProvider).suspend());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(dataRootPathProvider) != null) {
      ref.watch(syncControllerProvider);
    }
    return widget.child;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
