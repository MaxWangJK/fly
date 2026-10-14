import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/design_system/responsive_layout.dart';
import '../task_providers.dart';

Future<void> completeTaskWithFeedback(
  BuildContext context,
  WidgetRef ref,
  String id,
  bool value,
) async {
  final repository = ref.read(taskRepositoryProvider);
  try {
    await repository.setCompleted(id, completed: value);
    if (!context.mounted || !isPhoneLayout(context) || !value) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.lightGreenAccent),
            SizedBox(width: 8),
            Text('任务已完成'),
          ],
        ),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            try {
              await repository.setCompleted(id, completed: false);
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('撤销失败：$error')));
              }
            }
          },
        ),
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 850),
            onEnd: () {
              entry.remove();
              entry.dispose();
            },
            builder: (_, value, _) => CustomPaint(painter: _Celebration(value)),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('任务保存失败：$error')));
    }
  }
}

class _Celebration extends CustomPainter {
  const _Celebration(this.progress);
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .4);
    for (var i = 0; i < 28; i++) {
      final angle = i * math.pi * 2 / 28;
      final radius = (40 + i % 5 * 12) * progress;
      final paint = Paint()
        ..color = [
          Colors.green,
          Colors.amber,
          Colors.teal,
          Colors.pink,
        ][i % 4].withValues(alpha: 1 - progress);
      canvas.drawCircle(
        center +
            Offset(
              math.cos(angle) * radius,
              math.sin(angle) * radius + 40 * progress * progress,
            ),
        3,
        paint,
      );
    }
    final check = Paint()
      ..color = Colors.green.withValues(alpha: 1 - progress)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(center.dx - 15, center.dy)
        ..lineTo(center.dx - 3, center.dy + 12)
        ..lineTo(center.dx + 20, center.dy - 15),
      check,
    );
  }

  @override
  bool shouldRepaint(_Celebration oldDelegate) =>
      oldDelegate.progress != progress;
}
