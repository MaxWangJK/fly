import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/fly_localizations.dart';
import '../../../shared/design_system/design_tokens.dart';
import '../data/local_profile.dart';

class LocalProfileAvatar extends ConsumerWidget {
  const LocalProfileAvatar({this.hideWhenEmpty = false, super.key});
  final bool hideWhenEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(localProfileProvider).valueOrNull;
    if (hideWhenEmpty && profile?.avatar == null) {
      return const SizedBox.shrink();
    }
    final fallback = Icon(
      Icons.person_outline_rounded,
      size: FlyMetrics.iconLg,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Tooltip(
      message: profile?.name.isNotEmpty == true
          ? profile!.name
          : (context.l10n.isZh ? '我的' : 'Me'),
      child: Container(
        key: const ValueKey('primary-profile-avatar'),
        width: 34,
        height: 34,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(FlyRadius.md),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: profile?.avatar == null
            ? fallback
            : Image.memory(
                profile!.avatar!,
                key: const ValueKey('primary-profile-image'),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}
