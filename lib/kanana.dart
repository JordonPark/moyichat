import 'dart:io';

import 'package:llamadart/llamadart.dart';

import 'assistant_identity.dart';
import 'conversation_safety.dart';
import 'generation_size.dart';

class ChatMessage {
  const ChatMessage({
    required this.isUser,
    required this.text,
    this.instruction,
  });

  final bool isUser;
  final String text;
  final String? instruction;

  String get modelText => instruction == null ? text : '$instruction\n\n$text';

  Map<String, Object> toJson() => {
    'user': isUser,
    'text': text,
    'instruction': ?instruction,
  };

  factory ChatMessage.fromJson(Map<String, Object?> json) => ChatMessage(
    isUser: json['user'] as bool,
    text: json['text'] as String,
    instruction: json['instruction'] as String?,
  );
}

class Kanana {
  Kanana._(this._engine, this.size);

  final LlamaEngine _engine;
  final GenerationSize size;
  bool _stopped = false;

  static Future<Kanana> load(
    String path, {
    bool forceCpu = false,
    GenerationSize size = GenerationSize.normal,
  }) async {
    final model = LlamaModel(ModelSource.path(path));
    final cpu = ModelParams(
      contextSize: size.context,
      preferredBackend: GpuBackend.cpu,
      gpuLayers: 0,
    );
    if (Platform.isIOS && !forceCpu) {
      try {
        return Kanana._(
          await LlamaEngine.load(
            model,
            params: ModelParams(contextSize: size.context),
          ),
          size,
        );
      } on LlamaException {
        // Some devices cannot initialize the accelerated backend.
      }
    }
    return Kanana._(await LlamaEngine.load(model, params: cpu), size);
  }

  Stream<String> reply(
    List<ChatMessage> conversation, {
    String assistantName = defaultAssistantName,
    List<ChatMessage> parentConversation = const [],
  }) async* {
    _stopped = false;
    final parent = await _parentExcerpt(parentConversation);
    if (_stopped) return;
    final system =
        '너는 모이챗 앱의 AI 도우미야. 사용자가 부르는 이름은 “$assistantName”이야. '
        '자연스러운 한국어로 간결하고 정확하게 답해. 확실하지 않은 내용은 솔직하게 알려 줘.'
        '\n$systemSafetyGuidance'
        '$parent';
    final systemTokens = await _engine.tokenize(system, addSpecial: false);
    // Reserve space for the role headers, special tokens, and the generated reply.
    var remaining = size.context - size.reply - systemTokens.length - 64;
    final recent = <LlamaChatMessage>[];
    for (final message in conversation.reversed.take(18)) {
      if (_stopped) return;
      final text = message.modelText;
      final tokens = (await _engine.tokenize(text, addSpecial: false)).length;
      if (recent.isEmpty && tokens > size.prompt) {
        throw PromptTooLong(size.prompt);
      }
      final turnSize = tokens + 18;
      if (turnSize > remaining) {
        if (recent.isEmpty) {
          throw PromptTooLong(remaining - 18);
        }
        break;
      }
      remaining -= turnSize;
      recent.add(
        LlamaChatMessage.fromText(
          role: message.isUser ? LlamaChatRole.user : LlamaChatRole.assistant,
          text: text,
        ),
      );
    }
    if (_stopped || recent.isEmpty) return;
    if (recent.last.role == LlamaChatRole.assistant) recent.removeLast();
    yield* _engine
        .create(
          [
            LlamaChatMessage.fromText(role: LlamaChatRole.system, text: system),
            ...recent.reversed,
          ],
          params: GenerationParams(maxTokens: size.reply, temp: 0.65),
          enableThinking: false,
        )
        .textDeltas();
  }

  Future<String> _parentExcerpt(List<ChatMessage> conversation) async {
    var budget = 320;
    final notes = <String>[];
    for (final message in conversation.reversed.take(6)) {
      if (_stopped || budget <= 0) break;
      final tokens = await _engine.tokenize(message.text, addSpecial: false);
      final text = tokens.length <= budget
          ? message.text
          : await _engine.detokenize(tokens.take(budget).toList());
      notes.add('${message.isUser ? '사용자' : '도우미'}: $text');
      budget -= tokens.length + 8;
    }
    if (notes.isEmpty) return '';
    return '\n상위 작업의 최근 대화는 배경 자료야. 현재 질문에 관련 있는 내용만 활용해.\n'
        '${notes.reversed.join('\n')}\n상위 작업 참고 자료 끝.';
  }

  void stop() {
    _stopped = true;
    _engine.cancelGeneration();
  }

  Future<void> dispose() => _engine.dispose();
}

class PromptTooLong implements Exception {
  const PromptTooLong(this.limit);

  final int limit;
}
