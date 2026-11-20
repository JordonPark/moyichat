import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:moyichat/chat_history.dart';
import 'package:moyichat/chat_photo.dart';
import 'package:moyichat/kanana.dart';

void main() {
  test(
    'photo files survive reopening and are removed with their messages',
    () async {
      final dir = await Directory.systemTemp.createTemp('moyichat-chat-photo-');
      addTearDown(() => dir.delete(recursive: true));
      final history = ChatHistory(dir);
      final bytes = Uint8List.fromList([1, 2, 3]);
      final ids = await history.storePhotos([
        bytes,
        Uint8List.fromList([4]),
      ]);
      final task = ChatTask.create()
        ..messages.add(ChatMessage(isUser: true, text: '', photoIds: ids));

      await history.write(ChatWorkspace(activeId: task.id, tasks: [task]));
      final reopened = ChatHistory(dir);
      final workspace = (await reopened.read())!;
      final message = workspace.tasks.single.messages.single;
      expect(message.photoIds, ids);
      expect(message.modelText, '이미지 첨부');
      expect(await reopened.readPhoto(ids.first), bytes);
      expect(await reopened.readPhoto('../chat.json'), isNull);

      await reopened.write(const ChatWorkspace(activeId: '', tasks: []));
      expect(await reopened.readPhoto(ids.first), isNull);
      expect(await reopened.readPhoto(ids.last), isNull);
    },
  );

  testWidgets('tapping a photo opens a zoomable viewer', (tester) async {
    final bytes = await tester.runAsync(
      () => File('assets/preview-groceries.png').readAsBytes(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatPhotoThumbnail(
            photoId: 'id',
            number: 1,
            load: (_) async => bytes,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ChatPhotoThumbnail));
    await tester.pumpAndSettle();
    final viewer = find.byType(InteractiveViewer);
    expect(viewer, findsOneWidget);
    expect(tester.widget<InteractiveViewer>(viewer).maxScale, 5);

    await tester.tap(find.byTooltip('사진 닫기'));
    await tester.pumpAndSettle();
    expect(viewer, findsNothing);
  });
}
