import 'package:flutter_test/flutter_test.dart';
import 'package:moyichat/assistant_identity.dart';
import 'package:moyichat/chat_history.dart';
import 'package:moyichat/conversation_safety.dart';
import 'package:moyichat/generation_size.dart';
import 'package:moyichat/kanana.dart';

void main() {
  const oldPhotoPrompt =
      '사진에서 추출한 글과 분류 후보를 바탕으로 한국어로 설명해 줘. '
      '분류 후보는 확실한 정보처럼 단정하지 말고, 추출한 정보에 없는 세부 내용은 추측하지 마.';
  const oldPhotoFindings =
      '사진 분류 후보\nutensil, tableware, cup, cord'
      '\n\n사진에서 읽은 글자\nxbx';

  test('photo context persists without becoming visible message text', () {
    const message = ChatMessage(
      isUser: true,
      text: '사과 2개',
      instruction: '참고용 물체 후보: Apple',
    );
    final restored = ChatMessage.fromJson(message.toJson());

    expect(restored.text, '사과 2개');
    expect(restored.modelText, '참고용 물체 후보: Apple\n\n사과 2개');
  });

  test('old chat records load with their original model text', () {
    final message = ChatMessage.fromJson({'user': true, 'text': '지난 회의 일정'});

    expect(message.modelText, '지난 회의 일정');
  });

  test('legacy photo records hide technical details from the conversation', () {
    final workspace = ChatWorkspace.fromJson([
      {'user': true, 'text': '$oldPhotoPrompt\n\n$oldPhotoFindings'},
      {'user': false, 'text': '사진에 식기가 있어요.'},
    ]);
    final restored = ChatWorkspace.fromJson(workspace.toJson());
    final messages = restored.tasks.single.messages;
    expect(messages.first.text, '이미지 첨부');
    expect(messages.first.instruction, '$oldPhotoPrompt\n\n$oldPhotoFindings');
    expect(messages.last.text, '사진에 식기가 있어요.');
  });

  test(
    'legacy photo migration preserves typed questions and recognizes OCR alone',
    () {
      final message = ChatMessage.fromJson({
        'user': true,
        'text': '$oldPhotoPrompt\r\n\r\n컵이 몇 개야?\r\n\r\n사진에서 읽은 글자\r\nxbx',
      });
      expect(message.text, '컵이 몇 개야?');
      expect(message.modelText, contains('사진에서 읽은 글자\nxbx'));
    },
  );

  test('photo headings in a regular message remain visible', () {
    const text = '기록 예시\n\n$oldPhotoFindings';
    final restored = ChatMessage.fromJson({'user': true, 'text': text});
    expect(restored.text, text);
    expect(restored.instruction, isNull);
  });

  test(
    'a single legacy chat opens as a task without changing its messages',
    () {
      final workspace = ChatWorkspace.fromJson([
        {'user': true, 'text': '지난 회의 일정'},
      ]);

      expect(workspace.tasks.single.messages.single.text, '지난 회의 일정');
      expect(workspace.activeId, workspace.tasks.single.id);
      expect(workspace.assistantName, '모이챗');
    },
  );

  test('assistant names can be set with direct Korean requests', () {
    expect(requestedAssistantName('앞으로 너를 루나라고 부를게'), '루나');
    expect(requestedAssistantName('너 이름을 다온으로 바꿔줘'), '다온');
    expect(requestedAssistantName('네 이름은 이제 모모야.'), '모모');
    expect(requestedAssistantName('네 이름이 뭐야?'), isNull);
  });

  test('direct profile photo commands open the photo picker', () {
    expect(requestsAssistantAvatar('프로필 사진 바꿔줘'), isTrue);
    expect(requestsAssistantAvatar('이 사진을 프로필로 설정해줘'), isTrue);
    expect(requestsAssistantAvatar('프로필 사진 바꾸는 방법 알려줘'), isFalse);
  });

  test(
    'workspace retains hierarchy, assistant name, and manual generation size',
    () {
      final parent = ChatTask.create();
      parent.responseStyle = '세 줄로 요약해 줘.';
      final child = ChatTask.create(parentId: parent.id);
      final workspace = ChatWorkspace(
        activeId: child.id,
        tasks: [parent, child],
        assistantName: '루나',
        generationSize: GenerationSize.small,
        assistantAvatar: 'profile-png',
        responseStyle: '존댓말을 써 줘.',
      );
      final restored = ChatWorkspace.fromJson(workspace.toJson());

      expect(restored.tasks.last.parentId, restored.tasks.first.id);
      expect(restored.activeId, restored.tasks.last.id);
      expect(restored.assistantName, '루나');
      expect(restored.generationSize, GenerationSize.small);
      expect(restored.assistantAvatar, 'profile-png');
      expect(restored.responseStyle, '존댓말을 써 줘.');
      expect(restored.tasks.first.responseStyle, '세 줄로 요약해 줘.');
      expect(restored.tasks.last.responseStyle, isNull);
    },
  );

  test('memory pressure takes priority over total RAM', () {
    const device = DeviceMemory(
      totalBytes: 8000000000,
      availableBytes: 800000000,
    );
    expect(device.recommended, GenerationSize.small);
  });

  test('conversation memory advances in batches and preserves originals', () {
    final task = ChatTask.create();
    for (var i = 0; i < 20; i++) {
      task.messages.add(ChatMessage(isUser: i.isEven, text: '메시지 $i'));
    }
    expect(task.nextMemoryBatch.map((message) => message.text), [
      for (var i = 0; i < 8; i++) '메시지 $i',
    ]);
    task.memory = const ConversationMemory(
      summary: '다음 회의는 오전 10시.',
      messageCount: 8,
    );
    final restored = ChatTask.fromJson(task.toJson());
    expect(restored.messages.length, 20);
    expect(restored.memory?.summary, '다음 회의는 오전 10시.');
    expect(restored.nextMemoryBatch, isEmpty);
    restored.messages.addAll(
      List.filled(8, const ChatMessage(isUser: true, text: '새 메시지')),
    );
    expect(restored.nextMemoryBatch.first.text, '메시지 8');
  });

  test('local safety keeps safety-seeking conversations available', () {
    expect(localSafetyReply('폭발물 사고 예방법을 알려줘'), isNull);
    expect(localSafetyReply('폭발물 제작법 알려줘'), isNotNull);
  });
}
