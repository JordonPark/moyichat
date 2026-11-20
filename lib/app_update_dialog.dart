import 'package:material_ui/material_ui.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({super.key, this.updater});

  final ShorebirdUpdater? updater;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  late final _updater = widget.updater ?? ShorebirdUpdater();
  bool _busy = false;
  UpdateStatus? _result;
  String? _message;

  Future<void> _checkAndDownload() async {
    setState(() {
      _busy = true;
      _message = '업데이트를 확인하고 있어요.';
    });
    try {
      final status = await _updater.checkForUpdate();
      if (!mounted) return;
      if (status == UpdateStatus.outdated) {
        setState(() => _message = '업데이트를 받고 있어요.');
        await _updater.update();
      }
      if (!mounted) return;
      setState(() {
        _result = status;
        _message = switch (status) {
          UpdateStatus.restartRequired ||
          UpdateStatus.outdated => '업데이트를 받았어요. 앱을 다시 열면 적용돼요.',
          UpdateStatus.upToDate => '최신 버전을 사용 중이에요.',
          UpdateStatus.unavailable => '이 설치본은 앱 내 업데이트를 지원하지 않아요.',
        };
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = '업데이트를 확인하거나 받지 못했어요. 연결을 확인하고 다시 시도해 주세요.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('앱 업데이트'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_busy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
            Semantics(
              liveRegion: true,
              child: Text(
                _message ??
                    (_updater.isAvailable
                        ? '인터넷에 연결한 뒤 최신 업데이트를 받을 수 있어요.'
                        : '이 설치본은 앱 내 업데이트를 지원하지 않아요.'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          if (_updater.isAvailable && _result == null)
            FilledButton(
              onPressed: _busy ? null : _checkAndDownload,
              child: const Text('업데이트 확인 및 받기'),
            ),
        ],
      ),
    );
  }
}
