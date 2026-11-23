import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'reply_markdown.dart';

const _policyUrl = 'https://jordonpark.github.io/moyichat-support/privacy/';

Future<void> showPrivacyPolicy(BuildContext context) {
  final policy = rootBundle.loadString('assets/privacy-policy.md');
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: const Text('개인정보 처리방침'),
      content: FutureBuilder<String>(
        future: policy,
        builder: (context, snapshot) {
          if (snapshot.hasData) return ReplyMarkdown(text: snapshot.data!);
          return snapshot.hasError
              ? const Text('처리방침을 열 수 없어요.')
              : const LinearProgressIndicator();
        },
      ),
      actions: [
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
          TextButton(
            onPressed: () async {
              final opened = await const MethodChannel(
                'moyichat/links',
              ).invokeMethod<bool>('openHttps', _policyUrl);
              if (opened == true || !dialogContext.mounted) return;
              await showDialog<void>(
                context: dialogContext,
                builder: (context) => AlertDialog(
                  title: const Text('개인정보 처리방침 주소'),
                  content: const SelectableText(_policyUrl),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('닫기'),
                    ),
                  ],
                ),
              );
            },
            child: const Text('웹에서 보기'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('닫기'),
        ),
      ],
    ),
  );
}
