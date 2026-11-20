import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

enum _UpdatePhase {
  checking('업데이트를 확인하고 있어요.'),
  available('새 업데이트를 받을 수 있어요.'),
  downloading('업데이트를 받고 있어요.'),
  current('최신 버전을 사용 중이에요.'),
  restartRequired('앱을 다시 열면 업데이트가 적용돼요.'),
  failed('업데이트를 확인하거나 받지 못했어요. 연결을 확인하고 다시 시도해 주세요.'),
  unavailable('이 설치본은 앱 내 업데이트를 지원하지 않아요.');

  const _UpdatePhase(this.message);

  final String message;
}

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({super.key, this.updater});

  final ShorebirdUpdater? updater;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  late final _updater = widget.updater ?? ShorebirdUpdater();
  late _UpdatePhase _phase;

  @override
  void initState() {
    super.initState();
    _phase = _UpdatePhase.unavailable;
    if (_updater.isAvailable) unawaited(_check());
  }

  Future<void> _check() async {
    setState(() => _phase = _UpdatePhase.checking);
    final _UpdatePhase result;
    try {
      result = switch (await _updater.checkForUpdate()) {
        UpdateStatus.outdated => _UpdatePhase.available,
        UpdateStatus.restartRequired => _UpdatePhase.restartRequired,
        UpdateStatus.upToDate => _UpdatePhase.current,
        UpdateStatus.unavailable => _UpdatePhase.unavailable,
      };
    } catch (_) {
      if (mounted) setState(() => _phase = _UpdatePhase.failed);
      return;
    }
    if (mounted) setState(() => _phase = result);
  }

  Future<void> _download() async {
    if (_phase != _UpdatePhase.available) return;
    setState(() => _phase = _UpdatePhase.downloading);
    try {
      await _updater.update();
      if (mounted) setState(() => _phase = _UpdatePhase.restartRequired);
    } catch (_) {
      if (mounted) setState(() => _phase = _UpdatePhase.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloading = _phase == _UpdatePhase.downloading;
    return PopScope(
      canPop: !downloading,
      child: AlertDialog(
        title: const Text('앱 업데이트'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_phase == _UpdatePhase.checking || downloading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
            Semantics(liveRegion: true, child: Text(_phase.message)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: downloading ? null : () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          if (_phase == _UpdatePhase.available)
            FilledButton(onPressed: _download, child: const Text('업데이트 받기')),
          if (_phase == _UpdatePhase.failed)
            FilledButton(onPressed: _check, child: const Text('다시 확인')),
        ],
      ),
    );
  }
}
