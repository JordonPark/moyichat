import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:moyichat/app_update_dialog.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

class _TestUpdater extends Fake implements ShorebirdUpdater {
  var shouldFail = false;

  @override
  bool get isAvailable => true;

  @override
  Future<UpdateStatus> checkForUpdate({UpdateTrack? track}) async {
    if (shouldFail) throw StateError('Offline');
    return UpdateStatus.upToDate;
  }
}

void main() {
  testWidgets('shows only Close after a successful latest-version check', (
    tester,
  ) async {
    final updater = _TestUpdater()..shouldFail = true;
    await tester.pumpWidget(
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
    final open = find.text('업데이트 창 열기');
    final check = find.text('업데이트 확인 및 받기');

    await tester.tap(open);
    await tester.pumpAndSettle();
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(find.textContaining('다시 시도해 주세요'), findsOneWidget);
    expect(check, findsOneWidget);

    updater.shouldFail = false;
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(find.text('최신 버전을 사용 중이에요.'), findsOneWidget);
    expect(check, findsNothing);

    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(check, findsOneWidget);
  });
}
