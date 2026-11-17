import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../l10n/fly_localizations.dart';
import '../../account/presentation/my_settings_panel.dart';
import '../domain/sync_protocol.dart';
import 'lan_pairing_scanner.dart';
import 'lan_pairing_guide.dart';
import 'sync_controller.dart';
import 'sync_status_details.dart';

class SyncSettingsPanel extends ConsumerStatefulWidget {
  const SyncSettingsPanel({this.accountOnly = false, this.onOpenMy, super.key});
  // Retain the former embedding API; account-only embeds now show local profile.
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
    port.dispose();
    super.dispose();
  }

  Widget heading(String zh, String en) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 12),
    child: Text(tr(zh, en), style: Theme.of(context).textTheme.titleMedium),
  );

  Widget input(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
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
    final engine = c.engine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('本地同步', 'Local sync'),
        Text(
          tr(
            '请让手机和电脑连接同一网络，再使用手机 Fly 内置扫一扫连接电脑。数据和文件将在设备间本地传输。',
            'Connect your phone and computer to the same network, then scan the desktop QR code inside Fly on your phone. Records and files transfer locally.',
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
        ..._lan(c),
        if (engine != null) ...[
          heading('同步状态', 'Sync status'),
          Text(c.status),
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
        if (c.trustedDevices.isNotEmpty)
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
      ],
    );
  }

  List<Widget> _lan(SyncController c) => [
    heading('设备连接', 'Device connection'),
    const LanPairingGuide(),
    if (!c.isMobile) ...[
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('开启电脑同步服务', 'Enable desktop sync service')),
        value: c.host.running,
        onChanged: c.busy
            ? null
            : (value) => c.setHost(value, int.tryParse(port.text) ?? 0),
      ),
      if (!c.host.running) input(port, tr('服务端口', 'Service port')),
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
            '请用手机 Fly 中的“扫描电脑二维码”扫描（5 分钟有效）。',
            'Scan with “Scan desktop QR code” inside Fly on your phone (valid for 5 minutes).',
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
