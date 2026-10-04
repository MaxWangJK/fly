import 'package:uuid/uuid.dart';

import 'note_block.dart';

/// Presents legacy note blocks as one continuous, Markdown-friendly document.
/// Media and future/unknown blocks remain in storage when the body is edited.
class NoteDocumentCodec {
  const NoteDocumentCodec._();

  static String read(List<NoteBlock> blocks) => blocks
      .map(_line)
      .where((line) => line != null)
      .cast<String>()
      .join('\n\n');

  static String? _line(NoteBlock block) {
    final text = block.text;
    return switch (block.knownType) {
      NoteBlockType.paragraph => text,
      NoteBlockType.heading1 => '# $text',
      NoteBlockType.heading2 => '## $text',
      NoteBlockType.heading3 => '### $text',
      NoteBlockType.bullet => '- $text',
      NoteBlockType.numbered => '1. $text',
      NoteBlockType.checklist =>
        '- [${block.content['checked'] == true ? 'x' : ' '}] $text',
      NoteBlockType.quote => '> $text',
      NoteBlockType.divider => '---',
      NoteBlockType.code => '```\n$text\n```',
      NoteBlockType.table => _table(block),
      NoteBlockType.image || NoteBlockType.attachment || null => null,
    };
  }

  static String _table(NoteBlock block) {
    final rows = (block.content['rows'] as List).cast<List>();
    if (rows.isEmpty) return '';
    final lines = <String>[];
    for (var index = 0; index < rows.length; index++) {
      lines.add('| ${rows[index].map((cell) => '$cell').join(' | ')} |');
      if (index == 0) {
        lines.add('| ${rows[index].map((_) => '---').join(' | ')} |');
      }
    }
    return lines.join('\n');
  }

  /// Collapse editable text into one paragraph; retain media/unknown blocks.
  /// The original note stays unchanged until the user actually edits it.
  static List<NoteBlock> write(List<NoteBlock> previous, String text) {
    final firstText = previous.where(_isText).firstOrNull;
    final document = NoteBlock(
      id: firstText?.id ?? const Uuid().v7(),
      type: NoteBlockType.paragraph.name,
      content: {'text': text},
    );
    final result = <NoteBlock>[];
    var inserted = false;
    for (final block in previous) {
      if (_isText(block)) {
        if (!inserted) {
          result.add(document);
          inserted = true;
        }
      } else {
        result.add(block);
      }
    }
    if (!inserted) result.insert(0, document);
    return result;
  }

  static bool _isText(NoteBlock block) => switch (block.knownType) {
    NoteBlockType.image || NoteBlockType.attachment || null => false,
    _ => true,
  };
}
