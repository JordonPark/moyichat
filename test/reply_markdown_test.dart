import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:moyichat/reply_markdown.dart';

Future<void> showReply(WidgetTester tester, ReplyMarkdown reply) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 280, child: reply),
          ),
        ),
      ),
    );

void main() {
  testWidgets('renders chat headings, emphasis, lists, and code', (
    tester,
  ) async {
    await showReply(
      tester,
      const ReplyMarkdown(
        text:
            '### 실행 방법\n\n'
            '**코드**를 저장하세요.\n\n'
            '- 터미널을 여세요.\n\n'
            '```python\nprint("안녕")\n```',
      ),
    );

    expect(find.text('실행 방법', findRichText: true), findsOneWidget);
    expect(find.text('코드를 저장하세요.', findRichText: true), findsOneWidget);
    expect(find.text('터미널을 여세요.', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('print("안녕")', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('```python', findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('handles an unfinished fence and keeps response images offline', (
    tester,
  ) async {
    await showReply(
      tester,
      const ReplyMarkdown(
        streaming: true,
        text:
            '![참고 그림](https://example.invalid/image.png)\n\n'
            '```python\nprint("안녕")',
      ),
    );

    expect(find.text('참고 그림', findRichText: true), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(
      find.textContaining('print("안녕")', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('```python', findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
