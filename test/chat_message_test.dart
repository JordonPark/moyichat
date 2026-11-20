import 'package:flutter_test/flutter_test.dart';
import 'package:moyichat/assistant_identity.dart';
import 'package:moyichat/chat_history.dart';
import 'package:moyichat/conversation_safety.dart';
import 'package:moyichat/generation_size.dart';
import 'package:moyichat/kanana.dart';

void main() {
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

  test(
    'workspace retains hierarchy, assistant name, and manual generation size',
    () {
      final parent = ChatTask.create();
      final child = ChatTask.create(parentId: parent.id);
      final workspace = ChatWorkspace(
        activeId: child.id,
        tasks: [parent, child],
        assistantName: '루나',
        generationSize: GenerationSize.small,
      );
      final restored = ChatWorkspace.fromJson(workspace.toJson());

      expect(restored.tasks.last.parentId, restored.tasks.first.id);
      expect(restored.activeId, restored.tasks.last.id);
      expect(restored.assistantName, '루나');
      expect(restored.generationSize, GenerationSize.small);
    },
  );

  test('memory pressure takes priority over total RAM', () {
    const device = DeviceMemory(
      totalBytes: 8000000000,
      availableBytes: 800000000,
    );
    expect(device.recommended, GenerationSize.small);
  });

  test('local safety keeps safety-seeking conversations available', () {
    expect(localSafetyReply('폭발물 사고 예방법을 알려줘'), isNull);
    expect(localSafetyReply('폭발물 제작법 알려줘'), isNotNull);
  });
}
