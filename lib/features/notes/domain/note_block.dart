import 'dart:convert';

enum NoteBlockType {
  paragraph,
  heading1,
  heading2,
  heading3,
  bullet,
  numbered,
  checklist,
  quote,
  divider,
  image,
  attachment,
  table,
  code,
}

class NoteBlock {
  NoteBlock({
    required this.id,
    required this.type,
    required Map<String, dynamic> content,
  }) : contentJson = jsonEncode(content);
  const NoteBlock.encoded({
    required this.id,
    required this.type,
    required this.contentJson,
  });
  final String id;

  /// Kept as a string so newer/unknown blocks survive old editor round trips.
  final String type, contentJson;
  Map<String, dynamic> get content =>
      Map<String, dynamic>.from(jsonDecode(contentJson) as Map);
  NoteBlockType? get knownType =>
      NoteBlockType.values.where((v) => v.name == type).firstOrNull;
  String get text => content['text'] as String? ?? '';

  void validate() {
    final value = content;
    if (id.isEmpty || type.isEmpty) {
      throw ArgumentError('Block ID/type required');
    }
    final kind = knownType;
    if (kind == null) return;
    if (kind == NoteBlockType.table) {
      final rows = value['rows'];
      if (rows is! List || rows.isEmpty || rows.length > 200) {
        throw ArgumentError('表格需要 1–200 行');
      }
      final width = rows.first is List ? (rows.first as List).length : 0;
      if (width < 1 ||
          width > 30 ||
          rows.any(
            (r) =>
                r is! List || r.length != width || r.any((c) => c is! String),
          )) {
        throw ArgumentError('表格单元格必须是等宽字符串数组');
      }
    } else if (kind == NoteBlockType.image ||
        kind == NoteBlockType.attachment) {
      if (value['attachmentId'] is! String ||
          (value['attachmentId'] as String).isEmpty) {
        throw ArgumentError('附件不能为空');
      }
    } else if (kind != NoteBlockType.divider) {
      if (value['text'] is! String) throw ArgumentError('块文字必须为字符串');
      if (kind == NoteBlockType.checklist && value['checked'] is! bool) {
        throw ArgumentError('Checklist 状态必须为布尔值');
      }
    }
  }

  static NoteBlockType? shortcut(String prefix) => switch (prefix) {
    '# ' => NoteBlockType.heading1,
    '## ' => NoteBlockType.heading2,
    '### ' => NoteBlockType.heading3,
    '- ' => NoteBlockType.bullet,
    '1. ' => NoteBlockType.numbered,
    '[] ' || '- [ ] ' => NoteBlockType.checklist,
    '> ' => null,
    _ => null,
  };
}
