import 'dart:convert';
import 'dart:io';

import 'assistant_identity.dart';
import 'generation_size.dart';
import 'kanana.dart';
import 'preview_storage_stub.dart'
    if (dart.library.js_interop) 'preview_storage.dart';

class ChatTask {
  ChatTask({
    required this.id,
    required this.messages,
    this.name,
    this.parentId,
  });

  factory ChatTask.create({String? parentId}) => ChatTask(
    id: '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
    messages: [],
    parentId: parentId,
  );

  static int _sequence = 0;
  final String id;
  final List<ChatMessage> messages;
  final String? parentId;
  String? name;

  String get title =>
      name ??
      (messages.isEmpty
          ? parentId == null
                ? '새 작업'
                : '하위 작업'
          : messages.first.text.split('\n').first);

  Map<String, Object> toJson() => {
    'id': id,
    'messages': messages.map((message) => message.toJson()).toList(),
    'name': ?name,
    'parentId': ?parentId,
  };

  factory ChatTask.fromJson(Map<String, Object?> value) => ChatTask(
    id: value['id'] as String,
    messages: _decodeMessages(value['messages'] as List<dynamic>),
    name: value['name'] as String?,
    parentId: value['parentId'] as String?,
  );
}

class ChatWorkspace {
  const ChatWorkspace({
    required this.activeId,
    required this.tasks,
    this.assistantName = defaultAssistantName,
    this.generationSize,
  });

  final String activeId;
  final List<ChatTask> tasks;
  final String assistantName;
  final GenerationSize? generationSize;

  Map<String, Object> toJson() => {
    'activeId': activeId,
    'tasks': tasks.map((task) => task.toJson()).toList(),
    'assistantName': assistantName,
    'generationSize': ?generationSize?.name,
  };

  factory ChatWorkspace.fromJson(Object? value) {
    if (value is List<dynamic>) {
      final task = ChatTask(
        id: 'previous-chat',
        messages: _decodeMessages(value),
      );
      return ChatWorkspace(activeId: task.id, tasks: [task]);
    }
    final data = value as Map<String, Object?>;
    return ChatWorkspace(
      activeId: data['activeId'] as String,
      assistantName: data['assistantName'] as String? ?? defaultAssistantName,
      generationSize: GenerationSize.values
          .where((size) => size.name == data['generationSize'])
          .firstOrNull,
      tasks: (data['tasks'] as List<dynamic>)
          .map((task) => ChatTask.fromJson(task as Map<String, Object?>))
          .toList(),
    );
  }
}

List<ChatMessage> _decodeMessages(List<dynamic> values) => values
    .map((value) => ChatMessage.fromJson(value as Map<String, Object?>))
    .toList();

class ChatHistory {
  ChatHistory(Directory directory)
    : _file = File.fromUri(directory.uri.resolve('chat.json'));

  ChatHistory.preview() : _file = null;

  final File? _file;
  Future<void> _pendingWrite = Future<void>.value();

  Future<ChatWorkspace?> read() async {
    final file = _file;
    final contents = file == null
        ? readPreviewHistory()
        : await file.exists()
        ? await file.readAsString()
        : null;
    return contents == null
        ? null
        : ChatWorkspace.fromJson(jsonDecode(contents));
  }

  Future<void> write(ChatWorkspace workspace) {
    final snapshot = jsonEncode(workspace.toJson());
    final next = _pendingWrite.then((_) => _writeSnapshot(snapshot));
    _pendingWrite = next.onError((_, _) {});
    return next;
  }

  Future<void> _writeSnapshot(String snapshot) async {
    final file = _file;
    if (file == null) {
      writePreviewHistory(snapshot);
      return;
    }
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(snapshot, flush: true);
    await temporary.rename(file.path);
  }
}
