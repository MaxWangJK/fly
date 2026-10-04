import 'package:flutter/material.dart';

/// One editable text surface with quiet Markdown line styling.
/// During IME composition Flutter's default span builder takes precedence so
/// Chinese input, selection and candidate text remain predictable.
class NoteDocumentTextController extends TextEditingController {
  NoteDocumentTextController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (withComposing &&
        value.composing.isValid &&
        !value.composing.isCollapsed) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;
    final lines = text.split('\n');
    final spans = <InlineSpan>[];
    var fencedCode = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final marker = RegExp(r'^(#{1,3}|- \[[ xX]\]|-|\d+\.|>)\s')
          .firstMatch(line);
      TextStyle? lineStyle;
      if (line.startsWith('```')) {
        fencedCode = !fencedCode;
        lineStyle = style?.copyWith(fontFamily: 'Consolas', color: muted);
      } else if (fencedCode) {
        lineStyle = style?.copyWith(fontFamily: 'Consolas');
      } else if (line.startsWith('# ')) {
        lineStyle = theme.textTheme.headlineSmall?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        );
      } else if (line.startsWith('## ')) {
        lineStyle = theme.textTheme.titleLarge?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        );
      } else if (line.startsWith('### ')) {
        lineStyle = theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        );
      } else if (line.startsWith('> ')) {
        lineStyle = style?.copyWith(color: muted, fontStyle: FontStyle.italic);
      }
      if (marker != null && !fencedCode) {
        spans.add(
          TextSpan(
            text: line.substring(0, marker.end),
            style: (lineStyle ?? style)?.copyWith(color: accent),
          ),
        );
        spans.add(TextSpan(text: line.substring(marker.end), style: lineStyle));
      } else {
        spans.add(TextSpan(text: line, style: lineStyle));
      }
      if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
    }
    return TextSpan(style: style, children: spans);
  }
}
