import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/fly_localizations.dart';
import '../domain/sync_protocol.dart';
import 'sync_controller.dart';

class SyncSettingsPanel extends ConsumerStatefulWidget {
  const SyncSettingsPanel({super.key});
  @override
  ConsumerState<SyncSettingsPanel> createState() => _SyncSettingsPanelState();
}

class _SyncSettingsPanelState extends ConsumerState<SyncSettingsPanel> {
  final email = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController();
  final endpoint = TextEditingController(),
      lanEndpoint = TextEditingController(),
      code = TextEditingController(),
      port = TextEditingController(text: '8765');
  bool register = false;
  String tr(String zh, String en) => context.l10n.isZh ? zh : en;
  @override
  void dispose() {
    for (final c in [
      email,
      password,
      confirm,
      endpoint,
      lanEndpoint,
      code,
      port,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget heading(String zh, String en) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(tr(zh, en), style: Theme.of(context).textTheme.titleMedium),
  );
  Widget input(
    TextEditingController controller,
    String label, {
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      obscureText: secret,
      enableSuggestions: !secret,
      autocorrect: !secret,
      decoration: InputDecoration(labelText: label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(syncControllerProvider);
    if (!c.ready) return const LinearProgressIndicator();
    if (endpoint.text.isEmpty) endpoint.text = c.server;
    final engine = c.engine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(
            '所有数据先保存本机。登录和同步不影响离线使用。',
            'Data is saved locally first. Your workspace stays available offline.',
          ),
        ),
        if (c.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              c.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (c.busy) const LinearProgressIndicator(),
        heading('账号', 'Account'),
        if (c.auth.userId == null) ...[
          input(email, tr('邮箱', 'Email')),
          input(
            password,
            tr('密码（至少 10 位）', 'Password (10+ characters)'),
            secret: true,
          ),
          if (register)
            input(confirm, tr('确认密码', 'Confirm password'), secret: true),
          Wrap(
            spacing: 12,
            children: [
              FilledButton(
                onPressed: c.busy
                    ? null
                    : () async {
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
                child: Text(
                  register ? tr('注册', 'Register') : tr('登录', 'Log in'),
                ),
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
              'Email verification and password reset are planned for a later version.',
            ),
          ),
        ] else ...[
          SelectableText('${c.auth.email}\nUser ID: ${c.auth.userId}'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: c.busy ? null : c.logout,
              child: Text(tr('退出当前设备', 'Log out this device')),
            ),
          ),
        ],
        heading('云同步', 'Cloud sync'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('开启云同步', 'Enable cloud sync')),
          value: c.cloudEnabled,
          onChanged: c.busy || c.auth.userId == null
              ? null
              : (value) async {
                  if (value) {
                    final accepted = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(tr('首次同步', 'Initial sync')),
                        content: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr(
                                  '本机数据将合并到此账号工作区，旧数据会保留。',
                                  'Local data will be merged into this account workspace.',
                                ),
                              ),
                              for (final entry in {
                                'customers': tr('客户', 'Customers'),
                                'orders': tr('订单', 'Orders'),
                                'tasks': tr('任务', 'Tasks'),
                                'workspace_notes': tr('笔记', 'Notes'),
                                'attachments': tr('文件', 'Files'),
                              }.entries)
                                Text(
                                  '${entry.value}: ${c.counts[entry.key] ?? 0}',
                                ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(tr('取消', 'Cancel')),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(tr('开始同步', 'Start sync')),
                          ),
                        ],
                      ),
                    );
                    if (accepted != true) return;
                  }
                  await c.setCloud(value);
                },
        ),
        input(endpoint, tr('服务器地址', 'Server URL')),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: c.busy || c.cloudEnabled
                  ? null
                  : () => c.configureServer(endpoint.text),
              child: Text(tr('保存服务器', 'Save server')),
            ),
            TextButton(
              onPressed: c.busy
                  ? null
                  : () async {
                      await c.testConnection(endpoint.text);
                      if (context.mounted && c.error == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(tr('服务器连接正常', 'Server reachable')),
                          ),
                        );
                      }
                    },
              child: Text(tr('测试连接', 'Test connection')),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('云端同步文件内容', 'Sync cloud file contents')),
          subtitle: Text(
            tr(
              '关闭后仍同步文件名称、目录、标签和业务关联。',
              'File names, folders, tags and links always sync.',
            ),
          ),
          value: c.cloudFiles,
          onChanged: c.busy ? null : (v) => c.setFiles(cloud: v),
        ),
        if (engine != null) ...[
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
              onPressed: engine.running
                  ? null
                  : () => c.run(() async {
                      await engine.synchronize();
                      await c.refreshDetails();
                    }),
              child: Text(tr('立即同步', 'Sync now')),
            ),
          ),
        ],
        heading('局域网同步', 'LAN sync'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('开启电脑局域网服务', 'Enable desktop LAN host')),
          value: c.host.running,
          onChanged: c.busy
              ? null
              : (v) => c.setHost(v, int.tryParse(port.text) ?? 0),
        ),
        input(port, tr('端口', 'Port')),
        if (c.host.running) ...[
          for (final address in c.addresses)
            SelectableText('http://$address:${c.lanPort}/api'),
          SelectableText(
            '${tr('配对码（5 分钟有效）', 'Pairing code (5 minutes)')}: ${c.host.pairingCode}',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(c.host.rotatePairing),
              child: Text(tr('更新配对码', 'New pairing code')),
            ),
          ),
        ],
        DropdownButtonFormField<LanSyncMode>(
          initialValue: c.mode,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('同步方向', 'Sync direction')),
          items: [
            DropdownMenuItem(
              value: LanSyncMode.bidirectional,
              child: Text(tr('双向同步（推荐）', 'Both directions (recommended)')),
            ),
            DropdownMenuItem(
              value: LanSyncMode.desktopToMobile,
              child: Text(tr('电脑 → 手机', 'Desktop → mobile')),
            ),
            DropdownMenuItem(
              value: LanSyncMode.mobileToDesktop,
              child: Text(tr('手机 → 电脑', 'Mobile → desktop')),
            ),
          ],
          onChanged: c.busy
              ? null
              : (v) {
                  if (v != null) c.setMode(v);
                },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(switch (c.mode) {
            LanSyncMode.bidirectional => tr(
              '两台设备的新增和修改都会同步。',
              'New records and changes sync both ways.',
            ),
            LanSyncMode.desktopToMobile => tr(
              '仅将电脑数据同步到手机。手机修改不会返回电脑。',
              'Desktop changes sync to mobile. Mobile changes stay on mobile.',
            ),
            LanSyncMode.mobileToDesktop => tr(
              '仅将手机数据同步到电脑。电脑修改不会返回手机。',
              'Mobile changes sync to desktop. Desktop changes stay on desktop.',
            ),
          }),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('局域网同步文件内容', 'Sync LAN file contents')),
          value: c.lanFiles,
          onChanged: c.busy ? null : (v) => c.setFiles(lan: v),
        ),
        input(
          lanEndpoint,
          tr(
            '电脑地址，例如 http://192.168.1.20:8765/api',
            'Desktop URL, e.g. http://192.168.1.20:8765/api',
          ),
        ),
        input(code, tr('配对码', 'Pairing code')),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: c.busy
                ? null
                : () => c.pair(lanEndpoint.text, code.text),
            child: Text(tr('配对并连接', 'Pair and connect')),
          ),
        ),
        if (c.cloudEnabled)
          Text(
            tr(
              '云端负责记录版本协调；局域网服务可传输文件。',
              'Cloud coordinates record versions; the LAN host can serve files.',
            ),
          ),
        heading('设备', 'Devices'),
        for (final d in c.devices)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${d['deviceName']}'),
            trailing: TextButton(
              onPressed:
                  c.busy || d['revoked'] == true || d['id'] == c.auth.deviceId
                  ? null
                  : () => c.revokeDevice(d['id'] as String),
              child: Text(tr('撤销', 'Revoke')),
            ),
            subtitle: Text(
              '${d['platform']} · ${d['revoked'] == true ? tr('已撤销', 'Revoked') : tr('受信任', 'Trusted')}',
            ),
          ),
        for (final d in c.trustedDevices)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${d['name']}'),
            subtitle: Text('LAN'),
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
              const SizedBox(height: 8),
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
        const SizedBox(height: 16),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(tr('诊断信息', 'Diagnostics')),
          children: [
            SelectableText(
              'User: ${c.auth.userId ?? "—"}\nDevice: ${c.auth.deviceId ?? "—"}\nServer: ${c.server}\nPending: ${engine?.pending ?? 0}\nFile queue: ${engine?.files.queued ?? 0}',
            ),
            FutureBuilder<String?>(
              future: c.outbox.state(
                c.cloudEnabled ? 'cloudCursor' : 'lanCursor',
              ),
              builder: (_, snapshot) =>
                  SelectableText('Cursor: ${snapshot.data ?? "0"}'),
            ),
          ],
        ),
      ],
    );
  }
}
