import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:moyichat/chat_history.dart';
import 'package:moyichat/chat_photo.dart';
import 'package:moyichat/generation_size.dart';
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

  test('clearing storage removes saved records and orphaned photos', () async {
    final dir = await Directory.systemTemp.createTemp('moyichat-clear-');
    addTearDown(() => dir.delete(recursive: true));
    final history = ChatHistory(dir);
    final [savedId, orphanId] = await history.storePhotos([
      Uint8List.fromList([1]),
      Uint8List.fromList([2]),
    ]);
    final task = ChatTask.create()
      ..messages.add(
        ChatMessage(isUser: true, text: 'Private text', photoIds: [savedId]),
      );
    final pending = history.write(
      ChatWorkspace(
        activeId: task.id,
        tasks: [task],
        assistantName: 'Private name',
        assistantAvatar: 'AA==',
      ),
    );
    final cleared = history.clear(
      'new-task',
      generationSize: GenerationSize.small,
    );
    await pending;
    expect(await cleared, isTrue);

    final reopened = ChatHistory(dir);
    final workspace = (await reopened.read())!;
    expect(workspace.activeId, 'new-task');
    expect(workspace.tasks.single.messages, isEmpty);
    expect(workspace.assistantName, '모이챗');
    expect(workspace.assistantAvatar, isNull);
    expect(workspace.generationSize, GenerationSize.small);
    expect(await reopened.readPhoto(savedId), isNull);
    expect(await reopened.readPhoto(orphanId), isNull);
  });

  testWidgets('photo follows a pull and shrinks back to its thumbnail', (
    tester,
  ) async {
    final bytes = await tester.runAsync(
      () => File('assets/preview-groceries.png').readAsBytes(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: const Alignment(.75, .6),
            child: ChatPhotoThumbnail(
              photoId: 'id',
              number: 1,
              load: (_) async => bytes,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final thumbnail = find.byType(ChatPhotoThumbnail);
    await tester.tap(thumbnail);
    await tester.pumpAndSettle();
    final viewer = find.byType(InteractiveViewer);
    expect(viewer, findsOneWidget);
    expect(tester.widget<InteractiveViewer>(viewer).maxScale, 5);
    final photo = find.descendant(of: viewer, matching: find.byType(Image));
    final original = tester.getRect(photo);

    final shortPull = await tester.startGesture(original.center);
    await shortPull.moveBy(const Offset(0, 30));
    await shortPull.moveBy(const Offset(0, 24));
    await tester.pump();
    expect(tester.getRect(photo).center.dy, greaterThan(original.center.dy));
    expect(tester.getSize(photo).width, lessThan(original.width));
    await shortPull.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(photo), original);

    final dismissPull = await tester.startGesture(original.center);
    await dismissPull.moveBy(const Offset(0, 35));
    await dismissPull.moveBy(const Offset(0, 170));
    await tester.pump();
    final pulled = tester.getRect(photo);
    await dismissPull.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getSize(photo).width, lessThan(pulled.width));
    expect(tester.getRect(photo).center.dx, greaterThan(pulled.center.dx));
    await tester.pumpAndSettle();
    expect(viewer, findsNothing);
    expect(thumbnail, findsOneWidget);

    await tester.tap(thumbnail);
    await tester.pumpAndSettle();
    final first = await tester.startGesture(
      original.center - const Offset(50, 0),
    );
    final second = await tester.startGesture(
      original.center + const Offset(50, 0),
    );
    await first.moveBy(const Offset(-45, 0));
    await second.moveBy(const Offset(45, 0));
    await first.moveBy(const Offset(-35, 0));
    await second.moveBy(const Offset(35, 0));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    final controller = tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!;
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));

    final beforePan = controller.value.getTranslation().y;
    final pan = await tester.startGesture(original.center);
    await pan.moveBy(const Offset(0, 35));
    await pan.moveBy(const Offset(0, 170));
    await pan.up();
    await tester.pumpAndSettle();
    expect(viewer, findsOneWidget);
    expect(controller.value.getTranslation().y, greaterThan(beforePan));

    await tester.tap(find.byTooltip('사진 닫기'));
    await tester.pumpAndSettle();
    expect(viewer, findsNothing);
  });
}
