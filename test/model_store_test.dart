import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moyichat/model_store.dart';

void main() {
  late Directory directory;
  late HttpServer server;
  late ModelStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('moyichat-download-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    store = ModelStore(directory, source: 'http://127.0.0.1:${server.port}');
  });

  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('resumes an interrupted download at the saved byte offset', () async {
    final partial = File('${store.model.path}.part');
    await partial.writeAsBytes([1, 2, 3]);
    String? range;
    server.listen((request) async {
      range = request.headers.value(HttpHeaders.rangeHeader);
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 3-${ModelStore.bytes - 1}/${ModelStore.bytes}',
        )
        ..add([4, 5]);
      await request.response.close();
    });

    await expectLater(
      store.download(
        onProgress: (_) {},
        onVerify: () => fail('Incomplete model'),
      ),
      throwsA(isA<ModelDownloadException>()),
    );
    expect(range, 'bytes=3-');
    expect(await partial.readAsBytes(), [1, 2, 3, 4, 5]);
    expect(await store.isInstalled(), isFalse);
  });

  test(
    'a full response replaces an old partial file when Range is ignored',
    () async {
      final partial = File('${store.model.path}.part');
      await partial.writeAsBytes([9, 9]);
      server.listen((request) async {
        request.response.add([1, 2, 3]);
        await request.response.close();
      });

      await expectLater(
        store.download(
          onProgress: (_) {},
          onVerify: () => fail('Incomplete model'),
        ),
        throwsA(isA<ModelDownloadException>()),
      );
      expect(await partial.readAsBytes(), [1, 2, 3]);
    },
  );
}
