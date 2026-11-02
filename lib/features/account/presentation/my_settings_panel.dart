import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../l10n/fly_localizations.dart';
import '../../tasks/presentation/task_providers.dart';
import '../../sync/domain/sync_protocol.dart';
import '../../sync/presentation/sync_controller.dart';
import '../data/local_profile.dart';
import 'cloud_account_form.dart';

Future<void> showMySettings(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640, maxHeight: 760),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Builder(
                builder: (context) => IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            const MySettingsPanel(),
          ],
        ),
      ),
    ),
  ),
);

class MySettingsPanel extends ConsumerStatefulWidget {
  const MySettingsPanel({super.key});
  @override
  ConsumerState<MySettingsPanel> createState() => _MySettingsPanelState();
}

class _MySettingsPanelState extends ConsumerState<MySettingsPanel> {
  final name = TextEditingController(), server = TextEditingController();
  Uint8List? avatar;
  bool loaded = false, serverLoaded = false, busy = false;
  String? error;
  String t(String zh, String en) => context.l10n.isZh ? zh : en;
  @override
  void dispose() {
    name.dispose();
    server.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm(String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('切换同步服务', 'Switch sync service')),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('继续', 'Continue')),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> pickAvatar() => run(() async {
    final XFile? file = Platform.isAndroid || Platform.isIOS
        ? await ImagePicker().pickImage(
            source: ImageSource.gallery,
            maxWidth: 512,
            maxHeight: 512,
            imageQuality: 85,
          )
        : await openFile(
            acceptedTypeGroups: [
              const XTypeGroup(
                label: 'Images',
                extensions: ['png', 'jpg', 'jpeg', 'webp'],
              ),
            ],
          );
    if (file == null) return;
    if (await file.length() > 8 * 1024 * 1024) {
      throw StateError(t('请选择小于 8 MB 的图片', 'Choose an image under 8 MB'));
    }
    final codec = await ui.instantiateImageCodecWithSize(
      await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes()),
      getTargetSize: (width, height) => width >= height
          ? ui.TargetImageSize(width: width.clamp(1, 256))
          : ui.TargetImageSize(height: height.clamp(1, 256)),
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final bytes = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (mounted && bytes != null) {
          setState(() => avatar = bytes.buffer.asUint8List());
        }
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  });
  Future<bool> prepare() async {
    final c = ref.read(syncControllerProvider);
    final intended = server.text.trim().isEmpty
        ? SyncServerConfig.defaultBaseUrl
        : SyncServerConfig.validate(server.text).toString();
    if (intended != c.server) {
      await saveServer();
      if (error != null || intended != c.server) return false;
    }
    if (c.connectionMode != SyncConnectionMode.cloud) {
      if (!await confirm(
        t(
          '登录并开启云同步将断开本地同步服务。是否继续？',
          'Signing in to cloud sync disconnects local sync. Continue?',
        ),
      )) {
        return false;
      }
      await c.selectConnectionMode(SyncConnectionMode.cloud);
    }
    return c.error == null;
  }

