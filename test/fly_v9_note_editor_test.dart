import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/features/notes/domain/note_block.dart';
import 'package:fly/features/notes/presentation/note_block_editor.dart';
import 'package:fly/l10n/fly_localizations.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    List<NoteBlock> initial,
    ValueChanged<List<NoteBlock>> changed,
  ) async {
    var blocks = initial;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: FlyLocalizations.supportedLocales,
        localizationsDelegates: const [
          FlyLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => NoteBlockEditor(
              blocks: blocks,
              onChanged: (next) {
                setState(() => blocks = next);
                changed(next);
              },
              onAddMedia: (_) {},
              mediaBuilder: (_, block) =>
                  Text(block.content['attachmentId'] as String),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Markdown conversion preserves identity and subsequent input', (
    tester,
  ) async {
    var result = <NoteBlock>[];
    await mount(tester, [
      NoteBlock(id: 'p', type: 'paragraph', content: {'text': ''}),
    ], (next) => result = next);
    final field = find.byKey(const ValueKey('block-text-p'));
    await tester.enterText(field, '# ');
    await tester.pump();
    expect(result.single.id, 'p');
    expect(result.single.knownType, NoteBlockType.heading1);
    expect(result.single.text, isEmpty);
    await tester.enterText(field, '客户开发方法');
    await tester.pump();
    expect(result.single.text, '客户开发方法');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Checklist updates without losing text and duplicate has a new ID',
    (tester) async {
      var result = <NoteBlock>[];
      await mount(tester, [
        NoteBlock(
          id: 'c',
          type: 'checklist',
          content: {'text': '联系 Jack', 'checked': false},
        ),
      ], (next) => result = next);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(result.single.content['checked'], true);
      expect(result.single.text, '联系 Jack');
      await tester.tap(find.byTooltip('块操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制块'));
      await tester.pumpAndSettle();
      expect(result.length, 2);
      expect(result[0].id, isNot(result[1].id));
      expect(result[0].contentJson, result[1].contentJson);
    },
  );

  testWidgets('Table edits and row additions preserve cell content', (
    tester,
  ) async {
    var result = <NoteBlock>[];
    await mount(tester, [
      NoteBlock(
        id: 't',
        type: 'table',
        content: {
          'rows': [
            ['名称', '价格'],
            ['', ''],
          ],
        },
      ),
    ], (next) => result = next);
    await tester.enterText(find.byKey(const ValueKey('t-1-0')), 'WPC');
    await tester.pump();
    await tester.tap(find.text('+ 行'));
    await tester.pump();
    final rows = result.single.content['rows'] as List;
    expect(rows.length, 3);
    expect(rows[1][0], 'WPC');
    result.single.validate();
    expect(tester.takeException(), isNull);
  });
}
