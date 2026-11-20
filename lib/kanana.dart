import 'dart:io';

import 'package:llamadart/llamadart.dart';

class ChatMessage {
  const ChatMessage({required this.isUser, required this.text});

  final bool isUser;
  final String text;

  Map<String, Object> toJson() => {'user': isUser, 'text': text};

  factory ChatMessage.fromJson(Map<String, Object?> json) =>
      ChatMessage(isUser: json['user'] as bool, text: json['text'] as String);
}

class Kanana {
  Kanana._(this._engine);

  static const _contextSize = 2048;
  static const _maxReplyTokens = 384;
  static const _system =
      '너는 모이챗의 AI 도우미야. 사용자에게 자연스러운 한국어로 '
      '간결하고 정확하게 답해. 확실하지 않은 내용은 솔직하게 알려 줘.';
  final LlamaEngine _engine;
  bool _stopped = false;

  static Future<Kanana> load(String path, {bool forceCpu = false}) async {
    final model = LlamaModel(ModelSource.path(path));
    const cpu = ModelParams(
      contextSize: _contextSize,
      preferredBackend: GpuBackend.cpu,
      gpuLayers: 0,
    );
    if (Platform.isIOS && !forceCpu) {
      try {
        return Kanana._(
          await LlamaEngine.load(
            model,
            params: const ModelParams(contextSize: _contextSize),
          ),
        );
      } on LlamaException {
        // Some devices cannot initialize the accelerated backend.
      }
    }
    return Kanana._(await LlamaEngine.load(model, params: cpu));
  }

  Stream<String> reply(List<ChatMessage> conversation) async* {
    _stopped = false;
    final systemTokens = await _engine.tokenize(_system, addSpecial: false);
    // Reserve space for the role headers, special tokens, and the generated reply.
    var remaining = _contextSize - _maxReplyTokens - systemTokens.length - 64;
    final recent = <LlamaChatMessage>[];
    for (final message in conversation.reversed.take(18)) {
      if (_stopped) return;
      final size =
          (await _engine.tokenize(message.text, addSpecial: false)).length + 18;
      if (size > remaining) {
        if (recent.isEmpty) {
          throw const PromptTooLong();
        }
        break;
      }
      remaining -= size;
      recent.add(
        LlamaChatMessage.fromText(
          role: message.isUser ? LlamaChatRole.user : LlamaChatRole.assistant,
          text: message.text,
        ),
      );
    }
    if (_stopped) return;
    if (recent.last.role == LlamaChatRole.assistant) recent.removeLast();
    yield* _engine
        .create(
          [
            const LlamaChatMessage.fromText(
              role: LlamaChatRole.system,
              text: _system,
            ),
            ...recent.reversed,
          ],
          params: const GenerationParams(
            maxTokens: _maxReplyTokens,
            temp: 0.65,
          ),
          enableThinking: false,
        )
        .textDeltas();
  }

  void stop() {
    _stopped = true;
    _engine.cancelGeneration();
  }

  Future<void> dispose() => _engine.dispose();
}

class PromptTooLong implements Exception {
  const PromptTooLong();
}