  Future<void> saveServer({bool restore = false}) => run(() async {
    final c = ref.read(syncControllerProvider);
    final value = restore || server.text.trim().isEmpty
        ? SyncServerConfig.defaultBaseUrl
        : SyncServerConfig.validate(server.text).toString();
    if (value != c.server) {
      if (c.cloudEnabled &&
          !await confirm(
            t(
              '更换服务器将停止当前云同步。已有数据保留，账号仍按服务器隔离。',
              'Changing servers stops cloud sync. Existing data is kept and accounts remain isolated by server.',
            ),
          )) {
        return;
      }
      if (c.cloudEnabled) await c.setCloud(false);
      await c.configureServer(value);
      if (c.error != null) throw StateError(c.error!);
    }
    server.text = value == SyncServerConfig.defaultBaseUrl
        ? ''
        : SyncServerConfig.displayAddress(value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('同步服务器设置已保存', 'Sync server saved'))),
      );
    }
  });
  @override
  Widget build(BuildContext context) {
    final c = ref.watch(syncControllerProvider);
    final profile = ref.watch(localProfileProvider);
    if (!loaded && profile.hasValue) {
      loaded = true;
      name.text = profile.value!.name;
      avatar = profile.value!.avatar;
    }
    if (!serverLoaded && c.ready) {
      serverLoaded = true;
      server.text = c.server == SyncServerConfig.defaultBaseUrl
          ? ''
          : SyncServerConfig.displayAddress(c.server);
    }
    return Column(
      key: const ValueKey('my-settings-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t('个人资料', 'Profile'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundImage: avatar == null ? null : MemoryImage(avatar!),
                child: avatar == null
                    ? const Icon(Icons.person_outline, size: 36)
                    : null,
              ),
              TextButton(
                key: const ValueKey('my-pick-avatar'),
                onPressed: busy ? null : pickAvatar,
                child: Text(t('设置头像', 'Choose avatar')),
              ),
            ],
          ),
        ),
        TextField(
          key: const ValueKey('my-display-name'),
          controller: name,
          maxLength: 80,
          decoration: InputDecoration(labelText: t('我的名字', 'My name')),
        ),
        FilledButton.tonal(
          key: const ValueKey('my-save-profile'),
          onPressed: busy || !loaded
              ? null
              : () => run(() async {
                  await LocalProfileRepository(ref.read(databaseProvider))
                      .save(name.text, avatar);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(t('个人资料已保存', 'Profile saved'))),
                    );
                  }
                }),
          child: Text(t('保存个人资料', 'Save profile')),
        ),
        const SizedBox(height: 24),
        Text(
          t('同步服务器', 'Sync server'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('my-sync-server'),
          controller: server,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: t('自建服务器地址（选填）', 'Custom server address (optional)'),
            hintText: t('留空使用默认服务', 'Leave empty to use the default service'),
            helperText: t(
              '填写后使用你指定的服务器；留空或恢复默认使用系统服务。',
              'A custom address replaces the default service. Leave empty or reset to restore it.',
            ),
            helperMaxLines: 3,
          ),
        ),
        Wrap(
          spacing: 12,
          children: [
            TextButton(
              key: const ValueKey('my-save-server'),
              onPressed: busy || c.busy ? null : saveServer,
              child: Text(t('保存地址', 'Save address')),
            ),
            TextButton(
              key: const ValueKey('my-reset-server'),
              onPressed: busy || c.busy
                  ? null
                  : () => saveServer(restore: true),
              child: Text(t('恢复默认', 'Restore default')),
            ),
          ],
        ),
        if (busy) const LinearProgressIndicator(),
        if (c.error != null)
          Text(
            c.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 20),
        if (!c.ready)
          const LinearProgressIndicator()
        else if (c.auth.userId == null || !c.auth.emailVerified) ...[
          if (c.auth.userId != null)
            Text(t('为现有同步空间绑定邮箱', 'Add email to your existing sync space')),
          CloudAccountForm(
            controller: c,
            prepare: prepare,
            onSuccess: () async {
              if (mounted) {
                await showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(t('连接成功', 'Connected')),
                    content: Text(
                      t('已登录并开启云同步。', 'Signed in. Cloud sync is enabled.'),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(t('确定', 'OK')),
                      ),
                    ],
                  ),
                );
              }
            },
          ),
        ] else ...[
          Text(
            t('登录邮箱', 'Signed-in email'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SelectableText(c.auth.email ?? ''),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                key: const ValueKey('cloud-manage-password'),
                onPressed: c.busy
                    ? null
                    : () => showCloudAccountOperation(
                        context,
                        controller: c,
                        prepare: () async => true,
                        operation: CloudAccountOperation.resetPassword,
                      ),
                child: Text(t('修改密码', 'Reset password')),
              ),
              TextButton(
                onPressed: c.busy ? null : c.logout,
                child: Text(t('退出登录', 'Sign out')),
              ),
              TextButton(
                key: const ValueKey('cloud-manage-delete'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: c.busy
                    ? null
                    : () => showCloudAccountOperation(
                        context,
                        controller: c,
                        prepare: () async => true,
                        operation: CloudAccountOperation.deleteAccount,
                      ),
                child: Text(t('注销云端账号', 'Delete cloud account')),
              ),
            ],
          ),
        ],
        const SizedBox(height: 88),
      ],
    );
  }
}
