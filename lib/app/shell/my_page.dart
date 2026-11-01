import '../../features/account/data/local_profile.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/design_system/responsive_layout.dart';
import '../../config/feature_flags.dart';
import '../../features/sync/presentation/sync_controller.dart';
import '../../l10n/fly_localizations.dart';
import '../settings/navigation_settings.dart';
import '../settings/settings_center.dart';

class MyPage extends ConsumerWidget {
  const MyPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zh = context.l10n.isZh;
    final sync = ref.watch(syncControllerProvider);
    final profile = ref.watch(localProfileProvider).valueOrNull;
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
            leading: CircleAvatar(
              backgroundImage: profile?.avatar == null
                  ? null
                  : MemoryImage(profile!.avatar!),
              child: profile?.avatar == null
                  ? const Icon(Icons.person_outline)
                  : null,
            ),
            title: Text(
              profile?.name.isNotEmpty == true
                  ? profile!.name
                  : sync.auth.email ?? (zh ? '本地账户' : 'Local account'),
            ),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => const SettingsCenter(initialCategory: '我的'),
            ),
            subtitle: Text(
              zh
                  ? '数据保存在此设备，可与电脑同步'
                  : 'Saved on this device, with desktop sync',
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
