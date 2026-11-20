import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:moyichat/response_style_dialog.dart';

void main() {
  testWidgets('applies only selected presets and restores their checkboxes', (
    tester,
  ) async {
    const legacy = '존댓말을 써 줘.\n도움이 되는 예시를 덧붙여 줘.\n글쓰기 코치처럼 답해 줘.';
    var saved = legacy;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await showDialog<String>(
                  context: context,
                  builder: (context) =>
                      ResponseStyleDialog(initial: saved, forTask: false),
                );
                if (result != null) saved = result;
              },
              child: const Text('설정 열기'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('설정 열기'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(5));
    expect(find.text('예시 포함'), findsNothing);
    expect(find.text('직접 입력'), findsNothing);
    expect(find.byType(EditableText), findsNothing);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(saved, legacy);

    await tester.tap(find.text('설정 열기'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('단계별로'));
    await tester.tap(find.text('단계별로'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();

    expect(saved, '존댓말을 써 줘.\n필요할 때 단계별로 정리해 줘.');

    await tester.tap(find.text('설정 열기'));
    await tester.pumpAndSettle();
    for (final label in ['존댓말', '단계별로']) {
      final tile = find.widgetWithText(CheckboxListTile, label);
      expect(tester.widget<CheckboxListTile>(tile).value, isTrue);
    }
  });
}
