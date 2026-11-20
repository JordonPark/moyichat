import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:moyichat/app_update_dialog.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

class _TestUpdater extends Fake implements ShorebirdUpdater {
  Future<UpdateStatus> Function() nextCheck = () async => UpdateStatus.upToDate;
  var checks = 0;
  var downloads = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<UpdateStatus> checkForUpdate({UpdateTrack? track}) {
    checks++;
    return nextCheck();
  }

  @override
  Future<void> update({UpdateTrack? track}) async {
    downloads++;
  }
}

Future<void> _mountDialogLauncher(
  WidgetTester tester,
  ShorebirdUpdater updater,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AppUpdateDialog(updater: updater),
          ),
          child: const Text('업데이트 창 열기'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'checks each time it opens and hides download on the latest build',
    (tester) async {
      final status = Completer<UpdateStatus>();
      final updater = _TestUpdater()..nextCheck = () => status.future;
      await _mountDialogLauncher(tester, updater);
      final open = find.text('업데이트 창 열기');
      final download = find.text('업데이트 받기');

      await tester.tap(open);
      await tester.pump();
      expect(find.text('업데이트를 확인하고 있어요.'), findsOneWidget);
      expect(download, findsNothing);

      status.complete(UpdateStatus.upToDate);
      await tester.pumpAndSettle();
      expect(find.text('최신 버전을 사용 중이에요.'), findsOneWidget);
      expect(download, findsNothing);

      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.text('최신 버전을 사용 중이에요.'), findsOneWidget);
      expect(download, findsNothing);
      expect(updater.checks, 2);
      expect(updater.downloads, 0);
    },
  );

  testWidgets('can retry a failed check and waits for consent to download', (
    tester,
  ) async {
    final updater = _TestUpdater()
      ..nextCheck = () async => throw StateError('Offline');
    await _mountDialogLauncher(tester, updater);
    final download = find.text('업데이트 받기');

    await tester.tap(find.text('업데이트 창 열기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('다시 시도해 주세요'), findsOneWidget);
    expect(download, findsNothing);

    updater.nextCheck = () async => UpdateStatus.outdated;
    await tester.tap(find.text('다시 확인'));
    await tester.pumpAndSettle();
    expect(download, findsOneWidget);
    expect(updater.downloads, 0);

    await tester.tap(download);
    await tester.pumpAndSettle();
    expect(updater.downloads, 1);
    expect(find.text('앱을 다시 열면 업데이트가 적용돼요.'), findsOneWidget);
    expect(download, findsNothing);
  });
}
