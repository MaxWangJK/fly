import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../l10n/fly_localizations.dart';
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
  final email = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController(),
      endpoint = TextEditingController(),
      port = TextEditingController(text: '8765');
  bool register = false, initialized = false;
  String tr(String zh, String en) => context.l10n.isZh ? zh : en;
  @override
  void dispose() {
    for (final c in [email, password, confirm, endpoint, port]) {
      c.dispose();
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
      enableSuggestions: !secret,
      autocorrect: false,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperMaxLines: 4,
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

  Future<void> enableCloud(SyncController c, bool value) async {
    if (value) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('首次同步', 'Initial sync')),
          content: Text(
            tr(
              '本机数据将合并到此账号工作区，请先做好备份。',
              'Local data will merge into this account workspace. Back up first.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('开始同步', 'Start sync')),
            ),
          ],
        ),
      );
      if (accepted != true) return;
    }
    await c.setCloud(value);
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
    final engine = c.engine;
    if (widget.accountOnly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null)
            Text(
              c.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ...cloud(c),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(
            '数据先保存本机，联网后自动同步。选择一种连接方式。',
            'Data is saved locally and syncs when connected. Choose a connection mode.',
          ),
        ),
        const SizedBox(height: 12),
        for (final mode in SyncConnectionMode.values)
          Card(
            child: ListTile(
              key: ValueKey('sync-mode-${mode.name}'),
              leading: Icon(
                mode == SyncConnectionMode.cloud
                    ? Icons.cloud_outlined
                    : Icons.devices_outlined,
              ),
              title: Text(
                mode == SyncConnectionMode.cloud
                    ? tr('云同步', 'Cloud sync')
                    : tr('电脑与手机同步', 'Desktop and phone'),
              ),
              subtitle: Text(
                mode == SyncConnectionMode.cloud
                    ? tr('使用官方平台或自建服务器', 'Official platform or your own server')
                    : tr(
                        '同一网络，扫码连接，自动同步文件',
                        'Same network, scan to connect, files sync automatically',
                      ),
              ),
              trailing: Icon(
                c.connectionMode == mode
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              selected: c.connectionMode == mode,
              onTap: c.busy ? null : () => c.selectConnectionMode(mode),
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
        if (c.connectionMode == SyncConnectionMode.cloud)
          ...cloud(c)
        else
          ...lan(c),
        if (engine != null) ...[
          heading('同步状态', 'Sync status'),
          Text(engine.status),
          if (engine.error != null)
            Text(
              engine.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Text(
            '${tr('最后同步', 'Last sync')}: ${engine.lastSuccess?.toLocal().toString() ?? '—'}',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              onPressed: engine.running || c.busy
                  ? null
                  : () => c.run(() async {
                      await engine.synchronize();
                      await c.refreshDetails();
                    }),
              child: Text(tr('立即同步', 'Sync now')),
            ),
          ),
        ],
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(tr('设备', 'Devices')),
          children: [
            for (final d in c.devices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${d['deviceName']}'),
                subtitle: Text(
                  '${d['platform']} · ${d['revoked'] == true ? tr('已撤销', 'Revoked') : tr('受信任', 'Trusted')}',
                ),
                trailing: TextButton(
                  onPressed:
                      c.busy ||
                          d['revoked'] == true ||
                          d['id'] == c.auth.deviceId
                      ? null
                      : () => c.revokeDevice(d['id'] as String),
                  child: Text(tr('撤销', 'Revoke')),
                ),
              ),
            for (final d in c.trustedDevices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${d['name']}'),
                subtitle: const Text('LAN'),
                trailing: TextButton(
                  onPressed: c.busy || d['revoked'] == 1
                      ? null
                      : () => c.run(() async {
                          await c.host.revoke(d['id'] as String);
                          await c.refreshDetails();
                        }),
                  child: Text(tr('撤销', 'Revoke')),
                ),
              ),
          ],
        ),
        const SyncStatusDetails(),
        const SizedBox(height: 12),
        heading('同步冲突', 'Sync conflicts'),
        if (c.conflicts.isEmpty)
          Text(tr('没有待处理冲突。', 'No unresolved conflicts.')),
        for (final conflict in c.conflicts)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              '${conflict['entityType']} · ${(conflict['fields'] as List).join(', ')}',
            ),
            subtitle: Text('${conflict['kind']}'),
            children: [
              SelectableText(
                '${tr('候选版本 A', 'Candidate A')}\n${const JsonEncoder.withIndent('  ').convert(conflict['serverCandidate'])}',
              ),
              SelectableText(
                '${tr('候选版本 B', 'Candidate B')}\n${const JsonEncoder.withIndent('  ').convert(conflict['localCandidate'])}',
              ),
              Wrap(
                spacing: 12,
                children: [
                  TextButton(
                    onPressed: c.busy ? null : () => c.resolve(conflict, false),
                    child: Text(tr('保留当前', 'Keep current')),
                  ),
                  TextButton(
                    onPressed: c.busy ? null : () => c.resolve(conflict, true),
                    child: Text(tr('使用保存的另一份', 'Use the other saved version')),
                  ),
                ],
              ),
            ],
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(tr('诊断信息', 'Diagnostics')),
          children: [
            SelectableText(
              'User: ${c.auth.userId ?? "—"}\nDevice: ${c.auth.deviceId ?? "—"}\nServer: ${c.server}\nPending: ${engine?.pending ?? 0}\nFile queue: ${engine?.files.queued ?? 0}',
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> cloud(SyncController c) => [
    heading('服务器', 'Server'),
    input(
      endpoint,
      tr('服务器地址', 'Server address'),
      key: 'sync-server-address',
      helperText: tr(
        '默认 world-workshop.cn/api。自建服务器可填 192.168.0.21/api 或 192.168.0.21:8765/api，无需填写协议。',
        'Default: world-workshop.cn/api. You may enter an IP with a port and /api; no scheme is needed.',
      ),
    ),
    Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        OutlinedButton(
          onPressed: c.busy || c.cloudEnabled
              ? null
              : () async {
                  await c.configureServer(endpoint.text);
                  if (mounted && c.error == null) {
                    setState(
                      () => endpoint.text = SyncServerConfig.displayAddress(
                        c.server,
                      ),
                    );
                  }
                },
          child: Text(tr('保存服务器', 'Save server')),
        ),
        TextButton(
          onPressed: c.busy
              ? null
              : () async {
                  await c.testConnection(endpoint.text);
                  await resultDialog(tr('服务器连接正常。', 'Server reachable.'), c);
                },
          child: Text(tr('测试连接', 'Test connection')),
        ),
      ],
    ),
    heading('账号', 'Account'),
    if (c.auth.userId == null) ...[
      input(
        email,
        tr('邮箱', 'Email'),
        key: 'sync-email',
        keyboardType: TextInputType.emailAddress,
      ),
      input(
        password,
        tr('密码（至少 10 位）', 'Password (10+ characters)'),
        secret: true,
        key: 'sync-password',
      ),
      if (register)
        input(
          confirm,
          tr('确认密码', 'Confirm password'),
          secret: true,
          key: 'sync-confirm',
        ),
      Wrap(
        spacing: 12,
        children: [
          FilledButton(
            onPressed: c.busy
                ? null
                : () async {
                    if (register && password.text != confirm.text) {
                      await c.login(
                        register,
                        email.text,
                        password.text,
                        confirm.text,
                      );
                      return;
                    }
                    await c.configureServer(endpoint.text);
                    if (c.error != null) return;
                    await c.login(
                      register,
                      email.text,
                      password.text,
                      confirm.text,
                    );
                    if (c.auth.userId != null) {
                      password.clear();
                      confirm.clear();
                    }
                  },
            child: Text(register ? tr('注册', 'Register') : tr('登录', 'Log in')),
          ),
          TextButton(
            onPressed: c.busy
                ? null
                : () => setState(() => register = !register),
            child: Text(
              register
                  ? tr('已有账号，登录', 'Have an account? Log in')
                  : tr('创建账号', 'Create account'),
            ),
          ),
        ],
      ),
      Text(
        tr(
          '暂不支持邮箱验证或忘记密码重置。',
          'Email verification and password reset are not yet supported.',
        ),
      ),
    ] else ...[
      SelectableText(c.auth.email ?? ''),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: c.busy ? null : c.logout,
          child: Text(tr('退出当前设备', 'Log out this device')),
        ),
      ),
    ],
    if (!widget.accountOnly)
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('开启云同步', 'Enable cloud sync')),
        value: c.cloudEnabled,
        onChanged: c.busy || c.auth.userId == null
            ? null
            : (v) => enableCloud(c, v),
      ),
    if (!widget.accountOnly)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          c.cloudFiles ? Icons.folder_shared_outlined : Icons.info_outline,
        ),
        title: Text(
          c.cloudFiles
              ? tr('文件内容自动同步', 'File contents sync automatically')
              : tr('此账号仅同步文件信息', 'This account syncs file information only'),
        ),
        subtitle: Text(
          c.cloudFiles
              ? tr('同步名称、目录和实体文件。', 'Names, folders and file contents sync.')
              : tr(
                  '官方平台仅为 max@ceiling-arts.com 同步实体文件；其他账号可使用自建服务器或电脑扫码同步文件。',
                  'Official file contents are enabled only for max@ceiling-arts.com. Other accounts may use self-hosting or desktop pairing.',
                ),
        ),
      ),
  ];

  List<Widget> lan(SyncController c) => [
    heading('电脑与手机同步', 'Desktop and phone'),
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
