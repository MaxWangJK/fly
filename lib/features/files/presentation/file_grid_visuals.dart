import 'package:flutter/material.dart';

import '../../../shared/design_system/design_tokens.dart';

/// A small folder with layered paper, drawn at the actual icon size.
class FileFolderVisual extends StatelessWidget {
  const FileFolderVisual({required this.seed, this.large = false, super.key});

  final String seed;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = [
      scheme.primary,
      FlyColors.someday,
      FlyColors.warning,
      FlyColors.urgentLight,
      FlyColors.importantUrgent,
    ];
    final hash = seed.codeUnits.fold(
      0,
      (value, unit) => (value * 31 + unit) & 0x7fffffff,
    );
    final tint = colors[hash.abs() % colors.length];
    final dark = scheme.brightness == Brightness.dark;
    final front = Color.lerp(scheme.surface, tint, dark ? .42 : .32)!;
    final back = Color.lerp(scheme.surface, tint, dark ? .58 : .48)!;
    return SizedBox(
      width: large ? 100 : 64,
      height: large ? 72 : 48,
      child: CustomPaint(
        painter: _FolderPainter(
          front,
          back,
          scheme.surface,
          scheme.outlineVariant,
        ),
      ),
    );
  }
}

class _FolderPainter extends CustomPainter {
  const _FolderPainter(this.front, this.back, this.paper, this.outline);
  final Color front, back, paper, outline;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 48);
    final paint = Paint()..color = back;
    final path = Path()
      ..moveTo(2, 9)
      ..quadraticBezierTo(2, 3, 8, 3)
      ..lineTo(23, 3)
      ..quadraticBezierTo(26, 3, 28, 7)
      ..lineTo(56, 7)
      ..quadraticBezierTo(62, 7, 62, 13)
      ..lineTo(62, 41)
      ..lineTo(2, 41)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(8, 11, 47, 29),
        const Radius.circular(3),
      ),
      paint..color = Color.lerp(paper, back, .18)!,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(6, 15, 51, 27),
        const Radius.circular(3),
      ),
      paint..color = paper,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(1, 23, 62, 24),
        const Radius.circular(5),
      ),
      paint..color = front,
    );
    canvas.drawLine(
      const Offset(7, 24),
      const Offset(57, 24),
      paint
        ..color = outline.withValues(alpha: .3)
        ..strokeWidth = .7,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FolderPainter old) =>
      front != old.front ||
      back != old.back ||
      paper != old.paper ||
      outline != old.outline;
}

/// A recognizable document cover, not a preview of the document's contents.
class FileDocumentVisual extends StatelessWidget {
  const FileDocumentVisual({
    required this.extension,
    this.large = false,
    super.key,
  });
  final String extension;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = extension == 'PDF' ? scheme.error : scheme.primary;
    return Center(
      child: SizedBox(
        width: large ? 70 : 48,
        height: large ? 88 : 64,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.article_outlined, size: large ? 30 : 23, color: color),
              const SizedBox(height: 3),
              Text(
                extension.isEmpty ? 'FILE' : extension,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: color,
                  fontSize: large ? 12 : 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
