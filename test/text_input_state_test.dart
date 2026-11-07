import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/features/files/presentation/mobile_file_browser.dart';
import 'package:fly/shared/design_system/mobile_workspace_actions.dart';
import 'package:fly/shared/design_system/model_text_field.dart';

EditableText editable(WidgetTester tester, Finder finder) =>
    tester.widget<EditableText>(
      find.descendant(of: finder, matching: find.byType(EditableText)),
    );

Future<void> typeAtCaret(
  WidgetTester tester,
  Finder finder,
  String text,
) async {
  final field = editable(tester, finder);
  expect(
    field.focusNode.hasFocus,
    isTrue,
    reason: 'Typing must not need another click',
  );
  final value = field.controller.value;
  expect(value.selection.isValid, isTrue);
  tester.testTextInput.updateEditingValue(
    value.replaced(value.selection, text),
  );
  await tester.pump();
}

void main() {
  test(
    'identical model echo preserves selection and active composition exactly',
    () {
      final c = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'ni',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      final before = c.value;
      c.syncTextFromModel('ni');
      expect(c.value, before);
      c.syncTextFromModel('old remote text');
      expect(c.value, before);
      c.dispose();
    },
  );
  test(
    'external update preserves a valid caret and clamps a reverse selection',
    () {
      final c = TextEditingController.fromValue(
        const TextEditingValue(
          text: '12345',
          selection: TextSelection(
            baseOffset: 4,
            extentOffset: 1,
            isDirectional: true,
          ),
        ),
      );
      c.syncTextFromModel('12');
      expect(
        c.selection,
        const TextSelection(
          baseOffset: 2,
          extentOffset: 1,
          isDirectional: true,
        ),
      );
      c.syncTextFromModel('');
      expect(
        c.selection,
        const TextSelection(
          baseOffset: 0,
          extentOffset: 0,
          isDirectional: true,
        ),
      );
      c.dispose();
    },
  );

  testWidgets(
    'model echoes keep 1 then 5 as 15 and support middle insertion and replace-selection',
    (tester) async {
      var model = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ModelTextField(
                key: const ValueKey('input'),
                value: model,
                onChanged: (value) => setState(() => model = value),
              ),
            ),
          ),
        ),
      );
      final finder = find.byKey(const ValueKey('input'));
      await tester.enterText(finder, '');
      final focus = editable(tester, finder).focusNode;
      await typeAtCaret(tester, finder, '1');
      await tester.pump(const Duration(seconds: 1));
      expect(
        editable(tester, finder).controller.selection,
        const TextSelection.collapsed(offset: 1),
      );
      await typeAtCaret(tester, finder, '5');
      expect(model, '15');
      expect(editable(tester, finder).focusNode, same(focus));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '15',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await typeAtCaret(tester, finder, '0');
      expect(model, '105');
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '105',
          selection: TextSelection(baseOffset: 1, extentOffset: 3),
        ),
      );
      await typeAtCaret(tester, finder, '2');
      expect(model, '12');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final files in [false, true]) {
    testWidgets(
      '${files ? 'file' : 'workspace'} search does not replace local draft with old or delayed query',
      (tester) async {
        var query = '';
        late StateSetter rebuild;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return files
                      ? MobileFilesHeader(
                          query: query,
                          searchHint: 'Search',
                          onSearch: (_) {},
                          menu: const SizedBox(),
                        )
                      : MobileWorkspaceActions(
                          query: query,
                          searchHint: 'Search',
                          onSearchChanged: (_) {},
                          actionId: 'test',
                          child: const SizedBox(),
                        );
                },
              ),
            ),
          ),
        );
        if (!files) {
          await tester.tap(find.byKey(const ValueKey('test-search-button')));
          await tester.pump();
        }
        final finder = find.byType(TextField);
        await tester.enterText(finder, '');
        await typeAtCaret(tester, finder, '1');
        rebuild(() {}); // An unrelated rebuild while the parent still has ''.
        await tester.pump();
        expect(editable(tester, finder).controller.text, '1');
        await typeAtCaret(tester, finder, '5');
        rebuild(
          () => query = '1',
        ); // A late acknowledgement of the first character.
        await tester.pump();
        expect(editable(tester, finder).controller.text, '15');
        rebuild(() => query = '15');
        await tester.pump();
        expect(
          editable(tester, finder).controller.selection,
          const TextSelection.collapsed(offset: 2),
        );
        if (files) {
          await tester.tap(find.byKey(const ValueKey('files-search-clear')));
        } else {
          await tester.tap(find.byIcon(Icons.close));
        }
        await tester.pump();
        if (files) expect(editable(tester, finder).controller.text, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
