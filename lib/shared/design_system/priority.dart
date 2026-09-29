import 'package:flutter/material.dart';

import '../domain/priority.dart';
import 'design_tokens.dart';

abstract final class PriorityColorTokens {
  static const highSoft = Color(0xFFFFF7F6);
  static const highSelected = Color(0xFFFFEFED);
  static const highAccent = Color(0xFFB65358);
  static const mediumSoft = Color(0xFFFFFBF3);
  static const mediumSelected = Color(0xFFFFF5E1);
  static const mediumAccent = Color(0xFFA87324);

  static Color accent(PriorityLevel priority) => switch (priority) {
    PriorityLevel.high => highAccent,
    PriorityLevel.medium => mediumAccent,
    PriorityLevel.low => FlyColors.inkMutedLight,
  };

  static Color optionBackground(PriorityLevel priority) => switch (priority) {
    PriorityLevel.high => highSelected,
    PriorityLevel.medium => mediumSelected,
    PriorityLevel.low => FlyColors.selectedLight,
  };

  static Color rowBackground(
    BuildContext context,
    PriorityLevel priority, {
    required bool selected,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      final base = switch (priority) {
        PriorityLevel.high => highAccent.withValues(alpha: .16),
        PriorityLevel.medium => mediumAccent.withValues(alpha: .14),
        PriorityLevel.low => Colors.transparent,
      };
      return selected
          ? Color.alphaBlend(
              FlyColors.accent.withValues(alpha: .18),
              base == Colors.transparent ? FlyColors.surfaceDark : base,
            )
          : base;
    }

    final base = switch (priority) {
      PriorityLevel.high => highSoft,
      PriorityLevel.medium => mediumSoft,
      PriorityLevel.low => Colors.transparent,
    };
    if (!selected) return base;
    return switch (priority) {
      PriorityLevel.high => highSelected,
      PriorityLevel.medium => mediumSelected,
      PriorityLevel.low => FlyColors.selectedLight,
    };
  }
}

class PrioritySelector extends StatelessWidget {
  const PrioritySelector({
    required this.value,
    required this.onChanged,
    this.compact = false,
    super.key,
  });

  final PriorityLevel value;
  final ValueChanged<PriorityLevel> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final priority in const [
        PriorityLevel.high,
        PriorityLevel.medium,
        PriorityLevel.low,
      ])
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 5),
            child: _PriorityOption(
              priority: priority,
              selected: priority == value,
              compact: compact,
              onTap: () => onChanged(priority),
            ),
          ),
        ),
    ],
  );
}

class _PriorityOption extends StatelessWidget {
  const _PriorityOption({
    required this.priority,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final PriorityLevel priority;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = PriorityColorTokens.accent(priority);
    return Material(
      color: selected
          ? PriorityColorTokens.optionBackground(priority)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(FlyRadius.sm),
      child: InkWell(
        key: ValueKey('priority-${priority.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(FlyRadius.sm),
        child: Container(
          height: compact ? 28 : 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FlyRadius.sm),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: .45)
                  : Theme.of(context).dividerColor,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: compact ? 14 : 15,
                color: selected ? accent : null,
              ),
              const SizedBox(width: 4),
              Text(
                priority.label,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? accent : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
