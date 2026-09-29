import 'package:flutter/material.dart';

import 'design_tokens.dart';

Future<bool> showFlyDeleteContextMenu(
  BuildContext context,
  Offset position, {
  required String label,
}) async {
  final action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    items: [
      PopupMenuItem(
        value: 'delete',
        child: Row(
          children: [
            const Icon(Icons.delete_outline, size: 17, color: FlyColors.danger),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: FlyColors.danger)),
          ],
        ),
      ),
    ],
  );
  return action == 'delete';
}

Future<bool> confirmFlyDestructiveAction(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = '删除',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const ValueKey('confirm-destructive-action'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: FlyColors.danger),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ) ??
    false;
