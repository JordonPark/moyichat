import 'package:web/web.dart';

const _key = 'moyichat.tasks.v1';
const _modelKey = 'moyichat.preview-model.v1';

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
