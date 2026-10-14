import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/settings_center.dart';
import 'sync_controller.dart';
import 'sync_status_details.dart';

class MobileSyncButton extends ConsumerWidget {
  const MobileSyncButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final waiting = !sync.ready || sync.busy || sync.connecting;
    final color = sync.connected
        ? Colors.green.shade700
        : waiting
        ? Colors.orange.shade800
        : Theme.of(context).colorScheme.error;
    final label = sync.connected
        ? (sync.busy || sync.engine?.running == true ? '同步中' : '已连接')
        : waiting
        ? '正在连接'
        : '立即连接';
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
            sync.connected ? Icons.cloud_done_outlined : Icons.sync,
            size: 18,
          ),
          label: Text(label),
          onPressed: waiting
              ? null
              : () async {
                  await sync.connectNow();
                  if (!context.mounted) return;
                  if (sync.error != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(sync.error!),
                        action: SnackBarAction(
                          label: '同步设置',
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) =>
                                const SettingsCenter(initialCategory: '同步'),
                          ),
                        ),
                      ),
                    );
                  }
                },
        ),
        IconButton(
          key: const ValueKey('mobile-sync-details'),
          tooltip: '同步状态',
          onPressed: () => showSyncStatusDetails(context),
          icon: const Icon(Icons.info_outline, size: 18),
        ),
      ],
    );
  }
}
