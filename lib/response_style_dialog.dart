import 'package:material_ui/material_ui.dart';

enum _ResponseOption {
  polite('존댓말', '존댓말을 써 줘.'),
  concise('짧고 간결하게', '짧고 간결하게 답해 줘.'),
  summaryFirst('핵심부터', '핵심을 먼저 말해 줘.'),
  plainLanguage('쉬운 말로', '쉬운 말로 설명해 줘.'),
  steps('단계별로', '필요할 때 단계별로 정리해 줘.');

  const _ResponseOption(this.label, this.instruction);

  final String label;
  final String instruction;
}

class ResponseStyleDialog extends StatefulWidget {
  const ResponseStyleDialog({
    super.key,
    required this.initial,
    required this.forTask,
  });

  final String? initial;
  final bool forTask;

  @override
  State<ResponseStyleDialog> createState() => _ResponseStyleDialogState();
}

class _ResponseStyleDialogState extends State<ResponseStyleDialog> {
  late final Set<_ResponseOption> _selected;

  @override
  void initState() {
    super.initState();
    final lines = (widget.initial ?? '').split('\n');
    _selected = {
      for (final option in _ResponseOption.values)
        if (lines.contains(option.instruction)) option,
    };
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.all(24),
      scrollable: true,
      title: Text(widget.forTask ? '이 작업의 답변 방식' : '내 AI의 답변 방식'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.forTask)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('비워 두면 상위 작업이나 내 AI의 기본 방식을 따라요.'),
            ),
          for (final option in _ResponseOption.values)
            CheckboxListTile(
              title: Text(option.label),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _selected.contains(option),
              onChanged: (checked) => setState(() {
                if (checked == true) {
                  _selected.add(option);
                } else {
                  _selected.remove(option);
                }
              }),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            final instructions = [
              for (final option in _ResponseOption.values)
                if (_selected.contains(option)) option.instruction,
            ];
            Navigator.pop(context, instructions.join('\n'));
          },
          child: const Text('적용'),
        ),
      ],
    );
  }
}
