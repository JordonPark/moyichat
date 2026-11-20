import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'chat_history.dart';
import 'kanana.dart';
import 'model_store.dart';
import 'online_ads.dart';
import 'photo_analysis.dart';

const _paper = Color(0xfff8f7f1);
const _ink = Color(0xff202e26);
const _muted = Color(0xff526257);
const _pine = Color(0xff164936);
const _line = Color(0xffdedfd4);
const _mint = Color(0xffe3eddf);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['Kanana 1.5 2.1B Instruct'],
      '${await rootBundle.loadString('assets/kanana-notice.txt')}\n'
      '${await rootBundle.loadString('assets/apache-2.0.txt')}',
    );
  });
  runApp(const MoyiChat());
}

class MoyiChat extends StatelessWidget {
  const MoyiChat({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '모이챗',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ko'),
    supportedLocales: const [Locale('ko'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _pine),
      scaffoldBackgroundColor: _paper,
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: _ink,
        displayColor: _ink,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    ),
    home: const Workspace(),
  );
}

enum _ModelStatus {
  checking,
  needed,
  downloading,
  verifying,
  loading,
  ready,
  error,
}

enum _Task {
  summary('내용 요약', '긴 글에서 핵심만', Icons.subject_rounded, '다음 글을 핵심 위주로 요약해 줘.'),
  rewrite(
    '문장 다듬기',
    '더 자연스러운 한국어로',
    Icons.edit_note_rounded,
    '다음 글을 자연스럽고 읽기 쉬운 한국어로 다듬어 줘.',
  ),
  draft('답장 초안', '상황과 말투에 맞게', Icons.reply_rounded, '다음 상황에 어울리는 짧은 답장을 써 줘.'),
  scan(
    '사진 분석',
    '글자와 물체 읽기',
    Icons.document_scanner_outlined,
    '사진에서 추출한 글과 분류 후보를 바탕으로 한국어로 설명해 줘. '
        '분류 후보는 확실한 정보처럼 단정하지 말고, 추출한 정보에 없는 세부 내용은 추측하지 마.',
  );

  const _Task(this.title, this.detail, this.icon, this.prompt);
  final String title;
  final String detail;
  final IconData icon;
  final String prompt;
}

class Workspace extends StatefulWidget {
  const Workspace({super.key});

  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _photos = PhotoAnalysis();
  final _ads = OnlineAds();
  final _messages = <ChatMessage>[];
  _Task? _task;
  ModelStore? _store;
  ChatHistory? _history;
  Kanana? _kanana;
  _ModelStatus _status = _ModelStatus.checking;
  String? _modelError;
  int _received = 0;
  bool _installed = false;
  bool _writing = false;
  bool _stopping = false;
  bool _readingImage = false;
  String _reply = '';

  @override
  void initState() {
    super.initState();
    _ads.start();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    setState(() => _status = _ModelStatus.checking);
    try {
      final support = await getApplicationSupportDirectory();
      final directory = Directory.fromUri(support.uri.resolve('MoyiChat/'));
      await directory.create(recursive: true);
      if (Platform.isIOS) {
        await const MethodChannel(
          'moyichat/photos',
        ).invokeMethod<void>('excludeFromBackup', directory.path);
      }
      final store = ModelStore(directory);
      final history = ChatHistory(directory);
      final restored = await history.read().onError((error, stack) {
        _notify('이전 대화 기록을 읽을 수 없어요.');
        return <ChatMessage>[];
      });
      final installed = await store.isInstalled();
      final partial = await store.partialBytes();
      if (!mounted) return;
      setState(() {
        _store = store;
        _history = history;
        _messages
          ..clear()
          ..addAll(restored);
        _installed = installed;
        _received = partial;
        _status = _ModelStatus.needed;
      });
      if (_messages.isNotEmpty) _toLatest(force: true);
      if (installed) unawaited(_loadModel());
      if (Platform.isAndroid) unawaited(_readImage(recover: true));
    } on Object catch (error) {
      _modelFailure(error, '모이챗의 저장 공간을 열 수 없어요.');
    }
  }

  Future<void> _downloadModel() async {
    final store = _store;
    if (store == null) return;
    setState(() {
      _status = _ModelStatus.downloading;
      _modelError = null;
    });
    try {
      final completed = await store.download(
        onProgress: (bytes) {
          if (mounted) setState(() => _received = bytes);
        },
        onVerify: () {
          if (mounted) setState(() => _status = _ModelStatus.verifying);
        },
      );
      if (!mounted) return;
      if (!completed) {
        setState(() => _status = _ModelStatus.needed);
        return;
      }
      _installed = true;
      await _loadModel();
    } on Object catch (error) {
      if (!mounted) return;
      _received = await store.partialBytes().onError((_, _) => 0);
      _modelFailure(
        error,
        error is ModelDownloadException
            ? error.message
            : '다운로드를 완료하지 못했어요. 연결과 저장 공간을 확인해 주세요.',
      );
    }
  }

