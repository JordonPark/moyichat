import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

class ModelStore {
  ModelStore(this.directory, {this.source = kananaUrl});

  static const fileName = 'kanana-1.5-2.1b-instruct-2505-q4_k_m.gguf';
  static const bytes = 1522796736;
  static const digest =
      '62a63f912a0708d9a522f974997b5bbd4927e01d739b07fe4c55c1f545241561';
  static const kananaUrl =
      'https://huggingface.co/TaeyoungLeeJack/'
      'kanana-1.5-2.1b-instruct-2505-Q4_K_M-GGUF/resolve/'
      '9a6c4bf9e13fea91c3100a891e7312dd9911f098/$fileName';

  final Directory directory;
  final String source;
  HttpClient? _client;
  bool _paused = false;
  bool _busy = false;
  bool _verifying = false;

  File get model => File.fromUri(directory.uri.resolve(fileName));
  File get _partial => File('${model.path}.part');
  File get _consent => File('${model.path}.consent');
  String get _consentVersion => 'model-download-v1:$digest';

  Future<bool> hasDownloadConsent() async =>
      await _consent.exists() &&
      await _consent.readAsString() == _consentVersion;

  Future<void> acceptDownload() async {
    final temporary = File('${_consent.path}.tmp');
    await temporary.writeAsString(_consentVersion, flush: true);
    await temporary.rename(_consent.path);
  }

  Future<bool> isInstalled() async =>
      await model.exists() && await model.length() == bytes;

  Future<int> partialBytes() async =>
      await _partial.exists() ? await _partial.length() : 0;

  void pause() {
    if (!_busy || _verifying) return;
    _paused = true;
    _client?.close(force: true);
  }

  /// Returns false when paused. Only a verified file gets the final name.
  Future<bool> download({
    required void Function(int) onProgress,
    required void Function() onVerify,
  }) async {
    if (_busy) throw StateError('A model download is already active.');
    _busy = true;
    _paused = false;
    try {
      await directory.create(recursive: true);
      var offset = await partialBytes();
      if (offset > bytes) {
        await _partial.delete();
        offset = 0;
      }
      if (offset < bytes && !_paused) {
        await _transfer(offset, onProgress);
      }
      if (_paused) return false;
      if (await partialBytes() != bytes) {
        throw const ModelDownloadException('다운로드가 끊겼어요. 이어받기를 눌러 주세요.');
      }
      _verifying = true;
      onVerify();
      final path = _partial.path;
      final checksum = await _fileChecksum(path);
      if (checksum.toString() != digest) {
        await _partial.delete();
        throw const ModelDownloadException('모델 파일 확인에 실패했어요. 다시 받아 주세요.');
      }
      await _partial.rename(model.path);
      return true;
    } on Exception {
      if (_paused) return false;
      rethrow;
    } finally {
      _client?.close(force: true);
      _client = null;
      _busy = false;
      _verifying = false;
    }
  }

  Future<void> _transfer(int offset, void Function(int) onProgress) async {
    const timeout = Duration(seconds: 30);
    final client = _client = HttpClient()..connectionTimeout = timeout;
    final request = await client.getUrl(Uri.parse(source));
    if (offset > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
    }
    final response = await request.close().timeout(timeout);
    if (response.statusCode == HttpStatus.ok) {
      offset = 0;
    } else if (response.statusCode == HttpStatus.partialContent) {
      final range = response.headers.value(HttpHeaders.contentRangeHeader);
      if (range != 'bytes $offset-${bytes - 1}/$bytes') {
        throw const ModelDownloadException('이어받기 응답을 확인할 수 없어요.');
      }
    } else {
      throw ModelDownloadException('모델을 받을 수 없어요. HTTP ${response.statusCode}');
    }
    if (response.contentLength != -1 &&
        response.contentLength != bytes - offset) {
      throw const ModelDownloadException('다운로드 파일의 크기가 예상과 달라요.');
    }
    if (_paused) return;

    final output = await _partial.open(
      mode: offset == 0 ? FileMode.write : FileMode.append,
    );
    var received = offset;
    onProgress(received);
    final update = Stopwatch()..start();
    try {
      await for (final chunk in response.timeout(timeout)) {
        if (_paused) break;
        if (received + chunk.length > bytes) {
          throw const ModelDownloadException('다운로드 파일의 크기가 예상과 달라요.');
        }
        await output.writeFrom(chunk);
        received += chunk.length;
        if (update.elapsedMilliseconds >= 150) {
          onProgress(received);
          update.reset();
        }
      }
    } finally {
      await output.close();
      onProgress(received);
    }
  }
}

Future<Digest> _fileChecksum(String path) =>
    Isolate.run(() => sha256.bind(File(path).openRead()).first);

class ModelDownloadException implements Exception {
  const ModelDownloadException(this.message);
  final String message;
}
