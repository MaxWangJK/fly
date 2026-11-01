import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../l10n/fly_localizations.dart';
import '../../account/presentation/cloud_account_form.dart';
import '../domain/sync_protocol.dart';
import 'lan_pairing_scanner.dart';
import 'sync_controller.dart';
import 'sync_status_details.dart';

class SyncSettingsPanel extends ConsumerStatefulWidget {
  const SyncSettingsPanel({this.accountOnly = false, super.key});
  final bool accountOnly;
  @override
  ConsumerState<SyncSettingsPanel> createState() => _SyncSettingsPanelState();
}

class _SyncSettingsPanelState extends ConsumerState<SyncSettingsPanel> {
  final endpoint = TextEditingController(),
      port = TextEditingController(text: '8765'),
      code = TextEditingController();
  bool initialized = false;
  String tr(String zh, String en) => context.l10n.isZh ? zh : en;
  @override
  void dispose() {
    for (final controller in [endpoint, port, code]) {
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
    final c = ref.watch(syncControllerProvider);
    if (!c.ready) return const LinearProgressIndicator();
    if (!initialized) {
      initialized = true;
      endpoint.text = SyncServerConfig.displayAddress(c.server);
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
                : (value) => c.selectConnectionMode(value.single),
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
                  '在电脑开启同步服务，再用手机扫码。本地同步会传输数据和实体文件。',
                  'Enable desktop sync, then scan its QR code on your phone. Local sync transfers records and file contents.',
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

  List<Widget> cloud(SyncController c) => [
    heading('云同步', 'Cloud sync'),
    ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.info_outline),
      title: Text(tr('仅同步数据', 'Records only')),
      subtitle: Text(
        tr(
          '同步客户、订单、任务、复盘等数据。不上传或下载图片和文件内容；文件内容请使用本地同步。',
          'Sync customers, orders, tasks and reviews. Images and file contents use local sync only.',
        ),
      ),
    ),
    input(
      endpoint,
      tr('同步服务器', 'Sync server'),
      key: 'sync-server',
      helperText: tr(
        '默认 world-workshop.cn/api，无需填写 http 或 https。',
        'Default: world-workshop.cn/api. The scheme is optional.',
      ),
    ),
    Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: c.busy
            ? null
            : () async {
                await c.testConnection(endpoint.text);
                await resultDialog(
                  tr('同步服务器连接正常。', 'Sync server is available.'),
                  c,
                );
              },
        icon: const Icon(Icons.network_check),
        label: Text(tr('测试连接', 'Test connection')),
      ),
    ),
    if (c.auth.userId == null) ...[
      CloudAccountForm(
        controller: c,
        prepare: () => prepareAccount(c),
        onSuccess: () => resultDialog(
          tr(
            '已登录，云同步已开启。文件和图片内容仍通过本地同步。',
            'Signed in. Cloud sync is enabled. File contents still use local sync.',
          ),
          c,
        ),
      ),
      ExpansionTile(
        key: const ValueKey('cloud-device-code-option'),
        tilePadding: EdgeInsets.zero,
        title: Text(tr('设备接入码（测试入口）', 'Device code (testing)')),
        children: [
          const SizedBox(height: 16),
          input(
            code,
            tr('一次性设备接入码', 'One-use device code'),
            key: 'sync-device-code',
            secret: true,
            helperText: tr(
              '管理员签发的临时测试入口。已有账号请使用上方邮箱登录。',
              'Temporary access issued by an administrator. Use email sign-in above for an existing account.',
            ),
          ),
          FilledButton.icon(
            key: const ValueKey('enroll-cloud-device'),
            onPressed: c.busy
                ? null
                : () async {
                    await c.configureServer(endpoint.text);
                    if (c.error != null) return;
                    if (widget.accountOnly) {
                      await c.selectConnectionMode(SyncConnectionMode.cloud);
                    }
                    await c.enrollCloudDevice(code.text);
                    if (c.error == null) code.clear();
                    await resultDialog(
                      tr(
                        '设备已接入，数据将自动同步。',
                        'Device connected. Records will sync automatically.',
                      ),
                      c,
                    );
                  },
            icon: const Icon(Icons.link),
            label: Text(tr('连接云同步', 'Connect cloud sync')),
          ),
        ],
      ),
    ] else ...[
      Text(
        c.auth.emailVerified
            ? '${tr('登录邮箱', 'Email')}: ${c.auth.email}'
            : tr(
                '当前空间尚未绑定验证邮箱',
                'This space does not have a verified email yet',
              ),
      ),
      if (!c.auth.emailVerified)
        CloudAccountForm(
          controller: c,
          prepare: () => prepareAccount(c),
          onSuccess: () => resultDialog(
            tr(
              '邮箱已绑定，原同步空间和数据已保留。',
              'Email linked. Your sync space and existing data are preserved.',
            ),
            c,
          ),
        ),
      Text('${tr('同步空间', 'Sync space')}: ${c.auth.userId}'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('开启云同步', 'Enable cloud sync')),
        value: c.cloudEnabled,
        onChanged: c.busy ? null : c.setCloud,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: c.busy ? null : c.logout,
          child: Text(tr('断开此设备', 'Disconnect this device')),
        ),
      ),
    ],
  ];

  Future<bool> prepareAccount(SyncController c) async {
    await c.configureServer(endpoint.text);
    if (c.error != null) return false;
    if (widget.accountOnly) {
      await c.selectConnectionMode(SyncConnectionMode.cloud);
    }
    return c.error == null;
  }

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
