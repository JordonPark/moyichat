import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moyichat/photo_analysis.dart';
import 'package:moyichat/photo_reply.dart';

void main() {
  test('keeps OCR and useful object clues without generic screen labels', () {
    const findings = PhotoFindings(
      text: '말씀알림\n89일 남음 · 0.1.0 (1)',
      labels: [' Document ', 'screen_shot', 'cup', 'cup'],
    );
    expect(jsonDecode(findings.modelContext), {
      'text': '말씀알림\n89일 남음 · 0.1.0 (1)',
      'objects': ['cup'],
    });
    expect(
      const PhotoFindings(text: null, labels: ['cup']).modelContext,
      '{"objects":["cup"]}',
    );
    expect(const PhotoFindings(text: ' ', labels: []).modelContext, isEmpty);
  });

  test('omits internal photo labels and keeps the answer and quoted text', () {
    const answer =
        '### 확인한 정보:\n\n'
        '말씀알림 0.1.0 (1)을 설치할 수 있고, 테스트 기간은 89일 남았어요.\n\n'
        '- **참고용 물체 후보:** document,\n'
        '  screenshot\n\n'
        '추가 정보나 세부 사항이 필요하면 말씀해 주세요. '
        '확인할 수 있는 내용이 더 없으면 위와 같이 정리합니다.';
    expect(
      cleanPhotoReply(answer).trim(),
      '말씀알림 0.1.0 (1)을 설치할 수 있고, 테스트 기간은 89일 남았어요.',
    );
    expect(
      cleanPhotoReply('안내 문구는 “더 궁금한 점이 있으면 말씀해 주세요.”예요.'),
      '안내 문구는 “더 궁금한 점이 있으면 말씀해 주세요.”예요.',
    );
  });

  test('keeps streaming the answer while hiding a partial metadata line', () {
    expect(
      cleanPhotoReply('사과가 보여요.\n- 참고용 물체 후', streaming: true),
      '사과가 보여요.',
    );
    expect(cleanPhotoReply('사과가 두 개 보', streaming: true), '사과가 두 개 보');
  });
}
