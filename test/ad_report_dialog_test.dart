import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:moyichat/ad_report_dialog.dart';

void main() {
  testWidgets('composes an ad report with the current ad identifiers', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const links = MethodChannel('moyichat/links');
    final messenger = tester.binding.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(links, null);
      debugDefaultTargetPlatformOverride = null;
    });
    MethodCall? sent;
    messenger.setMockMethodCallHandler(links, (call) async {
      sent = call;
      return true;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAdReportDialog(
                context,
                adUnitId: 'example-ad-unit',
                responseId: 'example-ad-response',
              ),
              child: const Text('광고 정보 및 신고'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이메일 작성'));
    await tester.pumpAndSettle();

    expect(sent?.method, 'openSupportMail');
    final mail = Uri.parse(sent!.arguments as String);
    expect(mail.path, 'moyichats@gmail.com');
    expect(mail.queryParameters['body'], contains('example-ad-unit'));
    expect(mail.queryParameters['body'], contains('example-ad-response'));
  });
}
