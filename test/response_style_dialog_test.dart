import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:moyichat/response_style_dialog.dart';

void main() {
  testWidgets('keeps multiple selections and an existing custom instruction', (
    tester,
  ) async {
    String? saved = '글쓰기 코치처럼 답해 줘.';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showDialog<String>(
                  context: context,
                  builder: (context) =>
                      ResponseStyleDialog(initial: saved, forTask: false),
                );
              },
              child: const Text('설정 열기'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('설정 열기'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '글쓰기 코치처럼 답해 줘.',
    );
    await tester.ensureVisible(find.text('존댓말'));
    await tester.tap(find.text('존댓말'));
    await tester.ensureVisible(find.text('단계별로'));
    await tester.tap(find.text('단계별로'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();

    expect(saved, '존댓말을 써 줘.\n필요할 때 단계별로 정리해 줘.\n글쓰기 코치처럼 답해 줘.');

    await tester.tap(find.text('설정 열기'));
    await tester.pumpAndSettle();
    for (final label in ['존댓말', '단계별로', '직접 입력']) {
      final tile = find.widgetWithText(CheckboxListTile, label);
      expect(tester.widget<CheckboxListTile>(tile).value, isTrue);
    }
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '글쓰기 코치처럼 답해 줘.',
    );
  });
}
