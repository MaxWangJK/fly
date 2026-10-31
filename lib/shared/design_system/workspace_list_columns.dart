import 'package:flutter/material.dart';

/// One column layout for both the table heading and its selectable records.
class WorkspaceListColumns extends StatelessWidget {
  const WorkspaceListColumns({
    required this.primary,
    required this.secondary,
    required this.status,
    required this.date,
    this.marker,
    this.leading,
    this.leadingWidth = 0,
    this.dateWidth = 88,
    this.trailing,
    this.trailingWidth = 0,
    super.key,
  });

  final Widget primary, secondary, status, date;
  final Widget? marker, leading, trailing;
  final double leadingWidth, dateWidth, trailingWidth;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 2, child: marker),
      const SizedBox(width: 6),
      if (leadingWidth > 0) SizedBox(width: leadingWidth, child: leading),
      Expanded(flex: 4, child: primary),
      const SizedBox(width: 6),
      Expanded(flex: 3, child: secondary),
      const SizedBox(width: 6),
      Expanded(flex: 3, child: status),
      const SizedBox(width: 6),
      SizedBox(width: dateWidth, child: date),
      if (trailingWidth > 0) ...[
        const SizedBox(width: 6),
        SizedBox(width: trailingWidth, child: trailing),
      ],
      const SizedBox(width: 8),
    ],
  );
}

class WorkspaceListHeader extends StatelessWidget {
  const WorkspaceListHeader({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
        child: child,
      ),
    ),
  );
}

/// Labels stay next to values when a phone uses cards instead of table columns.
class WorkspaceListField extends StatelessWidget {
  const WorkspaceListField({
    required this.label,
    required this.value,
    super.key,
  });
  final String label, value;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        TextSpan(text: value.trim().isEmpty ? '—' : value),
      ],
    ),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  );
}
