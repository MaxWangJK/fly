import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../l10n/fly_localizations.dart';
import '../../account/presentation/my_settings_panel.dart';
import '../domain/sync_protocol.dart';
import 'lan_pairing_scanner.dart';
import 'sync_controller.dart';
import 'sync_status_details.dart';

class SyncSettingsPanel extends ConsumerStatefulWidget {
  const SyncSettingsPanel({this.accountOnly = false, this.onOpenMy, super.key});
  final bool accountOnly;
  final VoidCallback? onOpenMy;
  @override
  ConsumerState<SyncSettingsPanel> createState() => _SyncSettingsPanelState();
}

class _SyncSettingsPanelState extends ConsumerState<SyncSettingsPanel> {
  final port = TextEditingController(text: '8765');
  bool initialized = false;
  String tr(String zh, String en) => context.l10n.isZh ? zh : en;
  @override
  void dispose() {
    for (final controller in [port]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget heading(String zh, String en) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 12),
    child: Text(tr(zh, en), style: Theme.of(context).textTheme.titleMedium),
  );
  Widget input(
    TextEditingController controller,
    String label, {
    bool secret = false,
    String? helperText,
    String? key,
    TextInputType? keyboardType,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: key == null ? null : ValueKey(key),
      controller: controller,
      obscureText: secret,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperMaxLines: 5,
      ),
    ),
  );
  Future<void> resultDialog(String success, SyncController c) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          c.error == null
              ? tr('连接成功', 'Connected')
              : tr('连接失败', 'Connection failed'),
        ),
        content: Text(c.error ?? success),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('确定', 'OK')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.accountOnly) return const MySettingsPanel();
    final c = ref.watch(syncControllerProvider);
    if (!c.ready) return const LinearProgressIndicator();
    if (!initialized) {
      initialized = true;
      port.text = '${c.lanPort}';
    }
    final cloudSelected =
        widget.accountOnly || c.connectionMode == SyncConnectionMode.cloud;
    final engine = c.engine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.accountOnly) ...[
          heading('同步方式', 'Sync method'),
          SegmentedButton<SyncConnectionMode>(
            key: const ValueKey('sync-mode-selector'),
            segments: [
              ButtonSegment(
                value: SyncConnectionMode.lan,
                icon: const Icon(Icons.devices),
                label: Text(tr('本地同步', 'Local')),
              ),
              ButtonSegment(
                value: SyncConnectionMode.cloud,
                icon: const Icon(Icons.cloud_outlined),
                label: Text(tr('云同步', 'Cloud')),
              ),
            ],
            selected: {c.connectionMode},
            onSelectionChanged: c.busy
                ? null
                : (value) => switchMode(c, value.single),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          cloudSelected
              ? tr(
                  '工作电脑、手机和家庭电脑使用同一用户空间，离线修改会在连接后自动合并。',
                  'Use one personal space on your work computer, phone and home computer. Offline changes merge when connected.',
                )
              : tr(
                  '本地同步默认开启，用手机扫描电脑二维码即可。数据和文件直接传输。',
                  'Local sync is enabled by default. Scan the desktop QR code to transfer records and files.',
                ),
        ),
        if (c.busy) const LinearProgressIndicator(),
        if (c.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              c.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ...(cloudSelected ? cloud(c) : lan(c)),
        if (engine != null) ...[
          heading('同步状态', 'Sync status'),
          Text(engine.status),
          if (engine.error != null)
            Text(
              engine.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton.tonal(
            onPressed: engine.running || c.busy
                ? null
                : () => c.run(() async {
                    await engine.synchronize();
                    await c.refreshDetails();
                  }),
            child: Text(tr('立即同步', 'Sync now')),
          ),
        ],
        if (cloudSelected && c.devices.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(tr('已连接设备', 'Connected devices')),
            children: [
              for (final device in c.devices)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${device['deviceName']}'),
                  subtitle: Text('${device['platform']}'),
                  trailing: TextButton(
                    onPressed:
                        c.busy ||
                            device['revoked'] == true ||
                            device['id'] == c.auth.deviceId
                        ? null
                        : () => c.revokeDevice(device['id'] as String),
                    child: Text(tr('撤销', 'Revoke')),
                  ),
                ),
            ],
          ),
        if (!cloudSelected && c.trustedDevices.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(tr('已配对设备', 'Paired devices')),
            children: [
              for (final device in c.trustedDevices)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${device['name']}'),
                  trailing: TextButton(
                    onPressed: c.busy || device['revoked'] == 1
                        ? null
                        : () => c.run(() async {
                            await c.host.revoke(device['id'] as String);
                            await c.refreshDetails();
                          }),
                    child: Text(tr('撤销', 'Revoke')),
                  ),
                ),
            ],
          ),
        const SyncStatusDetails(),
        const SizedBox(height: 12),
        Text(
          tr(
            '不同记录自动保留，同一记录按字段与修改顺序自动合并。',
            'Distinct records are kept. Changes to a shared record merge automatically by field and edit order.',
          ),
        ),
      ],
    );
  }

  void openMy() {
    if (widget.onOpenMy != null) {
      widget.onOpenMy!();
    } else {
      showMySettings(context);
    }
  }

  Future<void> switchMode(SyncController c, SyncConnectionMode next) async {
    if (next == c.connectionMode) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('切换同步方式', 'Switch sync method')),
        content: Text(
          next == SyncConnectionMode.cloud
              ? tr(
                  '云同步将断开本地同步服务。是否继续？',
                  'Cloud sync will disconnect local sync. Continue?',
                )
              : tr(
                  '本地同步将断开云同步。是否继续？',
                  'Local sync will disconnect cloud sync. Continue?',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('取消', 'Cancel')),
          ),
          FilledButton(
            key: const ValueKey('confirm-sync-mode-switch'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('继续', 'Continue')),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) await c.selectConnectionMode(next);
  }

  List<Widget> cloud(SyncController c) => [
    const SizedBox(height: 16),
    Text(
      tr(
        '同步客户、订单、任务和复盘。图片和文件内容使用本地同步。',
        'Sync customers, orders, tasks and reviews. File contents use local sync.',
      ),
    ),
    const SizedBox(height: 16),
    if (!c.cloudEnabled)
      FilledButton.icon(
        key: const ValueKey('enable-cloud-sync'),
        icon: const Icon(Icons.cloud_sync_outlined),
        onPressed: c.busy
            ? null
            : () async {
                if (c.auth.userId == null) {
                  openMy();
                  return;
                }
                await c.setCloud(true);
                if (c.error == null) await c.refreshDetails();
              },
        label: Text(tr('开启云同步', 'Enable cloud sync')),
      )
    else
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.cloud_done_outlined),
        title: Text(tr('云同步已开启', 'Cloud sync enabled')),
      ),
    TextButton(
      key: const ValueKey('sync-open-my'),
      onPressed: openMy,
      child: Text(tr('在“我的”中管理账号', 'Manage your account in Me')),
    ),
  ];

  List<Widget> lan(SyncController c) => [
    heading('设备连接', 'Device connection'),
    Text(
      tr(
        '两端连接同一网络，双向同步数据和实体文件，无需云端账号。',
        'Connect both devices to the same network. Data and files sync both ways without a cloud account.',
      ),
    ),
    if (!c.isMobile) ...[
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('开启电脑同步服务', 'Enable desktop sync service')),
        value: c.host.running,
        onChanged: c.busy
            ? null
            : (v) => c.setHost(v, int.tryParse(port.text) ?? 0),
      ),
      if (!c.host.running)
        input(
          port,
          tr('服务端口', 'Service port'),
          keyboardType: TextInputType.number,
        ),
      if (c.host.running && c.pairingPayload != null) ...[
        Center(
          child: QrImageView(
            key: const ValueKey('lan-pairing-qr'),
            data: c.pairingPayload!.encode(),
            size: 240,
            backgroundColor: Colors.white,
          ),
        ),
        Text(
          tr(
            '手机扫描此二维码即可连接（5 分钟有效）。',
            'Scan this QR code on your phone to connect (valid for 5 minutes).',
          ),
          textAlign: TextAlign.center,
        ),
        Center(
          child: TextButton(
            onPressed: c.busy ? null : c.host.rotatePairing,
            child: Text(tr('刷新二维码', 'Refresh QR code')),
          ),
        ),
      ] else if (c.host.running)
        Text(
          tr(
            '未找到可用局域网地址，请检查电脑网络。',
            'No LAN address found. Check the desktop network.',
          ),
        ),
      if (c.host.running)
        Text(
          tr(
            '请允许防火墙访问此服务端口，并保持电脑端 Fly 运行。',
            'Allow the service port through your firewall and keep desktop Fly running.',
          ),
        ),
    ] else ...[
      const SizedBox(height: 16),
      FilledButton.icon(
        key: const ValueKey('scan-desktop-qr'),
        onPressed: c.busy
            ? null
            : () async {
                final raw = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => const LanPairingScanner(),
                    fullscreenDialog: true,
                  ),
                );
                if (raw == null || !mounted) return;
                await c.pairQr(raw);
                await resultDialog(
                  tr(
                    '已连接电脑，数据和文件将自动同步。',
                    'Desktop connected. Data and files will sync automatically.',
                  ),
                  c,
                );
              },
        icon: const Icon(Icons.qr_code_scanner),
        label: Text(tr('扫描电脑二维码', 'Scan desktop QR code')),
      ),
      if (c.lanEndpoint != null) ...[
        const SizedBox(height: 12),
        Text(
          '${tr('已配对电脑', 'Paired desktop')}: ${SyncServerConfig.displayAddress(c.lanEndpoint!)}',
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('开启电脑与手机同步', 'Enable desktop and phone sync')),
          value: c.engine?.enabled == true,
          onChanged: c.busy ? null : c.setLanClient,
        ),
      ],
    ],
  ];
}
