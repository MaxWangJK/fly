import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_tokens.dart';

class FlyExtensionHeader extends StatelessWidget {
  const FlyExtensionHeader({
    required this.title,
    required this.onClose,
    this.closeKey,
    super.key,
  });

  final String title;
  final VoidCallback onClose;
  final Key? closeKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          key: closeKey,
          tooltip: '关闭',
          onPressed: onClose,
          icon: const Icon(Icons.close, size: 19),
        ),
      ],
    ),
  );
}

class FlySubmitOnEnter extends StatelessWidget {
  const FlySubmitOnEnter({
    required this.onSubmit,
    required this.child,
    super.key,
  });

  final VoidCallback onSubmit;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter &&
          !HardwareKeyboard.instance.isShiftPressed) {
        onSubmit();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: child,
  );
}

class FlyHistoryBlock extends StatelessWidget {
  const FlyHistoryBlock({
    required this.color,
    required this.meta,
    required this.content,
    this.footer,
    this.menu,
    super.key,
  });

  final Color color;
  final String meta;
  final String content;
  final String? footer;
  final Widget? menu;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
    decoration: BoxDecoration(
      color: color.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? .18 : .78,
      ),
      borderRadius: BorderRadius.circular(FlyRadius.md),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(meta, style: Theme.of(context).textTheme.labelSmall),
            ),
            if (menu != null) SizedBox(width: 30, height: 26, child: menu),
          ],
        ),
        if (content.trim().isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(content, style: const TextStyle(fontSize: 13, height: 1.45)),
        ],
        if (footer != null) ...[
          const SizedBox(height: 6),
          Text(footer!, style: Theme.of(context).textTheme.labelSmall),
        ],
      ],
    ),
  );
}
