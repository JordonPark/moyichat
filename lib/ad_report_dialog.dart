import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

const _supportEmail = 'moyichats@gmail.com';
const _subject = '모이챗 광고 신고';

Future<void> showAdReportDialog(
  BuildContext context, {
  required String adUnitId,
  required String? responseId,
}) {
  final report = [
    '문제가 된 광고와 신고 이유를 적어 주세요.',
    '',
    '광고 단위 ID: $adUnitId',
    if (responseId != null) '광고 응답 ID: $responseId',
    '신고 시간(UTC): ${DateTime.now().toUtc().toIso8601String()}',
  ].join('\n');
  final canCompose = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  var feedback = '';
  return showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('광고 정보 및 신고'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '이 배너는 Google AdMob의 비개인화 광고예요. 현재 앱과 대략적인 지역 같은 정보가 광고 선택에 사용될 수 있어요. 배너의 광고 옵션에서 Google의 안내를 확인할 수 있어요.',
            ),
            const SizedBox(height: 12),
            const Text('부적절한 광고는 광고 식별 정보와 함께 지원팀에 신고할 수 있어요.'),
            const SelectableText(_supportEmail),
            if (feedback.isNotEmpty)
              Semantics(liveRegion: true, child: Text(feedback)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              if (context.mounted) update(() => feedback = '광고 신고 정보를 복사했어요.');
            },
            child: const Text('신고 정보 복사'),
          ),
          if (canCompose)
            FilledButton(
              onPressed: () async {
                final url =
                    'mailto:$_supportEmail?'
                    'subject=${Uri.encodeComponent(_subject)}&'
                    'body=${Uri.encodeComponent(report)}';
                final opened = await const MethodChannel(
                  'moyichat/links',
                ).invokeMethod<bool>('openSupportMail', url);
                if (opened != true && context.mounted) {
                  update(() => feedback = '메일을 열 수 없어요. 신고 정보를 복사해 보내 주세요.');
                }
              },
              child: const Text('이메일 작성'),
            ),
        ],
      ),
    ),
  );
}
