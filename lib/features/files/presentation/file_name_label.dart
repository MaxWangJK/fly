import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Keep both identifying ends and the extension, without changing the stored name.
class FileNameLabel extends StatelessWidget {
  const FileNameLabel({required this.name, this.style, super.key});
  final String name;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: name,
    child: Semantics(
      label: name,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final effectiveStyle = DefaultTextStyle.of(context).style
                .merge(style);
            final painter = TextPainter(
              textDirection: Directionality.of(context),
              locale: Localizations.maybeLocaleOf(context),
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 1,
            );
            bool fits(String text) {
              painter.text = TextSpan(text: text, style: effectiveStyle);
              painter.layout();
              return painter.width <= constraints.maxWidth;
            }

            var display = name;
            if (constraints.hasBoundedWidth && !fits(name)) {
              final extension = p.extension(name);
              final stem = name
                  .substring(0, name.length - extension.length)
                  .characters
                  .toList();
              String abbreviated(int count) {
                final tail = count ~/ 2;
                return '${stem.take(count - tail).join()}....${stem.skip(stem.length - tail).join()}$extension';
              }

              var low = 0, high = stem.length;
              while (low < high) {
                final middle = (low + high + 1) ~/ 2;
                if (fits(abbreviated(middle))) {
                  low = middle;
                } else {
                  high = middle - 1;
                }
              }
              display = abbreviated(low);
              if (!fits(display) && extension.isNotEmpty) display = extension;
            }
            painter.dispose();
            return Text(
              display,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: style,
            );
          },
        ),
      ),
    ),
  );
}
