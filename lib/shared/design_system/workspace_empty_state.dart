import 'package:flutter/material.dart';

import '../../l10n/fly_localizations.dart';
import '../search/global_search_palette.dart';
import 'responsive_layout.dart';

class WorkspaceEmptyState extends StatelessWidget {
  const WorkspaceEmptyState({
    required this.icon,
    required this.title,
    required this.actionLabel,
    required this.onCreate,
    super.key,
  });
  final IconData icon;
  final String title, actionLabel;
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 42,
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: .5),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 18),
              label: Text(actionLabel),
            ),
            if (!isPhoneLayout(context)) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => showGlobalSearchPalette(context),
                icon: const Icon(Icons.search, size: 16),
                label: Text('${context.l10n.t('globalSearch')} · Ctrl+K'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
