import '../../l10n/service_error_copy.dart';

import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/data_root_providers.dart';
import '../../core/storage/data_root_service.dart';
import '../design_system/design_tokens.dart';
import 'backup_providers.dart';
import 'backup_service.dart';
import '../../l10n/fly_localizations.dart';
import '../../l10n/settings_copy.dart';

class BackupSettingsDialog extends ConsumerStatefulWidget {
  const BackupSettingsDialog({this.embedded = false, super.key});
  final bool embedded;

  @override
  ConsumerState<BackupSettingsDialog> createState() =>
      _BackupSettingsDialogState();
}

class _BackupSettingsDialogState extends ConsumerState<BackupSettingsDialog> {
  String tr(String value) =>
      context.l10n.isZh ? value : settingsEnglish[value] ?? value;
  BackupSettings? _settings;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final value = await ref.read(backupServiceProvider).loadSettings();
    if (mounted) setState(() => _settings = value);
  }

  Future<void> _save(BackupSettings value) async {
    setState(() => _settings = value);
    await ref.read(backupServiceProvider).saveSettings(value);
  }

  Future<void> _chooseDirectory() async {
    final root = ref.read(dataRootPathProvider);
    final selected = await getDirectoryPath(
      initialDirectory: _settings?.directory ?? root,
      confirmButtonText: tr('使用此位置'),
    );
    if (selected != null) await _save(_settings!.copyWith(directory: selected));
  }

  Future<void> _backupNow() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final file = await ref
          .read(backupServiceProvider)
          .createBackup(directory: _settings?.directory);
      if (mounted) setState(() => _message = '${tr('备份成功')}: ${file.path}');
    } on Object catch (error) {
      if (mounted) {
        setState(() => _message = '${tr('备份失败')}: ${context.flyError(error)}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openBackupFolder() async {
    final root = ref.read(dataRootPathProvider);
    if (root == null) return;
    await FlyDataRootService().openInFileManager(
      _settings?.directory ?? '$root\\backups',
    );
  }

  Future<void> _restore() async {
    const group = XTypeGroup(label: 'Fly backup', extensions: ['zip']);
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null || !mounted) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr('恢复 Fly 备份？')),
            content: Text(
              tr(
                '恢复备份将替换当前 Fly 数据。当前数据会先自动创建一份 PreRestore 安全备份；验证或恢复失败时不会覆盖当前数据。',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr('取消')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr('继续恢复')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _message = tr('正在验证并安全恢复…');
    });
    final error = await ref
        .read(backupRuntimeActionsProvider)
        ?.restoreFrom(file.path);
    if (mounted) {
      setState(() {
        _busy = false;
        _message = error == null
            ? tr('恢复完成')
            : '${tr('恢复失败')}: ${context.flyError(error)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final dialog = AlertDialog(
      title: Text(tr('数据备份')),
      content: SizedBox(
        width: 480,
        child: settings == null
            ? const Center(child: CircularProgressIndicator.adaptive())
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile.adaptive(
                    key: const ValueKey('automatic-backup-toggle'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('每日自动备份')),
                    subtitle: Text(tr('每天第一次启动 Fly 后执行一次')),
                    value: settings.enabled,
                    onChanged: _busy
                        ? null
                        : (value) => _save(settings.copyWith(enabled: value)),
                  ),
                  const SizedBox(height: FlySpacing.xs),
                  Row(
                    children: [
                      Expanded(child: Text(tr('保留时间'))),
                      SegmentedButton<int>(
                        key: const ValueKey('backup-retention'),
                        segments: [
                          ButtonSegment(value: 7, label: Text(tr('7天'))),
                          ButtonSegment(value: 30, label: Text(tr('30天'))),
                        ],
                        selected: {settings.retentionDays},
                        showSelectedIcon: false,
                        onSelectionChanged: _busy
                            ? null
                            : (values) => _save(
                                settings.copyWith(retentionDays: values.first),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: FlySpacing.md),
                  Text(
                    tr(
                      '库文件采用增量备份。迁移或复制备份时，请同时保留 ZIP 和同目录的 .fly-file-objects 文件夹。',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: FlySpacing.md),
                  Text(
                    tr('备份位置'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          settings.directory ?? 'FlyData\\backups',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _chooseDirectory,
                        child: Text(tr('修改')),
                      ),
                    ],
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: FlySpacing.sm),
                    Text(
                      _message!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _openBackupFolder,
          child: Text(tr('打开文件夹')),
        ),
        TextButton(onPressed: _busy ? null : _restore, child: Text(tr('恢复备份'))),
        FilledButton.icon(
          key: const ValueKey('backup-now'),
          onPressed: _busy ? null : _backupNow,
          icon: const Icon(Icons.backup_outlined, size: 16),
          label: Text(tr('立即备份')),
        ),
        if (!widget.embedded)
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(tr('关闭')),
          ),
      ],
    );
    return widget.embedded
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              dialog.content!,
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: dialog.actions!),
            ],
          )
        : dialog;
  }
}
