import 'package:flutter_test/flutter_test.dart';
import 'package:fly/features/notes/domain/note_block.dart';
import 'package:fly/features/notes/domain/note_document_codec.dart';
import 'package:fly/features/notes/presentation/note_document_text_controller.dart';
import 'package:flutter/material.dart';

void main() {
  test('legacy blocks appear in one editable document', () {
    final blocks = [
      NoteBlock(
        id: 'heading',
        type: NoteBlockType.heading1.name,
        content: {'text': '客户开发'},
      ),
      NoteBlock(
        id: 'todo',
        type: NoteBlockType.checklist.name,
        content: {'text': '发送报价', 'checked': true},
      ),
      NoteBlock(
        id: 'table',
        type: NoteBlockType.table.name,
        content: {
          'rows': [
            ['产品', '价格'],
            ['WPC', '20'],
          ],
        },
      ),
      NoteBlock(
        id: 'image',
        type: NoteBlockType.image.name,
        content: {'attachmentId': 'image-1', 'caption': '样品'},
      ),
    ];
    final document = NoteDocumentCodec.read(blocks);
    expect(document, contains('# 客户开发'));
    expect(document, contains('- [x] 发送报价'));
    expect(document, contains('| WPC | 20 |'));

    final edited = NoteDocumentCodec.write(blocks, '$document\n\n下周复盘');
    expect(
      edited.where((b) => b.knownType == NoteBlockType.paragraph),
      hasLength(1),
    );
    expect(edited.first.id, 'heading');
    expect(edited.first.text, contains('下周复盘'));
    expect(edited.where((b) => b.id == 'image'), hasLength(1));
    expect(edited.last.content['attachmentId'], 'image-1');
    expect(NoteDocumentCodec.read(edited), '$document\n\n下周复盘');
  });

  test('unknown blocks survive editing without being overwritten', () {
    final unknown = NoteBlock(
      id: 'future',
      type: 'future-rich-content',
      content: {'data': 'keep'},
    );
    final edited = NoteDocumentCodec.write([unknown], 'New text');
    expect(edited.last.contentJson, unknown.contentJson);
    expect(NoteDocumentCodec.read(edited), 'New text');
  });

  testWidgets('styled continuous editor does not alter its text', (
    tester,
  ) async {
    final controller = NoteDocumentTextController(
      text: '# 客户开发\n- [ ] 联系 Jack\n普通正文',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final span = controller.buildTextSpan(
              context: context,
              style: const TextStyle(fontSize: 16),
              withComposing: false,
            );
            expect(span.toPlainText(), controller.text);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });
}
