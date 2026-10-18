import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/settings_center.dart';
import '../../../l10n/fly_localizations.dart';
import 'sync_controller.dart';
import 'sync_status_details.dart';

class MobileSyncButton extends ConsumerWidget {
  const MobileSyncButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final zh = context.l10n.isZh;
    final waiting = !sync.ready || sync.busy || sync.connecting;
    final color = sync.connected
        ? Colors.green.shade700
        : waiting
        ? Colors.orange.shade800
        : Theme.of(context).colorScheme.error;
    final label = sync.connected
        ? (sync.busy || sync.engine?.running == true
              ? (zh ? '同步中' : 'Syncing')
              : (zh ? '已连接' : 'Connected'))
        : waiting
        ? (zh ? '正在连接' : 'Connecting')
        : (zh ? '立即连接' : 'Connect now');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          key: const ValueKey('mobile-sync-button'),
          style: TextButton.styleFrom(
            foregroundColor: color,
            disabledForegroundColor: color,
            minimumSize: const Size(100, 40),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          icon: Icon(
            sync.connected ? Icons.devices_outlined : Icons.sync,
            size: 18,
          ),
          label: Text(label),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const SettingsCenter(initialCategory: '同步'),
          ),
        ),
        IconButton(
          key: const ValueKey('mobile-sync-details'),
          tooltip: zh ? '同步状态' : 'Sync status',
          onPressed: () => showSyncStatusDetails(context),
          icon: const Icon(Icons.info_outline, size: 18),
        ),
      ],
    );
  }
}
