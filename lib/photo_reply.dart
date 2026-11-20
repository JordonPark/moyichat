const photoReplyGuidance =
    '사진 자료는 기기에서 읽은 글자와 물체 단서야. 현재 질문에 필요한 답부터 일상적인 한국어로 말해. '
    '짧게 답할 수 있으면 한두 문장으로 답하고, 항목이 여러 개일 때 목록을 써. '
    '앱 이름, 수량과 상태는 화면에 나온 뜻 그대로 전해. 대화 캡처에서는 실제로 나온 결정과 할 일만 골라. '
    '물체 단서는 질문에 필요할 때만 참고하고, 분류 이름이나 인식 과정은 답변에서 빼. '
    '애매한 내용은 짧게 밝히고, 인사말과 관례적인 맺음말은 생략해.';

const _candidateHeadings = [
  '참고용 물체 후보',
  '참고용 분류 후보',
  '물체 후보',
  '사진 분류 후보',
  '분류 후보',
];

final _lineFormatting = RegExp(r'^(?:#{1,6}\s+|[-+*•]\s+|\d+[.)]\s+)');
final _candidateLine = RegExp(
  '^(?:${_candidateHeadings.join('|')})(?:\\s*[:：]\\s*(.*))?\$',
);
final _candidateContinuation = RegExp(r'^[a-zA-Z][a-zA-Z0-9_, /-]*$');
final _genericHeading = RegExp(r'^확인한 정보\s*[:：]?$');
final _genericEnding = RegExp(
  r'(?:^|\s)(?:(?:추가 정보가 필요하면|추가 정보나 세부 사항이 필요하면|더 궁금한 점이 있으면)\s*'
  r'말씀해\s*주세요[.!]?\s*|'
  r'확인할 수 있는 내용이 더 없으면 위와 같이 정리합니다[.!]?\s*)+$',
);

String cleanPhotoReply(String text, {bool streaming = false}) {
  final lines = text.split('\n');
  final kept = <String>[];
  var afterCandidates = false;
  for (final (index, line) in lines.indexed) {
    final content = line
        .trim()
        .replaceFirst(_lineFormatting, '')
        .replaceAll('**', '');
    final candidate = _candidateLine.firstMatch(content);
    if (candidate != null) {
      final value = candidate.group(1) ?? '';
      afterCandidates = value.isEmpty || value.endsWith(',');
      continue;
    }
    if (afterCandidates &&
        (content.isEmpty || _candidateContinuation.hasMatch(content))) {
      continue;
    }
    afterCandidates = false;
    if (_genericHeading.hasMatch(content)) continue;
    if (streaming &&
        index == lines.length - 1 &&
        _candidateHeadings.any((heading) => heading.startsWith(content))) {
      continue;
    }
    final cleaned = line.replaceAll(_genericEnding, '');
    if (cleaned.isEmpty && line.isNotEmpty) continue;
    kept.add(cleaned);
  }
  return kept.join('\n').trimLeft();
}
