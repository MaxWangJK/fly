import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// A compact, flat entry point into a detail extension panel.
///
/// The entry keeps hierarchy through typography, spacing and a single divider
/// instead of nesting another bordered card inside the detail surface.
class DetailSectionEntry extends StatelessWidget {
  const DetailSectionEntry({
    required this.title,
    required this.icon,
    required this.preview,
    required this.onTap,
    this.meta,
    super.key,
  });

  final String title;
  final IconData icon;
  final Widget preview;
  final String? meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(FlyRadius.sm),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FlyRadius.sm),
      hoverColor: Theme.of(context).hoverColor.withValues(alpha: .62),
      focusColor: FlyColors.accent.withValues(alpha: .08),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(8, 10, 6, 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: .72),
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                icon,
                size: 17,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  preview,
                  if (meta != null) ...[
                    const SizedBox(height: 4),
                    Text(meta!, style: Theme.of(context).textTheme.labelSmall),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.chevron_right, size: 18),
            ),
          ],
        ),
      ),
    ),
  );
}
