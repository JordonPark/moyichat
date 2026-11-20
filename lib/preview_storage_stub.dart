import 'dart:typed_data';

String? readPreviewHistory() => throw UnsupportedError('Browser storage only');

void writePreviewHistory(String snapshot) =>
    throw UnsupportedError('Browser storage only');

bool previewModelReady() => throw UnsupportedError('Browser storage only');

void setPreviewModelReady(bool ready) =>
    throw UnsupportedError('Browser storage only');

Future<void> writePreviewPhoto(String id, Uint8List bytes) =>
    throw UnsupportedError('Browser storage only');

Future<Uint8List?> readPreviewPhoto(String id) =>
    throw UnsupportedError('Browser storage only');

Future<void> deletePreviewPhoto(String id) =>
    throw UnsupportedError('Browser storage only');