  Future<void> _loadModel() async {
    setState(() {
      _status = _ModelStatus.loading;
      _modelError = null;
    });
    try {
      final engine = await Kanana.load(_store!.model.path);
      if (!mounted) {
        await engine.dispose();
        return;
      }
      setState(() {
        _kanana = engine;
        _status = _ModelStatus.ready;
      });
    } on Object catch (error) {
      _modelFailure(error, '모델을 열 수 없어요. 다른 앱을 닫고 다시 시도해 주세요.');
    }
  }

  void _modelFailure(Object error, String message) {
    debugPrint('Model or storage failure: ${error.runtimeType}');
    if (!mounted) return;
    setState(() {
      _status = _ModelStatus.error;
      _modelError = message;
    });
  }

  void _choose(_Task task) {
    if (task == _Task.scan) {
      unawaited(_readImage());
    } else {
      setState(() => _task = task);
      _focus.requestFocus();
    }
  }

  Future<void> _readImage({bool recover = false}) async {
    if (_readingImage || _writing) return;
    setState(() => _readingImage = true);
    try {
      final findings = recover
          ? await _photos.recoverInterruptedPick()
          : await _photos.pickAndAnalyze();
      if (!mounted || findings == null) return;
      if (!findings.hasFindings) {
        _notify('사진에서 글자나 물체 후보를 찾지 못했어요.');
        return;
      }
      final reviewed = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => _PhotoReview(findings: findings),
      );
      if (!mounted || reviewed == null) return;
      final draft = _input.text.trim();
      final combined = draft.isEmpty ? reviewed : '$draft\n\n$reviewed';
      _input.value = TextEditingValue(
        text: combined,
        selection: TextSelection.collapsed(offset: combined.length),
      );
      setState(() => _task ??= _Task.scan);
    } on Object catch (error) {
      debugPrint('Photo analysis failure: ${error.runtimeType}');
      _notify('사진을 분석하지 못했어요. 다른 사진을 골라 주세요.');
    } finally {
      if (mounted) setState(() => _readingImage = false);
    }
  }

  Future<void> _send() async {
    final engine = _kanana;
    final draft = _input.text.trim();
    if (engine == null || draft.isEmpty || _writing || _readingImage) return;
    final task = _task;
    final text = task == null ? draft : '${task.prompt}\n\n$draft';
    _input.clear();
    _focus.unfocus();
    setState(() {
      _messages.add(ChatMessage(isUser: true, text: text));
      _task = null;
      _writing = true;
      _reply = '';
    });
    _toLatest(force: true);
    try {
      await _save();
      if (!mounted || _stopping) return;
      await for (final fragment in engine.reply(_messages)) {
        if (!mounted) break;
        setState(() => _reply += fragment);
        _toLatest();
      }
      if (mounted && !_stopping && _reply.trim().isEmpty) {
        _notify('응답을 만들지 못했어요. 다시 시도해 주세요.');
      }
    } on PromptTooLong {
      _notify('글이 너무 길어요. 몇 부분으로 나눠 보내 주세요.');
    } on Object catch (error) {
      debugPrint('Generation failure: ${error.runtimeType}');
      if (!_stopping) _notify('응답 생성에 문제가 생겼어요. 다시 시도해 주세요.');
    } finally {
      final reply = _reply.trim();
      if (mounted) {
        setState(() {
          if (reply.isEmpty) {
            _messages.removeLast();
            _input.text = draft;
            _task = task;
          } else {
            _messages.add(ChatMessage(isUser: false, text: reply));
          }
          _reply = '';
        });
        await _save();
        if (mounted) {
          setState(() {
            _writing = false;
            _stopping = false;
          });
        }
      }
    }
  }

  Future<void> _save() async {
    try {
      await _history?.write(_messages);
    } on Object catch (error) {
      debugPrint('History save failure: ${error.runtimeType}');
      _notify('대화 기록을 저장하지 못했어요.');
    }
  }

