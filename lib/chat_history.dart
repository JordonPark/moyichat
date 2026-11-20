import 'dart:convert';
import 'dart:io';

import 'kanana.dart';

class ChatHistory {
  ChatHistory(Directory directory)
    : _file = File.fromUri(directory.uri.resolve('chat.json'));

  final File _file;
  Future<void> _pendingWrite = Future<void>.value();

  Future<List<ChatMessage>> read() async {
    if (!await _file.exists()) return [];
    final values = jsonDecode(await _file.readAsString()) as List<dynamic>;
    return values
        .map((value) => ChatMessage.fromJson(value as Map<String, Object?>))
        .toList();
  }

  Future<void> write(List<ChatMessage> messages) {
    final snapshot = jsonEncode(
      messages.map((message) => message.toJson()).toList(),
    );
    final next = _pendingWrite.then((_) => _writeSnapshot(snapshot));
    _pendingWrite = next.onError((_, _) {});
    return next;
  }

  Future<void> _writeSnapshot(String snapshot) async {
    await _file.parent.create(recursive: true);
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(snapshot, flush: true);
    await temporary.rename(_file.path);
  }
}
