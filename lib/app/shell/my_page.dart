import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/design_system/responsive_layout.dart';
import '../../config/feature_flags.dart';
import '../../features/sync/presentation/sync_controller.dart';
import '../../features/sync/presentation/sync_settings_panel.dart';
import '../../l10n/fly_localizations.dart';
import '../settings/navigation_settings.dart';
import '../settings/settings_center.dart';
import 'mobile_details.dart';

class MyPage extends ConsumerWidget {
  const MyPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zh = context.l10n.isZh;
    final sync = ref.watch(syncControllerProvider);
    final navigation = ref.watch(navigationSettingsProvider).value;
    return ListView(
      key: const ValueKey('my-page'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          zh ? '我的' : 'Me',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(sync.auth.email ?? (zh ? '本地账户' : 'Local account')),
            subtitle: Text(
              zh
                  ? '数据保存在此设备，可通过云端或电脑同步'
                  : 'Saved on this device, with cloud or desktop sync',
            ),
          ),
        ),
        ListTile(
          key: const ValueKey('my-account'),
          leading: const Icon(Icons.manage_accounts_outlined),
          title: Text(zh ? '账户设置' : 'Account settings'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showWorkspaceSheet(
            context,
            Builder(
              builder: (sheet) => sheetContent(
                sheet,
                zh ? '账户设置' : 'Account settings',
                const SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: SyncSettingsPanel(accountOnly: true),
                ),
              ),
            ),
          ),
        ),
        ListTile(
          key: const ValueKey('my-settings'),
          leading: const Icon(Icons.settings_outlined),
          title: Text(zh ? '设置' : 'Settings'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => const SettingsCenter(),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.sync),
          title: Text(zh ? '同步设置' : 'Sync settings'),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => const SettingsCenter(initialCategory: '同步'),
          ),
        ),
        const Divider(),
        if (!isPhoneLayout(context) && navigation.dashboardVisible)
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: Text(context.l10n.t('navHome')),
            onTap: () => context.go('/dashboard'),
          ),
        if (!isPhoneLayout(context))
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(context.l10n.t('navNotes')),
            onTap: () =>
                context.go(enableKnowledgeHub ? '/knowledge' : '/notes'),
          ),
        if (!isPhoneLayout(context) && navigation.toolsVisible)
          ListTile(
            leading: const Icon(Icons.handyman_outlined),
            title: Text(context.l10n.t('tools')),
            onTap: () => context.go('/tools/container-loading'),
          ),
      ],
    );
  }
}
