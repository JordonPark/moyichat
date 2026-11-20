import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:material_ui/material_ui.dart';

class ReplyMarkdown extends StatelessWidget {
  const ReplyMarkdown({super.key, required this.text, this.streaming = false});

  final String text;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final body = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontSize: 15,
      height: 1.58,
    );
    final heading = body.copyWith(fontWeight: FontWeight.w800, height: 1.35);
    return MarkdownBody(
      data: text,
      selectable: !streaming,
      softLineBreak: true,
      styleSheet: MarkdownStyleSheet(
        p: body,
        h1: heading.copyWith(fontSize: 21),
        h2: heading.copyWith(fontSize: 18),
        h3: heading.copyWith(fontSize: 16),
        h4: heading,
        blockSpacing: 10,
        listIndent: 20,
        code: body.copyWith(fontFamily: 'monospace', fontSize: 13),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: colors.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.outlineVariant),
        ),
      ),
      // Model-generated images must not make network or file requests.
      imageBuilder: (_, _, alt) => Text(alt ?? '', style: body),
    );
  }
}
