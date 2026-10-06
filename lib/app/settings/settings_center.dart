import '../../l10n/service_error_copy.dart';

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/database/app_database.dart';
import '../../config/feature_flags.dart';
import '../../config/app_version.dart';
import '../../l10n/fly_localizations.dart';
import '../../l10n/settings_copy.dart';
import '../../core/storage/data_root_providers.dart';
import '../../features/tasks/presentation/task_providers.dart';
import '../../features/customers/import/customer_import_dialog.dart';
import '../../shared/design_system/fly_color_scheme.dart';
import '../../shared/backup/backup_settings_dialog.dart';
import '../../shared/notifications/reminder_settings_dialog.dart';
import '../../shared/export/fly_excel_export_service.dart';
import 'navigation_settings.dart';

class SettingsCenter extends ConsumerStatefulWidget {
  const SettingsCenter({super.key});
  @override
  ConsumerState<SettingsCenter> createState() => _SettingsCenterState();
}

class _SettingsCenterState extends ConsumerState<SettingsCenter> {
  String tr(String value) =>
      context.l10n.isZh ? value : settingsEnglish[value] ?? value;
  static const appVersion = flyAppVersion;
  static const categories = [
    '常规',
    '外观',
    '导航',
    '提醒',
    '数据与备份',
    '文件与存储',
    '导入与导出',
    '关于',
  ];
  int selected = 0;
  bool busy = false;
  String? error;
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => error = '${tr('操作失败')}: ${context.flyError(e)}');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _save(String key, String value, VoidCallback apply) =>
      _run(() async {
        await ref
            .read(databaseProvider)
            .into(ref.read(databaseProvider).appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: key,
                value: value,
                updatedAt: DateTime.now(),
              ),
            );
        apply();
      });
  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 10),
    child: Text(
      tr(title),
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
  Widget _row(String title, String subtitle, {Widget? control}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(title)),
              if (subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    tr(subtitle),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        if (control != null) ...[const SizedBox(width: 12), control],
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Dialog(
    key: const ValueKey('settings-center'),
    insetPadding: const EdgeInsets.all(16),
    backgroundColor: Theme.of(context).colorScheme.surface,
    child: SizedBox(
      width: 1050,
      height: 740,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 12, 12),
            child: Row(
              children: [
                Text(tr('设置'), style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  tooltip: tr('关闭设置'),
                  onPressed: busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, bounds) {
                final content = SingleChildScrollView(
                  key: ValueKey('settings-content-$selected'),
                  padding: const EdgeInsets.all(24),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 740),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            tr(categories[selected]),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (error != null)
                            Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ..._content(),
                        ],
                      ),
                    ),
                  ),
                );
                if (bounds.maxWidth < 680) {
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: DropdownButton<int>(
                          key: const ValueKey('settings-category-selector'),
                          isExpanded: true,
                          value: selected,
                          items: [
                            for (var i = 0; i < categories.length; i++)
                              DropdownMenuItem(
                                value: i,
                                child: Text(tr(categories[i])),
                              ),
                          ],
                          onChanged: (i) => setState(() => selected = i!),
                        ),
                      ),
                      Expanded(child: content),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 200,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          for (var i = 0; i < categories.length; i++)
                            ListTile(
                              key: ValueKey('settings-category-$i'),
                              dense: true,
                              selected: selected == i,
                              selectedTileColor: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: .09),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              title: Text(tr(categories[i])),
                              onTap: () => setState(() {
                                selected = i;
                                error = null;
                              }),
                            ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: content),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _content() {
    final nav = ref.watch(navigationSettingsProvider);
    final root = ref.watch(dataRootPathProvider);
    switch (selected) {
      case 0:
        return [
          _heading('语言'),
          _row(
            '界面语言',
            '',
            control: DropdownButton<String>(
              value: ref.watch(localeProvider).languageCode,
              items: const [
                DropdownMenuItem(value: 'zh', child: Text('简体中文')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: busy
                  ? null
                  : (v) => _save(
                      'locale',
                      v!,
                      () => ref.read(localeProvider.notifier).state = Locale(v),
                    ),
            ),
          ),
          const Divider(),
          _heading('启动行为'),
          _row('默认启动页面', _startupLabel(nav.value)),
          Text(
            tr('按导航显隐设置选择：Dashboard → 客户今天 → 任务今天。'),
            style: const TextStyle(fontSize: 12),
          ),
        ];
      case 1:
        return [
          _heading('显示模式'),
          _row(
            '主题',
            '保留当前配色方案',
            control: DropdownButton<ThemeMode>(
              value: ref.watch(themeModeProvider),
              items: [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text(tr('跟随系统')),
                ),
                DropdownMenuItem(value: ThemeMode.light, child: Text(tr('浅色'))),
                DropdownMenuItem(value: ThemeMode.dark, child: Text(tr('深色'))),
              ],
              onChanged: busy
                  ? null
                  : (v) => _save(
                      'themeMode',
                      v!.name,
                      () => ref.read(themeModeProvider.notifier).state = v,
                    ),
            ),
          ),
          const Divider(),
          _heading('配色方案'),
          _paletteChooser(),
        ];
      case 2:
        return [
          _heading('一级模块'),
          SwitchListTile(
            key: const ValueKey('dashboard-visible'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('显示 Dashboard')),
            value: nav.value.dashboardVisible,
            onChanged: nav.saving || !nav.loaded
                ? null
                : (v) => nav.update(nav.value.copyWith(dashboardVisible: v)),
          ),
          const Divider(),
          SwitchListTile(
            key: const ValueKey('crm-visible'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('显示客户与订单')),
            subtitle: Text(tr('客户和订单联动；隐藏不会删除任何业务数据')),
            value: nav.value.crmVisible,
            onChanged: nav.saving || !nav.loaded
                ? null
                : (v) => nav.update(nav.value.copyWith(crmVisible: v)),
          ),
          SwitchListTile(
            key: const ValueKey('tools-visible'),
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.isZh ? '显示工具' : 'Show tools'),
            value: nav.value.toolsVisible,
            onChanged: nav.saving || !nav.loaded
                ? null
                : (v) => nav.update(nav.value.copyWith(toolsVisible: v)),
          ),
          if (nav.error != null)
            Text(
              nav.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const Divider(),
          _row(
            '始终显示',
            context.l10n.isZh
                ? '任务、日历、四象限、文件、笔记与设置'
                : 'Tasks, Calendar, Matrix, Files, Notes and Settings',
          ),
          _heading('启动页面'),
          _row('当前默认', _startupLabel(nav.value)),
        ];
      case 3:
        return [
          const SizedBox(height: 12),
          const ReminderSettingsDialog(embedded: true),
        ];
      case 4:
        return [
          const SizedBox(height: 12),
          if (root != null)
            const BackupSettingsDialog(embedded: true)
          else
            Text(tr('数据目录尚未初始化，请在正式桌面环境中配置后使用备份。')),
        ];
      case 5:
        return [
          _heading('本地数据'),
          _row('FlyData', root ?? '未配置'),
          _row(
            '附件位置',
            root == null
                ? '未配置'
                : '${p.join(root, 'attachments')}\n${p.join(root, 'customers')}\n${p.join(root, 'orders')}',
          ),
          const Divider(),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: root == null || busy
                    ? null
                    : () => _run(() async {
                        await ref.read(dataRootActionsProvider)?.open();
                      }),
                child: Text(tr('打开数据目录')),
              ),
              TextButton(
                onPressed: root == null || busy
                    ? null
                    : () => _run(_changeData),
                child: Text(tr('更改并迁移数据目录')),
              ),
            ],
          ),
          Text(
            tr('迁移会复制并校验数据库和附件，成功后再切换；不会仅更改路径。'),
            style: const TextStyle(fontSize: 12),
          ),
        ];
      case 6:
        return [
          _heading('Excel 导出'),
          _row(
            '全部客户与订单',
            '导出工作簿；附件实体文件不包含在 Excel 中',
            control: TextButton(
              onPressed: busy ? null : () => _run(_export),
              child: Text(tr('导出 Excel')),
            ),
          ),
          const Divider(),
          _heading('Excel 导入'),
          _row(
            '客户导入',
            '选择工作簿、预览与处理重复客户',
            control: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const CustomerImportDialog(),
              ),
              child: Text(tr('导入客户')),
            ),
          ),
        ];
      default:
        return [
          _heading('Fly'),
          _row('版本', appVersion),
          _row('数据版本', '${ref.read(databaseProvider).schemaVersion}'),
          const Divider(),
          _row(
            '授权信息',
            enableLocalLicense ? '本地授权已启用；有效期以激活界面为准' : '内部开发版：本地授权未启用',
          ),
          TextButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'Fly',
              applicationVersion: appVersion,
            ),
            child: Text(tr('第三方组件许可')),
          ),
        ];
    }
  }

  Widget _paletteChooser() {
    final selectedPalette = ref.watch(flyPaletteProvider);
    return LayoutBuilder(
      builder: (context, bounds) {
        final columns = bounds.maxWidth >= 680
            ? 3
            : bounds.maxWidth >= 420
            ? 2
            : 1;
        const gap = 12.0;
        final width = (bounds.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final palette in FlyPaletteId.values)
              SizedBox(
                width: width,
                child: Semantics(
                  button: true,
                  selected: selectedPalette == palette,
                  child: Material(
                    color: selectedPalette == palette
                        ? context.flyColors.selected
                        : context.flyColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: selectedPalette == palette
                            ? context.flyColors.accent
                            : context.flyColors.divider,
                        width: selectedPalette == palette ? 1.5 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: ValueKey('palette-${palette.name}'),
                      onTap: busy
                          ? null
                          : () => _save(
                              'colorPalette',
                              palette.name,
                              () =>
                                  ref.read(flyPaletteProvider.notifier).state =
                                      palette,
                            ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _PalettePreview(
                              FlyColorScheme.resolve(palette, Brightness.light),
                            ),
                            const SizedBox(height: 9),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    tr(palette.label),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge,
                                  ),
                                ),
                                if (selectedPalette == palette)
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 17,
                                    color: context.flyColors.accent,
                                  ),
                              ],
                            ),
                            Text(
                              tr(switch (palette) {
                                FlyPaletteId.flyDefault => '温和米杏',
                                FlyPaletteId.graphite => '中性石墨',
                                FlyPaletteId.warmSand => '暖调沙色',
                                FlyPaletteId.ocean => '清透海蓝',
                                FlyPaletteId.forest => '自然森林',
                                FlyPaletteId.clarity => '灰白与深紫',
                                FlyPaletteId.mintCloud => '冷白与薄荷',
                              }),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _startupLabel(NavigationSettings value) => value.dashboardVisible
      ? 'Dashboard'
      : value.crmVisible
      ? tr('客户 → 今天')
      : tr('任务 → 今天');
  Future<void> _changeData() async {
    final root = ref.read(dataRootPathProvider);
    final actions = ref.read(dataRootActionsProvider);
    if (root == null || actions == null) return;
    final path = await getDirectoryPath(
      initialDirectory: root,
      confirmButtonText: tr('迁移到这里'),
    );
    if (path == null || path == root || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('迁移 Fly 数据目录？')),
        content: Text(
          '${tr('复制并校验全部数据到：')}\n$path\n${tr('新目录必须为空，失败时仍使用当前目录。')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('迁移')),
          ),
        ],
      ),
    );
    if (confirmed == true) await actions.changeTo(path);
  }

  Future<void> _export() async {
    final location = await getSaveLocation(
      suggestedName: 'Fly-${tr('全部客户与订单')}.xlsx',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Excel', extensions: ['xlsx']),
      ],
    );
    if (location == null) return;
    final bytes = await FlyExcelExportService(ref.read(databaseProvider))
        .buildWorkbook();
    await File(location.path).writeAsBytes(bytes, flush: true);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Excel 已导出'))));
    }
  }
}

class _PalettePreview extends StatelessWidget {
  const _PalettePreview(this.colors);

  final FlyColorScheme colors;

  @override
  Widget build(BuildContext context) => Container(
    height: 68,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: colors.divider),
    ),
    clipBehavior: Clip.antiAlias,
    child: Row(
      children: [
        SizedBox(width: 17, child: ColoredBox(color: colors.primaryRail)),
        SizedBox(width: 42, child: ColoredBox(color: colors.secondarySidebar)),
        Expanded(
          child: ColoredBox(
            color: colors.canvas,
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 50,
                    height: 7,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: ColoredBox(color: colors.surface),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          flex: 2,
                          child: ColoredBox(color: colors.selected),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