  void _stop() {
    setState(() => _stopping = true);
    _kanana?.stop();
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('새 작업을 시작할까요?'),
        content: const Text('이 기기에 저장된 현재 대화가 지워져요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('새 작업'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _writing) return;
    setState(() {
      _messages.clear();
      _task = null;
      _input.clear();
    });
    await _save();
  }

  void _notify(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _toLatest({bool force = false}) {
    final follow =
        force || !_scroll.hasClients || _scroll.position.extentAfter < 100;
    if (!follow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _store?.pause();
    _ads.dispose();
    final model = _kanana;
    if (model != null) unawaited(model.dispose());
    _scroll.dispose();
    _focus.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
            children: [
              _header(),
              const Divider(height: 1, color: _line),
              _banner(),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                  children: [
                    if (_messages.isEmpty) _welcome(),
                    if (_status != _ModelStatus.ready) _modelCard(),
                    if (_messages.isEmpty) _taskGrid(),
                    for (final message in _messages) _bubble(message),
                    if (_writing)
                      if (_reply.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8, bottom: 12),
                          child: Text(
                            'Kanana가 답변을 준비하고 있어요…',
                            style: TextStyle(color: _muted),
                          ),
                        )
                      else
                        _bubble(
                          ChatMessage(isUser: false, text: _reply),
                          streaming: true,
                        ),
                  ],
                ),
              ),
              _composer(),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
    child: Row(
      children: [
        const _AppMark(),
        const SizedBox(width: 10),
        const Text(
          '모이챗',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
        ),
        const Spacer(),
        if (_status == _ModelStatus.ready)
          const Flexible(
            child: Text(
              '오프라인 AI',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _pine,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        if (_messages.isNotEmpty)
          IconButton(
            tooltip: '새 작업',
            onPressed: _writing || _readingImage ? null : _clear,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        IconButton(
          tooltip: '앱 정보 및 라이선스',
          icon: const Icon(Icons.info_outline_rounded),
          onPressed: () => showAboutDialog(
            context: context,
            applicationName: '모이챗',
            applicationVersion: '0.1.0',
            applicationIcon: const _AppMark(),
            children: [
              const Text(
                'Kanana 1.5 2.1B Instruct · Q4_K_M\n한국어 오프라인 AI 작업 공간',
              ),
              if (_ads.canShowPrivacyOptions)
                TextButton(
                  onPressed: () => unawaited(_ads.showPrivacyOptions()),
                  child: const Text('광고 개인정보 설정'),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _banner() => ListenableBuilder(
    listenable: _ads,
    builder: (context, _) {
      if (MediaQuery.viewInsetsOf(context).bottom > 0) {
        return const SizedBox.shrink();
      }
      final ad = _ads.banner;
      if (ad == null) return const SizedBox.shrink();
      return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < ad.size.width) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Column(
              children: [
                const Text('광고', style: TextStyle(color: _muted, fontSize: 11)),
                SizedBox(
                  width: ad.size.width.toDouble(),
                  height: ad.size.height.toDouble(),
                  child: AdWidget(key: ObjectKey(ad), ad: ad),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  Widget _welcome() => const Padding(
    padding: EdgeInsets.only(bottom: 23, top: 7),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '오늘은 무슨 일을\n도와드릴까요?',
          style: TextStyle(
            fontSize: 35,
            height: 1.18,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.4,
          ),
        ),
        SizedBox(height: 12),
        Text(
          '대화와 사진을 이 기기에서 처리해요.',
          style: TextStyle(fontSize: 14, color: _muted),
        ),
      ],
    ),
  );

  Widget _modelCard() {
    final downloading = _status == _ModelStatus.downloading;
    final checking =
        _status == _ModelStatus.verifying ||
        _status == _ModelStatus.loading ||
        _status == _ModelStatus.checking;
    final title = switch (_status) {
      _ModelStatus.downloading => 'Kanana 다운로드 중',
      _ModelStatus.verifying => '모델 파일 확인 중',
      _ModelStatus.loading => 'Kanana 준비 중',
      _ModelStatus.checking => '저장 공간 확인 중',
      _ModelStatus.error => '모델을 준비할 수 없어요',
      _ => '오프라인 AI 준비하기',
    };
    final progress = (_received / ModelStore.bytes).clamp(0.0, 1.0);
    final details =
        _modelError ??
        (downloading
            ? '${(_received / 1000000000).toStringAsFixed(2)} / 1.52 GB'
            : 'Kanana · 1.52 GB\n한 번 받으면 인터넷 없이 대화할 수 있어요.');
    return Container(
      margin: const EdgeInsets.only(bottom: 23),
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: _pine,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 19,
            ),
          ),
          const SizedBox(height: 6),
          Text(details, style: const TextStyle(color: _mint, height: 1.55)),
          if (downloading || checking) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: downloading ? progress : null,
              backgroundColor: const Color(0xff3c6455),
              color: _mint,
              borderRadius: BorderRadius.circular(5),
            ),
          ],
          if (!checking) ...[
            const SizedBox(height: 13),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _mint,
                foregroundColor: _pine,
              ),
              onPressed: downloading
                  ? _store?.pause
                  : _store == null
                  ? _initialize
                  : _installed
                  ? _loadModel
                  : _downloadModel,
              icon: Icon(
                downloading
                    ? Icons.pause_rounded
                    : _installed || _store == null
                    ? Icons.refresh_rounded
                    : Icons.download_rounded,
              ),
              label: Text(
                downloading
                    ? '일시 정지'
                    : _installed || _store == null
                    ? '다시 시도'
                    : _received > 0
                    ? '이어받기'
                    : '모델 다운로드',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _taskGrid() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 11),
        child: Text(
          '작업 선택',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
      LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final width = constraints.maxWidth < 310 || textScale > 1.5
              ? constraints.maxWidth
              : (constraints.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final task in _Task.values)
                SizedBox(
                  width: width,
                  child: Material(
                    color: _task == task ? _mint : const Color(0xfffdfcf7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: _line),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _readingImage || _writing
                          ? null
                          : () => _choose(task),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(task.icon, color: _pine, size: 22),
                            const SizedBox(height: 9),
                            Text(
                              task.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              task.detail,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );

  Widget _bubble(ChatMessage message, {bool streaming = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: message.isUser ? .88 : 1,
        child: Column(
          crossAxisAlignment: message.isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!message.isUser)
              const Padding(
                padding: EdgeInsets.only(bottom: 5, left: 3),
                child: Text(
                  'Kanana',
                  style: TextStyle(
                    fontSize: 12,
                    color: _pine,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              decoration: BoxDecoration(
                color: message.isUser ? _mint : const Color(0xfffdfcf7),
                border: Border.all(color: _line),
                borderRadius: BorderRadius.circular(16),
              ),
              child: SelectableText(
                message.text,
                style: const TextStyle(fontSize: 15, height: 1.58),
              ),
            ),
            if (!message.isUser && !streaming)
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: message.text));
                  _notify('답변을 복사했어요.');
                },
                icon: const Icon(Icons.copy_rounded, size: 15),
                label: const Text('복사'),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _composer() => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: _line)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_task case final task?)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: InputChip(
                avatar: Icon(task.icon, size: 17),
                label: Text(task.title),
                onDeleted: _writing ? null : () => setState(() => _task = null),
                deleteButtonTooltipMessage: '작업 선택 해제',
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _line),
              borderRadius: BorderRadius.circular(25),
            ),
            padding: const EdgeInsets.fromLTRB(4, 3, 5, 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: '사진에서 글자와 물체 찾기',
                  onPressed: _readingImage || _writing
                      ? null
                      : () => _readImage(),
                  icon: _readingImage
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_photo_alternate_outlined),
                ),
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    readOnly: _writing,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: _task == null
                          ? '모이챗에 메시지 보내기'
                          : '작업할 내용을 입력하세요',
                      hintStyle: const TextStyle(color: _muted, fontSize: 14),
                    ),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _input,
                  builder: (context, value, _) => IconButton.filled(
                    tooltip: _writing ? '응답 중지' : '보내기',
                    onPressed: _writing
                        ? _stopping
                              ? null
                              : _stop
                        : _status == _ModelStatus.ready &&
                              !_readingImage &&
                              value.text.trim().isNotEmpty
                        ? _send
                        : null,
                    icon: Icon(
                      _writing
                          ? Icons.stop_rounded
                          : Icons.arrow_upward_rounded,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 35,
    height: 35,
    decoration: BoxDecoration(
      color: _pine,
      borderRadius: BorderRadius.circular(11),
    ),
    child: const Icon(Icons.forum_outlined, size: 18, color: _mint),
  );
}

class _PhotoReview extends StatefulWidget {
  const _PhotoReview({required this.findings});
  final PhotoFindings findings;

  @override
  State<_PhotoReview> createState() => _PhotoReviewState();
}

class _PhotoReviewState extends State<_PhotoReview> {
  late final _text = TextEditingController(text: widget.findings.transcript);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '사진 분석 결과',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 7),
          Text(switch (widget.findings) {
            PhotoFindings(text: null) => '글자 인식에 실패했어요. 물체 후보를 확인해 주세요.',
            PhotoFindings(labels: null) => '물체 분류에 실패했어요. 읽은 글자를 확인해 주세요.',
            _ => '물체 후보와 읽은 글자를 확인하고 수정할 수 있어요.',
          }),
          const SizedBox(height: 14),
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 7,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _text,
            builder: (context, value, _) => FilledButton(
              onPressed: value.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, value.text.trim()),
              child: const Text('입력창에 추가'),
            ),
          ),
        ],
      ),
    ),
  );
}
