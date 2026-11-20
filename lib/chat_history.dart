import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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
    this.responseStyle,
    this.memory,
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
  String? responseStyle;
  ConversationMemory? memory;

  List<ChatMessage> get nextMemoryBatch {
    const batchSize = 8;
    const recentMessages = 12;
    final start = memory?.messageCount ?? 0;
    if (messages.length - start < batchSize + recentMessages) return const [];
    return messages.sublist(start, start + batchSize);
  }

  String get title =>
      name ??
      (messages.isEmpty
          ? parentId == null
                ? '새 작업'
                : '하위 대화'
          : messages.first.displayText.split('\n').first);

  Map<String, Object> toJson() => {
    'id': id,
    'messages': messages.map((message) => message.toJson()).toList(),
    'name': ?name,
    'parentId': ?parentId,
    'responseStyle': ?responseStyle,
    'memory': ?memory?.toJson(),
  };

  factory ChatTask.fromJson(Map<String, Object?> value) => ChatTask(
    id: value['id'] as String,
    messages: _decodeMessages(value['messages'] as List<dynamic>),
    name: value['name'] as String?,
    parentId: value['parentId'] as String?,
    responseStyle: value['responseStyle'] as String?,
    memory: ConversationMemory.fromJson(value['memory']),
  );
}

class ConversationMemory {
  const ConversationMemory({required this.summary, required this.messageCount});

  final String summary;
  final int messageCount;

  Map<String, Object> toJson() => {
    'summary': summary,
    'messageCount': messageCount,
  };

  static ConversationMemory? fromJson(Object? value) => switch (value) {
    {'summary': final String summary, 'messageCount': final int count}
        when summary.isNotEmpty && count > 0 =>
      ConversationMemory(summary: summary, messageCount: count),
    _ => null,
  };
}

class ChatWorkspace {
  const ChatWorkspace({
    required this.activeId,
    required this.tasks,
    this.assistantName = defaultAssistantName,
    this.generationSize,
    this.assistantAvatar,
    this.responseStyle,
  });

  final String activeId;
  final List<ChatTask> tasks;
  final String assistantName;
  final GenerationSize? generationSize;
  final String? assistantAvatar;
  final String? responseStyle;

  Map<String, Object> toJson() => {
    'activeId': activeId,
    'tasks': tasks.map((task) => task.toJson()).toList(),
    'assistantName': assistantName,
    'generationSize': ?generationSize?.name,
    'assistantAvatar': ?assistantAvatar,
    'responseStyle': ?responseStyle,
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
      assistantAvatar: data['assistantAvatar'] as String?,
      responseStyle: data['responseStyle'] as String?,
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
  static final _random = Random.secure();
  static final _photoIdPattern = RegExp(r'^[a-f0-9]{32}$');
  Set<String> _savedPhotoIds = {};
  Future<void> _pendingWrite = Future<void>.value();

  Future<ChatWorkspace?> read() async {
    final file = _file;
    final contents = file == null
        ? readPreviewHistory()
        : await file.exists()
        ? await file.readAsString()
        : null;
    if (contents == null) return null;
    final workspace = ChatWorkspace.fromJson(jsonDecode(contents));
    _savedPhotoIds = _photoIds(workspace);
    return workspace;
  }

  Future<void> write(ChatWorkspace workspace) {
    final snapshot = jsonEncode(workspace.toJson());
    final photoIds = _photoIds(workspace);
    final next = _pendingWrite.then((_) async {
      await _writeSnapshot(snapshot);
      final removed = _savedPhotoIds.difference(photoIds);
      _savedPhotoIds = photoIds;
      await discardPhotos(removed);
    });
    _pendingWrite = next.onError((_, _) {});
    return next;
  }

  Future<List<String>> storePhotos(Iterable<Uint8List> photos) async {
    final ids = <String>[];
    try {
      for (final bytes in photos) {
        final id = List.generate(
          16,
          (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        ids.add(id);
        final file = _photoFile(id);
        if (file == null) {
          await writePreviewPhoto(id, bytes);
        } else {
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes, flush: true);
        }
      }
      return ids;
    } catch (_) {
      await discardPhotos(ids);
      rethrow;
    }
  }

  Future<Uint8List?> readPhoto(String id) async {
    if (!_photoIdPattern.hasMatch(id)) return null;
    final file = _photoFile(id);
    if (file == null) return readPreviewPhoto(id);
    return await file.exists() ? file.readAsBytes() : null;
  }

  Future<void> discardPhotos(Iterable<String> ids) async {
    for (final id in ids.where(_photoIdPattern.hasMatch)) {
      try {
        final file = _photoFile(id);
        if (file == null) {
          await deletePreviewPhoto(id);
        } else if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // A cleanup failure must not invalidate an already saved conversation.
      }
    }
  }

  File? _photoFile(String id) {
    final directory = _file?.parent;
    return directory == null
        ? null
        : File.fromUri(directory.uri.resolve('chat-photos/$id'));
  }

  Set<String> _photoIds(ChatWorkspace workspace) => {
    for (final task in workspace.tasks)
      for (final message in task.messages) ...message.photoIds,
  };

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
