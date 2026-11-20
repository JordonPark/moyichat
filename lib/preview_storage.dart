import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

const _key = 'moyichat.tasks.v1';
const _modelKey = 'moyichat.preview-model.v1';
const _photoStore = 'photos';

String? readPreviewHistory() => window.localStorage.getItem(_key);

void writePreviewHistory(String snapshot) =>
    window.localStorage.setItem(_key, snapshot);

bool previewModelReady() => window.localStorage.getItem(_modelKey) == 'ready';

void setPreviewModelReady(bool ready) {
  if (ready) {
    window.localStorage.setItem(_modelKey, 'ready');
  } else {
    window.localStorage.removeItem(_modelKey);
  }
}

Future<IDBDatabase> _openPhotos() {
  final request = window.indexedDB.open('moyichat-chat-media', 1);
  final opened = Completer<IDBDatabase>();
  request.onupgradeneeded = ((Event _) {
    (request.result as IDBDatabase).createObjectStore(_photoStore);
  }).toJS;
  request.onsuccess = ((Event _) {
    opened.complete(request.result as IDBDatabase);
  }).toJS;
  request.onerror = ((Event _) {
    opened.completeError(StateError('Unable to open chat photo storage.'));
  }).toJS;
  return opened.future;
}

Future<JSAny?> _photoOperation(
  IDBRequest Function(IDBObjectStore) operation, {
  bool write = false,
}) async {
  final database = await _openPhotos();
  try {
    final transaction = database.transaction(
      _photoStore.toJS,
      write ? 'readwrite' : 'readonly',
    );
    final request = operation(transaction.objectStore(_photoStore));
    final finished = Completer<JSAny?>();
    transaction.oncomplete = ((Event _) {
      finished.complete(request.result);
    }).toJS;
    transaction.onabort = ((Event _) {
      finished.completeError(StateError('Chat photo storage failed.'));
    }).toJS;
    return await finished.future;
  } finally {
    database.close();
  }
}

Future<void> writePreviewPhoto(String id, Uint8List bytes) async {
  await _photoOperation((store) => store.put(bytes.toJS, id.toJS), write: true);
}

Future<Uint8List?> readPreviewPhoto(String id) async =>
    (await _photoOperation((store) => store.get(id.toJS)) as JSUint8Array?)
        ?.toDart;

Future<void> deletePreviewPhoto(String id) async {
  await _photoOperation((store) => store.delete(id.toJS), write: true);
}
