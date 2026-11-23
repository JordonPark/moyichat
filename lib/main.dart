import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

import 'app_update_dialog.dart';
import 'assistant_avatar.dart';
import 'assistant_identity.dart';
import 'chat_history.dart';
import 'chat_photo.dart';
import 'conversation_safety.dart';
import 'generation_size.dart';
import 'kanana.dart';
import 'model_store.dart';
import 'online_ads.dart';
import 'photo_analysis.dart';
import 'photo_reply.dart';
import 'privacy_policy.dart';
import 'preview_storage_stub.dart'
    if (dart.library.js_interop) 'preview_storage.dart';
import 'reply_markdown.dart';
import 'response_style_dialog.dart';
import 'workspace_layout.dart';

const _paper = Color(0xfff8f5eb);
const _surface = Color(0xfffffcf4);
const _ink = Color(0xff24352c);
const _muted = Color(0xff4e6053);
const _pine = Color(0xff20513d);
const _line = Color(0xffdcded1);
const _mint = Color(0xffe0ecd8);
const _workspaceGutter = 18.0;
const _appVersion = String.fromEnvironment(
  'MOYI_APP_VERSION',
  defaultValue: '0.1.0',
);

IconData _controlIcon(IconData material, IconData cupertino) =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
    ? cupertino
    : material;

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
        insetPadding: EdgeInsets.fromLTRB(16, 0, 16, 84),
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
  summary('내용 요약', '긴 글에서 핵심만', '다음 글을 핵심 위주로 요약해 줘.'),
  rewrite('문장 다듬기', '더 자연스러운 한국어로', '다음 글을 자연스럽고 읽기 쉬운 한국어로 다듬어 줘.'),
  draft('답장 초안', '상황과 말투에 맞게', '다음 상황에 어울리는 짧은 답장을 써 줘.'),
  scan(
    '사진 분석',
    '글자와 물체 읽기',
    '사진에서 읽은 내용과 앞선 대화를 참고해 사용자가 지금 필요한 정보만 한국어로 뽑아 줘.',
  );

  const _Task(this.title, this.detail, this.prompt);
  final String title;
  final String detail;
  final String prompt;

  Widget illustration(double size) => Image.asset(
    'assets/tasks/$name.webp',
    width: size,
    height: size,
    fit: BoxFit.contain,
    excludeFromSemantics: true,
  );

  Color get tint => switch (this) {
    _Task.summary => const Color(0xffe4eed8),
    _Task.rewrite => const Color(0xfff4e3dc),
    _Task.draft => const Color(0xffeee6f3),
    _Task.scan => const Color(0xffe0edeb),
  };
}

enum _TaskMenuAction { responseStyle, rename, delete }

class Workspace extends StatefulWidget {
  const Workspace({super.key});

  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  static const _layoutChannel = MethodChannel('moyichat/layout');
  static const _maxAttachments = 10;
  static const _previewBytes = 24000000;
  static const _previewTick = Duration(milliseconds: 160);
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _taskSearchFocus = FocusNode();
  final _scroll = ScrollController();
  final _taskSearch = TextEditingController();
  final _photos = PhotoAnalysis();
  final _ads = kIsWeb ? null : OnlineAds();
  late final _updater = kIsWeb ? null : ShorebirdUpdater();
  late ChatTask _activeTask = ChatTask.create();
  late final _tasks = <ChatTask>[_activeTask];
  List<ChatMessage> get _messages => _activeTask.messages;
  ChatTask? get _parentTask =>
      _tasks.where((task) => task.id == _activeTask.parentId).firstOrNull;
  final _drafts =
      <String, ({String text, _Task? action, List<PhotoFindings> photos})>{};
  final _attachedPhotos = <PhotoFindings>[];
  _Task? _task;
  ModelStore? _store;
  ChatHistory? _history;
  Kanana? _kanana;
  _ModelStatus _status = _ModelStatus.checking;
  String? _modelError;
  int _received = 0;
  double? _downloadSpeed;
  bool _installed = false;
  bool _writing = false;
  bool _summarizing = false;
  bool _stopping = false;
  bool _readingImage = false;
  bool _requestingDownload = false;
  bool _previewConsent = false;
  String _reply = '';
  String _assistantName = defaultAssistantName;
  Uint8List? _assistantAvatar;
  String? _assistantStyle;
  GenerationSize? _manualSize;
  DeviceMemory? _deviceMemory;

  GenerationSize get _recommendedSize =>
      _deviceMemory?.recommended ??
      (kIsWeb ? GenerationSize.normal : GenerationSize.small);
  GenerationSize get _selectedSize => _manualSize ?? _recommendedSize;
  Timer? _previewDownload;
  double? _followTarget;
  bool _iosCompactWidth = false;
  AxisDirection? _iosToolbarEdge;
  Rect? _iosToolbarFrame;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      _layoutChannel.setMethodCallHandler((call) async {
        if (call.method == 'layoutChanged') _updateIosLayout(call.arguments);
      });
      unawaited(_readIosLayout());
    }
    if (kIsWeb) {
      final history = _history = ChatHistory.preview();
      unawaited(_initializePreview(history));
    } else {
      unawaited(_initialize());
    }
  }

  Future<void> _readIosLayout() async {
    try {
      _updateIosLayout(await _layoutChannel.invokeMethod('currentLayout'));
    } on PlatformException catch (error) {
      debugPrint('Unable to read iOS layout: ${error.code}');
    } on MissingPluginException {
      // The workspace can adapt from window metrics without a native channel.
    }
  }

  void _updateIosLayout(Object? data) {
    if (!mounted || data is! Map) return;
    final compact = data['compactWidth'] == true;
    final edge = switch (data['toolbarEdge']) {
      'left' => AxisDirection.left,
      'right' => AxisDirection.right,
      _ => null,
    };
    final frame = switch (data['toolbarFrame']) {
      [final num x, final num y, final num width, final num height] =>
        Rect.fromLTWH(
          x.toDouble(),
          y.toDouble(),
          width.toDouble(),
          height.toDouble(),
        ),
      _ => null,
    };
    if (_iosCompactWidth == compact &&
        _iosToolbarEdge == edge &&
        _iosToolbarFrame == frame) {
      return;
    }
    setState(() {
      _iosCompactWidth = compact;
      _iosToolbarEdge = edge;
      _iosToolbarFrame = frame;
    });
  }

  Future<void> _initializePreview(ChatHistory history) async {
    final splash = Future<void>.delayed(const Duration(milliseconds: 350));
    final saved = await _readHistory(history);
    await splash;
    if (!mounted) return;
    var ready = false;
    try {
      ready = previewModelReady();
    } on Object catch (error) {
      debugPrint('Preview model state unavailable: ${error.runtimeType}');
    }
    setState(() {
      if (saved != null) _restoreTasks(saved);
      _status = ready ? _ModelStatus.ready : _ModelStatus.needed;
    });
    if (ready && _messages.isNotEmpty) _toLatest(force: true);
  }

  Future<void> _requestDownload() async {
    if (_requestingDownload || _status == _ModelStatus.downloading) return;
    _requestingDownload = true;
    try {
      final store = _store;
      final accepted = kIsWeb
          ? _previewConsent
          : await store!.hasDownloadConsent();
      if (!mounted) return;
      if (!accepted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text(kIsWeb ? '샘플 다운로드 안내' : '모델 다운로드 안내'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    kIsWeb
                        ? '웹 미리보기는 샘플 속도로 진행돼요. 실제 모델 파일은 받지 않아요.'
                        : 'Hugging Face에서 Kanana 모델 약 1.52GB를 받아 앱 전용 저장 공간에 보관해요. 다운로드에는 인터넷 연결이 필요하며 모바일 데이터가 사용될 수 있어요.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '모바일 앱은 사진과 대화를 기기 안에서 처리해요. AI 답변은 틀릴 수 있으니 중요한 내용은 확인해 주세요.',
                  ),
                  TextButton(
                    onPressed: () => showLicensePage(
                      context: context,
                      applicationName: '모이챗',
                    ),
                    child: const Text('Kanana 모델 라이선스 보기'),
                  ),
                  TextButton(
                    onPressed: () => showPrivacyPolicy(context),
                    child: const Text('개인정보 처리방침'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('나중에'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('동의하고 다운로드'),
              ),
            ],
          ),
        );
        if (!mounted || confirmed != true) return;
        if (kIsWeb) {
          _previewConsent = true;
        } else {
          await store!.acceptDownload();
        }
      }
      if (!mounted) return;
      if (kIsWeb) {
        _startPreviewDownload();
      } else {
        await _downloadModel();
      }
    } on Object catch (error) {
      _modelFailure(error, '다운로드 동의를 저장할 수 없어요. 다시 시도해 주세요.');
    } finally {
      _requestingDownload = false;
    }
  }

  Future<ChatWorkspace?> _readHistory(ChatHistory history) =>
      history.read().onError((error, stack) {
        _notify('이전 작업을 읽을 수 없어요.');
        return null;
      });

  void _restoreTasks(ChatWorkspace saved) {
    _assistantName = saved.assistantName;
    _assistantStyle = saved.responseStyle;
    if (saved.assistantAvatar case final value?) {
      try {
        _assistantAvatar = base64Decode(value);
      } on FormatException {
        _assistantAvatar = null;
      }
    }
    _manualSize = saved.generationSize;
    if (saved.tasks.isEmpty) return;
    _tasks
      ..clear()
      ..addAll(saved.tasks);
    _activeTask =
        _tasks.where((task) => task.id == saved.activeId).firstOrNull ??
        _tasks.first;
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
      final restored = await _readHistory(history);
      final memory = await DeviceMemory.read();
      final installed = await store.isInstalled();
      final partial = await store.partialBytes();
      if (!mounted) return;
      setState(() {
        _store = store;
        _history = history;
        _deviceMemory = memory;
        if (restored != null) _restoreTasks(restored);
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
      _downloadSpeed = null;
    });
    final clock = Stopwatch()..start();
    int? lastBytes;
    var lastTime = 0;
    try {
      final completed = await store.download(
        onProgress: (bytes) {
          if (!mounted) return;
          final previous = lastBytes;
          final now = clock.elapsedMilliseconds;
          setState(() {
            _received = bytes;
            if (previous == null || bytes < previous) {
              lastBytes = bytes;
              lastTime = now;
              _downloadSpeed = null;
            } else if (now - lastTime >= 400) {
              final speed = (bytes - previous) * 1000 / (now - lastTime);
              _downloadSpeed = (_downloadSpeed ?? speed) * .65 + speed * .35;
              lastBytes = bytes;
              lastTime = now;
            }
          });
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
      final engine = await Kanana.load(_store!.model.path, size: _selectedSize);
      if (!mounted) {
        await engine.dispose();
        return;
      }
      setState(() {
        _kanana = engine;
        _status = _ModelStatus.ready;
      });
      _ads?.start();
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

  void _startPreviewDownload() {
    setState(() => _status = _ModelStatus.downloading);
    _previewDownload = Timer.periodic(_previewTick, (timer) {
      setState(() {
        _received += _previewBytes ~/ 18;
        if (_received >= _previewBytes) {
          timer.cancel();
          _status = _ModelStatus.loading;
          _previewDownload = Timer(const Duration(milliseconds: 400), () {
            if (!mounted) return;
            _rememberPreviewModel(true);
            setState(() => _status = _ModelStatus.ready);
            if (_messages.isNotEmpty) _toLatest(force: true);
          });
        }
      });
    });
  }

  void _rememberPreviewModel(bool ready) {
    try {
      setPreviewModelReady(ready);
    } on Object catch (error) {
      debugPrint('Preview model state unavailable: ${error.runtimeType}');
    }
  }

  void _resetPreviewDownload() {
    _rememberPreviewModel(false);
    setState(() {
      _previewConsent = false;
      _received = 0;
      _status = _ModelStatus.needed;
    });
  }

  void _pausePreviewDownload() {
    _previewDownload?.cancel();
    setState(() => _status = _ModelStatus.needed);
  }

  void _choose(_Task task, {required bool keyboardVisible}) {
    if (keyboardVisible) {
      _focus.unfocus();
      _taskSearchFocus.unfocus();
      return;
    }
    if (task == _Task.scan) {
      unawaited(_readImage());
    } else {
      setState(() => _task = task);
      _focus.requestFocus();
    }
  }

  Future<void> _readImage({bool recover = false}) async {
    if (_readingImage || _writing) return;
    if (_attachedPhotos.length >= _maxAttachments) {
      _notify('이미지는 한 메시지에 최대 $_maxAttachments장까지 첨부할 수 있어요.');
      return;
    }
    setState(() => _readingImage = true);
    try {
      final findings = kIsWeb
          ? const PhotoFindings(
              text: '모이챗 사진 테스트\n사과 2개 · 우유 1개',
              labels: ['Apple', 'Milk carton'],
            )
          : recover
          ? await _photos.recoverInterruptedPick()
          : await _photos.pickAndAnalyze();
      if (!mounted || findings == null) return;
      final attached = await showModalBottomSheet<PhotoFindings>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        anchorPoint: MediaQuery.sizeOf(context).bottomRight(Offset.zero),
        builder: (context) => _PhotoReview(
          findings: findings,
          pickLocal: kIsWeb ? _photos.pickPreviewImage : null,
        ),
      );
      if (!mounted || attached == null) return;
      setState(() => _attachedPhotos.add(attached));
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
    if (_status != _ModelStatus.ready ||
        (draft.isEmpty && _attachedPhotos.isEmpty) ||
        _writing ||
        _readingImage) {
      return;
    }
    final task = _task;
    if (task == null && requestsAssistantAvatar(draft)) {
      await _changeAssistantAvatar(
        command: draft,
        source: _attachedPhotos.length == 1
            ? _attachedPhotos.single.imageBytes
            : null,
      );
      return;
    }
    final parent = _parentTask;
    final photos = _attachedPhotos.toList();
    final photoTask = photos.isNotEmpty;
    List<String> photoIds = const [];
    if (photoTask) {
      final history = _history;
      if (history == null) return;
      setState(() => _writing = true);
      try {
        photoIds = await history.storePhotos([
          for (final photo in photos)
            photo.imageBytes ??
                Uint8List.sublistView(
                  await rootBundle.load('assets/preview-groceries.png'),
                ),
        ]);
      } on Object catch (error) {
        debugPrint('Chat photo save failure: ${error.runtimeType}');
        if (mounted) {
          setState(() {
            _writing = false;
            _stopping = false;
          });
          _notify('사진을 저장하지 못했어요. 저장 공간을 확인하고 다시 보내 주세요.');
        }
        return;
      }
      if (!mounted || _stopping) {
        await history.discardPhotos(photoIds);
        if (mounted) {
          setState(() {
            _writing = false;
            _stopping = false;
          });
        }
        return;
      }
    }
    final renamed = task == null && !photoTask
        ? requestedAssistantName(draft)
        : null;
    final guarded = task == null && !photoTask ? localSafetyReply(draft) : null;
    final photoContext = photos.map((photo) => photo.modelContext).toList();
    final instruction = [
      if (task != null) task.prompt,
      if (photoTask)
        '현재 질문에 맞춰 사진에서 확인되는 내용만 답해. '
            '별도 질문이 없으면 사진의 핵심만 알려 줘.',
      for (final (index, evidence) in photoContext.indexed)
        if (evidence.isNotEmpty) '이미지 ${index + 1}\n$evidence',
    ];
    _input.clear();
    _focus.unfocus();
    setState(() {
      if (renamed != null) _assistantName = renamed;
      _tasks
        ..remove(_activeTask)
        ..insert(0, _activeTask);
      _messages.add(
        ChatMessage(
          isUser: true,
          text: draft,
          instruction: instruction.isEmpty ? null : instruction.join('\n'),
          photoIds: photoIds,
        ),
      );
      _attachedPhotos.clear();
      _task = null;
      _writing = true;
      _reply = '';
    });
    _toLatest(force: true);
    final photoReply = photoTask ? StringBuffer() : null;
    try {
      await _save();
      if (!mounted || _stopping) return;
      if (engine != null && renamed == null && guarded == null) {
        await _updateConversationMemory(engine);
        if (!mounted || _stopping) return;
      }
      final response = renamed != null
          ? Stream.value('좋아요. 앞으로 “$renamed”라고 불러 주세요.')
          : guarded != null
          ? Stream.value(guarded)
          : kIsWeb
          ? _previewReply(
              photoTask ? _Task.scan : task,
              parent: parent,
              hasLocalImage: photos.any((photo) => photo.imageBytes != null),
            )
          : engine!.reply(
              _messages,
              assistantName: _assistantName,
              responseStyle:
                  _activeTask.responseStyle ??
                  _parentTask?.responseStyle ??
                  _assistantStyle,
              memorySummary: _activeTask.memory?.summary,
              summarizedMessageCount: _activeTask.memory?.messageCount ?? 0,
              parentConversation: parent?.messages ?? const [],
              parentMemorySummary: parent?.memory?.summary,
              extractFacts: photoTask,
            );
      await for (final fragment in response) {
        if (!mounted) break;
        photoReply?.write(fragment);
        final visible = photoReply == null
            ? '$_reply$fragment'
            : cleanPhotoReply(photoReply.toString(), streaming: true);
        if (_reply != visible) {
          setState(() => _reply = visible);
          _toLatest();
        }
      }
      if (mounted && photoReply != null) {
        setState(() => _reply = cleanPhotoReply(photoReply.toString()));
      }
      if (mounted && !_stopping && _reply.trim().isEmpty) {
        _notify('응답을 만들지 못했어요. 다시 시도해 주세요.');
      }
    } on PromptTooLong catch (error) {
      _notify('입력 한도 ${error.limit}토큰을 넘었어요. 글이나 이미지를 나눠 보내 주세요.');
    } on Object catch (error) {
      debugPrint('Generation failure: ${error.runtimeType}');
      if (!_stopping) _notify('응답 생성에 문제가 생겼어요. 다시 시도해 주세요.');
    } finally {
      final reply =
          (photoReply == null ? _reply : cleanPhotoReply(photoReply.toString()))
              .trim();
      if (mounted) {
        setState(() {
          if (reply.isEmpty) {
            _messages.removeLast();
            _input.text = draft;
            _task = task;
            _attachedPhotos.addAll(photos);
          } else {
            _messages.add(ChatMessage(isUser: false, text: reply));
          }
          _reply = '';
          _writing = false;
          _summarizing = false;
          _stopping = false;
        });
        _toLatest();
        await _save();
      }
    }
  }

  Future<void> _updateConversationMemory(Kanana engine) async {
    final task = _activeTask;
    final archive = task.nextMemoryBatch;
    if (archive.isEmpty) return;
    final memory = task.memory;
    setState(() => _summarizing = true);
    try {
      final summary = await engine.summarize(
        archive,
        previousSummary: memory?.summary,
      );
      if (summary != null && !_stopping) {
        task.memory = ConversationMemory(
          summary: summary,
          messageCount: (memory?.messageCount ?? 0) + archive.length,
        );
      }
    } on Object catch (error) {
      debugPrint('Conversation summary failed: ${error.runtimeType}');
    } finally {
      if (mounted) setState(() => _summarizing = false);
    }
  }

  Future<void> _changeAssistantAvatar({
    String? command,
    Uint8List? source,
  }) async {
    if (_readingImage || _writing) return;
    setState(() => _readingImage = true);
    try {
      final bytes = source ?? await _photos.pickImageBytes();
      if (!mounted || bytes == null) return;
      final avatar = await makeAssistantAvatar(bytes);
      if (!mounted) return;
      setState(() {
        _assistantAvatar = avatar;
        if (command != null) {
          _tasks
            ..remove(_activeTask)
            ..insert(0, _activeTask);
          _input.clear();
          _attachedPhotos.clear();
          _messages.addAll([
            ChatMessage(isUser: true, text: command),
            const ChatMessage(isUser: false, text: '프로필 사진을 바꿨어요.'),
          ]);
        }
      });
      if (command != null) {
        _focus.unfocus();
        _toLatest(force: true);
      }
      await _save();
    } on Object catch (error) {
      debugPrint('Profile photo failure: ${error.runtimeType}');
      _notify('프로필 사진을 읽을 수 없어요. 다른 사진을 골라 주세요.');
    } finally {
      if (mounted) setState(() => _readingImage = false);
    }
  }

  Stream<String> _previewReply(
    _Task? task, {
    ChatTask? parent,
    bool hasLocalImage = false,
  }) async* {
    final example = switch (task) {
      _Task.summary =>
        '핵심은 일정과 다음 할 일이에요.\n• 금요일 오후에 초안을 검토해요.\n• 의견을 모아 최종본을 정리해요.',
      _Task.rewrite => '안녕하세요. 이번 주 금요일까지 초안을 검토해 주시면 감사하겠습니다.',
      _Task.draft => '안녕하세요! 보내 주신 내용 확인했어요. 금요일 오후까지 검토해서 답드릴게요.',
      _Task.scan =>
        hasLocalImage
            ? '이미지가 첨부됐어요. 실제 이미지 인식은 모바일 앱에서 확인할 수 있어요.'
            : '장볼 것\n• 사과 2개\n• 우유 1개',
      null =>
        parent == null
            ? '안녕하세요! 메시지가 채팅창에 표시됐어요. 답변 복사, 응답 중지, 새 작업 시작을 테스트해 보세요.'
            : '상위 작업 “${parent.title}”의 대화를 참고하도록 연결했어요. 이 답변은 흐름 확인용 샘플이에요.',
    };
    if (MediaQuery.disableAnimationsOf(context)) {
      yield example;
      return;
    }
    for (final character in example.characters) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (!mounted || _stopping) return;
      yield character;
    }
  }

  Future<void> _save() async {
    try {
      await _history?.write(
        ChatWorkspace(
          activeId: _activeTask.id,
          tasks: _tasks,
          assistantName: _assistantName,
          responseStyle: _assistantStyle,
          generationSize: _manualSize,
          assistantAvatar: _assistantAvatar == null
              ? null
              : base64Encode(_assistantAvatar!),
        ),
      );
    } on Object catch (error) {
      debugPrint('History save failure: ${error.runtimeType}');
      _notify('대화 기록을 저장하지 못했어요.');
    }
  }

  void _stop() {
    setState(() => _stopping = true);
    _kanana?.stop();
  }

  void _newTask() {
    if (_writing || _readingImage) return;
    if (_messages.isEmpty &&
        _input.text.trim().isEmpty &&
        _attachedPhotos.isEmpty &&
        _task == null &&
        _activeTask.name == null &&
        _activeTask.responseStyle == null) {
      return;
    }
    final task = ChatTask.create();
    _tasks.insert(0, task);
    _openTask(task);
  }

  void _newChildTask(ChatTask parent) {
    if (_writing || _readingImage || parent.parentId != null) return;
    final task = ChatTask.create(parentId: parent.id);
    _tasks.insert(0, task);
    _openTask(task);
  }

  void _openTask(ChatTask task, {bool save = true}) {
    if (_writing || _readingImage || identical(_activeTask, task)) return;
    _drafts[_activeTask.id] = (
      text: _input.text,
      action: _task,
      photos: _attachedPhotos.toList(),
    );
    final draft = _drafts.remove(task.id);
    _focus.unfocus();
    setState(() {
      _activeTask = task;
      _task = draft?.action;
      _input.text = draft?.text ?? '';
      _attachedPhotos
        ..clear()
        ..addAll(draft?.photos ?? const []);
    });
    _toLatest(force: true);
    if (save) unawaited(_save());
  }

  Future<void> _renameTask(ChatTask task) async {
    var name = task.title;
    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('작업 이름 바꾸기'),
        content: TextFormField(
          initialValue: name,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: '작업 이름'),
          onChanged: (value) => name = value,
          onFieldSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, name.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (!mounted ||
        updated == null ||
        updated.isEmpty ||
        !_tasks.contains(task)) {
      return;
    }
    setState(() => task.name = updated);
    await _save();
  }

  Future<void> _editResponseStyle({ChatTask? task}) async {
    final initial = task == null ? _assistantStyle : task.responseStyle;
    final value = await showDialog<String>(
      context: context,
      anchorPoint: MediaQuery.sizeOf(context).topRight(Offset.zero),
      builder: (context) =>
          ResponseStyleDialog(initial: initial, forTask: task != null),
    );
    if (!mounted || value == null || (task != null && !_tasks.contains(task))) {
      return;
    }
    final style = value.isEmpty ? null : value;
    if (style == initial) return;
    setState(() {
      if (task == null) {
        _assistantStyle = style;
      } else {
        task.responseStyle = style;
      }
    });
    await _save();
  }

  Future<void> _openSettings() async {
    if (_writing || _readingImage) return;
    var manual = _manualSize;
    final memory = _deviceMemory;
    final picked = await showDialog<({GenerationSize? size})>(
      context: context,
      anchorPoint: MediaQuery.sizeOf(context).topRight(Offset.zero),
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final size = manual ?? _recommendedSize;
          return AlertDialog(
            insetPadding: const EdgeInsets.all(24),
            title: const Text('사용자 설정'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: _assistantPortrait(38),
                    title: const Text(
                      '프로필 사진',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: TextButton(
                      onPressed: _readingImage
                          ? null
                          : () async {
                              final operation = _changeAssistantAvatar();
                              update(() {});
                              await operation;
                              if (context.mounted) update(() {});
                            },
                      child: const Text('사진 바꾸기'),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('내 AI의 답변 방식'),
                    subtitle: Text(
                      _assistantStyle ?? '말투와 답변 형식 선택',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      await _editResponseStyle();
                      if (context.mounted) update(() {});
                    },
                  ),
                  const Divider(height: 20),
                  if (_updater?.isAvailable ?? false)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('앱 업데이트'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => showDialog<void>(
                        context: context,
                        anchorPoint: MediaQuery.sizeOf(
                          context,
                        ).topRight(Offset.zero),
                        builder: (context) =>
                            AppUpdateDialog(updater: _updater),
                      ),
                    ),
                  Text(
                    memory == null
                        ? (kIsWeb ? '웹 미리보기 기본값 · 보통' : '자동 추천 · 작게')
                        : 'RAM ${(memory.totalBytes / 1e9).toStringAsFixed(1)}GB · '
                              '사용 가능 ${(memory.availableBytes / 1e9).toStringAsFixed(1)}GB',
                  ),
                  SwitchListTile(
                    title: const Text('기기에 맞게 자동 설정'),
                    contentPadding: EdgeInsets.zero,
                    value: manual == null,
                    onChanged: (automatic) => update(() {
                      manual = automatic ? null : _recommendedSize;
                    }),
                  ),
                  SegmentedButton<GenerationSize>(
                    segments: [
                      for (final item in GenerationSize.values)
                        ButtonSegment(value: item, label: Text(item.label)),
                    ],
                    selected: {size},
                    onSelectionChanged: (selection) =>
                        update(() => manual = selection.single),
                  ),
                  const SizedBox(height: 14),
                  Text('입력 최대 ${size.prompt}토큰 · 답변 최대 ${size.reply}토큰'),
                  const SizedBox(height: 6),
                  const Text('이미지에서 읽은 글자도 입력 한도에 포함돼요.'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, (size: manual)),
                child: const Text('저장'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || picked == null || picked.size == _manualSize || _writing) {
      return;
    }
    final updated = picked.size ?? _recommendedSize;
    final reload = !kIsWeb && _installed && _kanana?.size != updated;
    final previous = reload ? _kanana : null;
    setState(() {
      _manualSize = picked.size;
      if (reload) {
        _kanana = null;
        _status = _ModelStatus.loading;
      }
    });
    await _save();
    if (!reload) return;
    try {
      await previous?.dispose();
      if (mounted) await _loadModel();
    } on Object catch (error) {
      _modelFailure(error, '모델을 다시 열 수 없어요.');
    }
  }

  Future<void> _deleteTask(ChatTask task) async {
    final removedIds = {
      task.id,
      for (final child in _tasks)
        if (child.parentId == task.id) child.id,
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('작업을 삭제할까요?'),
        content: Text(
          removedIds.length > 1
              ? '‘${task.title}’과 하위 대화가 함께 삭제돼요.'
              : '‘${task.title}’의 대화가 삭제돼요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _writing || _readingImage) return;
    if (removedIds.contains(_activeTask.id)) {
      final next = _tasks
          .where((item) => !removedIds.contains(item.id))
          .firstOrNull;
      _openTask(next ?? ChatTask.create(), save: false);
      if (!_tasks.contains(_activeTask)) _tasks.insert(0, _activeTask);
    }
    setState(() {
      _tasks.removeWhere((item) => removedIds.contains(item.id));
      _drafts.removeWhere((id, _) => removedIds.contains(id));
    });
    await _save();
  }

  Future<void> _confirmClearData(BuildContext from) async {
    final history = _history;
    if (history == null || _writing || _readingImage) return;
    var clearing = false;
    await showDialog<void>(
      context: from,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (context, update) => PopScope(
          canPop: !clearing,
          child: AlertDialog(
            title: const Text('저장된 데이터를 삭제할까요?'),
            content: const Text('모든 대화, 첨부 사진, 작성 중인 내용과 사용자 지정 프로필을 지워요.'),
            actions: [
              TextButton(
                onPressed: clearing ? null : () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: clearing
                    ? null
                    : () async {
                        update(() => clearing = true);
                        final message = await _clearData(history);
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        if (from.mounted) Navigator.pop(from);
                        _notify(message);
                      },
                child: Text(clearing ? '삭제 중' : '모두 삭제'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String> _clearData(ChatHistory history) async {
    final task = ChatTask.create();
    try {
      final photosCleared = await history.clear(
        task.id,
        generationSize: _manualSize,
      );
      if (mounted) {
        _focus.unfocus();
        _taskSearchFocus.unfocus();
        setState(() {
          _activeTask = task;
          _tasks
            ..clear()
            ..add(task);
          _drafts.clear();
          _attachedPhotos.clear();
          _input.clear();
          _taskSearch.clear();
          _task = null;
          _assistantName = defaultAssistantName;
          _assistantAvatar = null;
          _assistantStyle = null;
        });
      }
      return photosCleared
          ? '저장된 데이터를 삭제했어요.'
          : '첨부 사진을 모두 지우지 못했어요. 다시 시도해 주세요.';
    } on Object catch (error) {
      debugPrint('History clear failure: ${error.runtimeType}');
      return '데이터를 지우지 못했어요. 다시 시도해 주세요.';
    }
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
      if (!mounted || !_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (force || MediaQuery.disableAnimationsOf(context)) {
        _followTarget = null;
        _scroll.jumpTo(target);
      } else if (_followTarget != target &&
          _scroll.position.extentAfter > 0.5) {
        _followTarget = target;
        unawaited(
          _scroll.animateTo(
            target,
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      _layoutChannel.setMethodCallHandler(null);
    }
    _store?.pause();
    _ads?.dispose();
    _previewDownload?.cancel();
    final model = _kanana;
    if (model != null) unawaited(model.dispose());
    _scroll.dispose();
    _taskSearch.dispose();
    _taskSearchFocus.dispose();
    _focus.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (_status != _ModelStatus.ready) {
        return _screenTransition(
          context,
          Scaffold(
            key: const ValueKey('setup'),
            body: SafeArea(child: _setupScreen()),
          ),
        );
      }
      final safeArea = MediaQuery.paddingOf(context);
      final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
      final layout = WorkspaceLayout.fit(
        size: constraints.biggest,
        safeArea: safeArea,
        features: MediaQuery.displayFeaturesOf(context),
        compactWidth: _iosCompactWidth,
        keyboardHeight: keyboardHeight,
        toolbarEdge: _iosToolbarEdge,
        systemToolbarFrame: _iosToolbarFrame,
      );
      final toolbarFrame = layout.sideToolbarFrame;
      return _screenTransition(
        context,
        Scaffold(
          key: const ValueKey('workspace'),
          drawer: layout.showsSidebar
              ? null
              : Drawer(
                  width: 298,
                  backgroundColor: _mint,
                  child: SafeArea(
                    child: Builder(
                      builder: (context) => _taskMenu(
                        close: Scaffold.of(context).closeDrawer,
                        short: layout.short,
                      ),
                    ),
                  ),
                ),
          body: Builder(
            builder: (context) {
              final openMenu = layout.showsSidebar
                  ? null
                  : Scaffold.of(context).openDrawer;
              return Stack(
                fit: StackFit.expand,
                children: [
                  SafeArea(
                    child: Padding(
                      padding: layout.sideToolbarInsets,
                      child: Row(
                        textDirection: TextDirection.ltr,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: layout.sidebarWidth,
                            child: layout.showsSidebar
                                ? _taskMenu(short: layout.short)
                                : null,
                          ),
                          VerticalDivider(
                            width: layout.sidebarGap,
                            color: _line,
                          ),
                          Expanded(
                            child: Padding(
                              padding: layout.chatInsets,
                              child: _workspace(
                                layout: layout,
                                openMenu: toolbarFrame == null
                                    ? openMenu
                                    : null,
                                sideToolbar: toolbarFrame != null,
                                keyboardVisible: keyboardHeight > 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (toolbarFrame != null)
                    Positioned.fromRect(
                      rect: toolbarFrame,
                      child: _sideToolbar(openMenu),
                    ),
                ],
              );
            },
          ),
        ),
      );
    },
  );

  Widget _screenTransition(BuildContext context, Widget screen) =>
      AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 210),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: screen,
      );

  Widget _taskMenu({VoidCallback? close, required bool short}) {
    final busy = _writing || _readingImage;
    final query = _taskSearch.text.trim().toLowerCase();
    final visible = <ChatTask>[];
    for (final parent in _tasks.where((task) => task.parentId == null)) {
      final parentMatches = query.isEmpty || _matchesTask(parent, query);
      final children = _tasks.where(
        (task) =>
            task.parentId == parent.id &&
            (parentMatches || _matchesTask(task, query)),
      );
      if (parentMatches || children.isNotEmpty) {
        visible
          ..add(parent)
          ..addAll(children);
      }
    }
    return ColoredBox(
      color: const Color(0xffeaf0e4),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, short ? 4 : 16, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!short)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 0, 12),
                child: Row(
                  children: [
                    const _AppMark(),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '내 작업',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (close != null)
                      IconButton(
                        tooltip: '작업 메뉴 닫기',
                        onPressed: close,
                        icon: Icon(
                          _controlIcon(
                            Icons.close_rounded,
                            CupertinoIcons.xmark,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () {
                            _newTask();
                            close?.call();
                          },
                    icon: Icon(
                      _controlIcon(Icons.add_rounded, CupertinoIcons.plus),
                    ),
                    label: const Text('새 작업'),
                  ),
                ),
                if (short && close != null)
                  IconButton(
                    tooltip: '작업 메뉴 닫기',
                    onPressed: close,
                    icon: Icon(
                      _controlIcon(Icons.close_rounded, CupertinoIcons.xmark),
                    ),
                  ),
              ],
            ),
            SizedBox(height: short ? 4 : 12),
            TextField(
              controller: _taskSearch,
              groupId: _taskSearch,
              focusNode: _taskSearchFocus,
              onTapUpOutside: (_) => _taskSearchFocus.unfocus(),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: Icon(
                  _controlIcon(Icons.search_rounded, CupertinoIcons.search),
                  size: 18,
                ),
                hintText: '대화 검색',
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '검색 지우기',
                        onPressed: () => setState(_taskSearch.clear),
                        icon: Icon(
                          _controlIcon(
                            Icons.close_rounded,
                            CupertinoIcons.xmark,
                          ),
                          size: 17,
                        ),
                      ),
              ),
            ),
            if (!short)
              Padding(
                padding: const EdgeInsets.fromLTRB(7, 20, 7, 8),
                child: Text(
                  query.isEmpty ? '최근 작업' : '검색 결과',
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Expanded(
              child: visible.isEmpty
                  ? const Center(child: Text('일치하는 대화가 없어요.'))
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final task = visible[index];
                        final child = task.parentId != null;
                        final match = query.isEmpty
                            ? null
                            : task.messages
                                  .where(
                                    (message) => message.displayText
                                        .toLowerCase()
                                        .contains(query),
                                  )
                                  .firstOrNull;
                        return ListTile(
                          key: ValueKey(task.id),
                          selected: identical(task, _activeTask),
                          selectedTileColor: const Color(0xffd7e6d6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: EdgeInsets.only(left: child ? 24 : 6),
                          horizontalTitleGap: 7,
                          minLeadingWidth: 26,
                          leading: Image.asset(
                            'assets/tasks/conversation.webp',
                            width: child ? 21 : 26,
                            fit: BoxFit.contain,
                            excludeFromSemantics: true,
                          ),
                          title: Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: match == null
                              ? null
                              : Text(
                                  match.displayText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: busy
                              ? null
                              : () {
                                  _openTask(task);
                                  close?.call();
                                },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!child)
                                IconButton(
                                  tooltip: '하위 대화 추가',
                                  color: _pine,
                                  onPressed: busy
                                      ? null
                                      : () {
                                          _newChildTask(task);
                                          close?.call();
                                        },
                                  icon: Icon(
                                    _controlIcon(
                                      Icons.add_rounded,
                                      CupertinoIcons.plus,
                                    ),
                                    size: 21,
                                  ),
                                ),
                              PopupMenuButton<_TaskMenuAction>(
                                tooltip: '작업 옵션',
                                enabled: !busy,
                                onSelected: (action) {
                                  switch (action) {
                                    case _TaskMenuAction.responseStyle:
                                      unawaited(_editResponseStyle(task: task));
                                    case _TaskMenuAction.rename:
                                      unawaited(_renameTask(task));
                                    case _TaskMenuAction.delete:
                                      unawaited(_deleteTask(task));
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: _TaskMenuAction.responseStyle,
                                    child: Text('답변 방식 설정'),
                                  ),
                                  const PopupMenuItem(
                                    value: _TaskMenuAction.rename,
                                    child: Text('이름 바꾸기'),
                                  ),
                                  const PopupMenuItem(
                                    value: _TaskMenuAction.delete,
                                    child: Text('삭제'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  bool _matchesTask(ChatTask task, String query) =>
      task.title.toLowerCase().contains(query) ||
      task.messages.any(
        (message) => message.displayText.toLowerCase().contains(query),
      );

  Widget _setupScreen() {
    final loading = switch (_status) {
      _ModelStatus.checking => '모이챗을 준비하고 있어요',
      _ModelStatus.verifying => '모델 파일을 확인하고 있어요',
      _ModelStatus.loading => kIsWeb ? '미리보기를 준비하고 있어요' : 'Kanana를 여는 중이에요',
      _ => null,
    };
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _MoyiIllustration(width: 152),
                    const SizedBox(height: 12),
                    const Text(
                      '모이챗',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (loading == null) ...[
                      _modelCard(),
                      if (_status != _ModelStatus.downloading)
                        TextButton(
                          onPressed: _openSettings,
                          child: const Text('사용자 설정'),
                        ),
                    ] else
                      _loadingScreen(loading),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _workspace({
    required WorkspaceLayout layout,
    required VoidCallback? openMenu,
    required bool sideToolbar,
    required bool keyboardVisible,
  }) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 780),
      child: Column(
        children: [
          Expanded(
            child: Column(
              children: [
                _header(
                  openMenu: openMenu,
                  sideToolbar: sideToolbar,
                  short: layout.short,
                ),
                const Divider(height: 1, color: _line),
                if (!layout.short && _parentTask != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: _parentLink(_parentTask!),
                  ),
                if (!layout.short && !keyboardVisible) _banner(),
                Expanded(
                  child: _taskTransition(
                    ListView(
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(
                        _workspaceGutter,
                        layout.short ? 8 : 20,
                        _workspaceGutter,
                        16,
                      ),
                      children: [
                        if (layout.short && _parentTask != null)
                          _parentLink(_parentTask!),
                        if (_messages.isEmpty) _welcome(),
                        if (_messages.isEmpty)
                          _taskGrid(keyboardVisible: keyboardVisible),
                        for (final message in _messages) _bubble(message),
                        if (_writing)
                          if (_reply.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 8,
                                bottom: 12,
                              ),
                              child: Text(
                                _summarizing
                                    ? '이전 대화를 정리하고 있어요…'
                                    : kIsWeb
                                    ? '샘플 답변을 준비하고 있어요…'
                                    : '$_assistantName · 답변 준비 중…',
                                style: const TextStyle(color: _muted),
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
                ),
              ],
            ),
          ),
          SizedBox(height: layout.foldGap),
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: layout.composerHeight),
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: 1,
              child: TextFieldTapRegion(
                groupId: _input,
                child: _composer(short: layout.short),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _parentLink(ChatTask parent) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: _writing || _readingImage ? null : () => _openTask(parent),
      icon: Image.asset(
        'assets/tasks/conversation.webp',
        width: 20,
        height: 20,
        excludeFromSemantics: true,
      ),
      label: Text(
        '상위 대화 · ${parent.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );

  Widget _taskTransition(Widget child) => TweenAnimationBuilder<double>(
    key: ValueKey(_activeTask.id),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    tween: Tween(begin: 0, end: 1),
    child: child,
    builder: (context, progress, child) => Opacity(
      opacity: progress,
      child: Transform.translate(
        offset: Offset(0, (1 - progress) * 5),
        child: child,
      ),
    ),
  );

  Widget _loadingScreen(String label) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    ),
  );

  Widget _header({
    required VoidCallback? openMenu,
    required bool sideToolbar,
    required bool short,
  }) => Padding(
    padding: EdgeInsets.fromLTRB(
      openMenu == null ? _workspaceGutter : 8,
      short ? 0 : 8,
      8,
      short ? 0 : 8,
    ),
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          if (openMenu != null) _menuButton(openMenu),
          const _AppMark(),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '모이챗',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
          ),
          if (!short && constraints.maxWidth >= (openMenu == null ? 275 : 335))
            const Text(
              kIsWeb ? '웹 미리보기' : '오프라인 AI',
              style: TextStyle(
                color: _pine,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          if (!sideToolbar) ...[_settingsButton(), _aboutButton()],
        ],
      ),
    ),
  );

  Widget _sideToolbar(VoidCallback? openMenu) => ListView(
    primary: false,
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
    children: [
      if (openMenu != null) _menuButton(openMenu),
      _settingsButton(),
      _aboutButton(),
    ],
  );

  Widget _menuButton(VoidCallback openMenu) => IconButton(
    tooltip: '작업 메뉴',
    onPressed: openMenu,
    icon: Icon(
      _controlIcon(Icons.menu_rounded, CupertinoIcons.line_horizontal_3),
    ),
  );

  Widget _settingsButton() => IconButton(
    tooltip: '사용자 설정',
    onPressed: _writing || _readingImage ? null : _openSettings,
    icon: Icon(_controlIcon(Icons.settings_outlined, CupertinoIcons.gear)),
  );

  Widget _aboutButton() => IconButton(
    tooltip: '앱 정보 및 라이선스',
    icon: Icon(
      _controlIcon(Icons.info_outline_rounded, CupertinoIcons.info_circle),
    ),
    onPressed: _openAppInfo,
  );

  void _openAppInfo() {
    final currentPatch = (_updater?.isAvailable ?? false)
        ? _updater?.readCurrentPatch()
        : null;
    showDialog<void>(
      context: context,
      anchorPoint: MediaQuery.sizeOf(context).topRight(Offset.zero),
      builder: (dialogContext) => AlertDialog(
        insetPadding: const EdgeInsets.all(24),
        scrollable: true,
        title: const Row(
          children: [
            _AppMark(),
            SizedBox(width: 12),
            Expanded(child: Text('모이챗')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('앱 버전 $_appVersion'),
            if (currentPatch != null)
              FutureBuilder<Patch?>(
                future: currentPatch,
                builder: (context, snapshot) => switch (snapshot.data) {
                  final Patch patch => Text('OTA 패치 ${patch.number}'),
                  null => const SizedBox.shrink(),
                },
              ),
            const Divider(height: 24),
            Text('사용 모델', style: Theme.of(dialogContext).textTheme.titleSmall),
            const SizedBox(height: 4),
            const Text('Kanana 1.5 2.1B Instruct'),
            Text(
              '양자화 Q4_K_M',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            TextButton(
              onPressed: () => showPrivacyPolicy(dialogContext),
              child: const Text('개인정보 처리방침'),
            ),
            if (_history != null && !_writing && !_readingImage)
              TextButton(
                onPressed: () => _confirmClearData(dialogContext),
                child: const Text('저장된 데이터 삭제'),
              ),
            if (kIsWeb)
              TextButton(
                onPressed: _writing || _readingImage
                    ? null
                    : () {
                        Navigator.of(dialogContext).pop();
                        _resetPreviewDownload();
                      },
                child: const Text('웹 다운로드 다시 테스트'),
              ),
            if (_ads?.canShowPrivacyOptions ?? false)
              TextButton(
                onPressed: () => unawaited(_ads?.showPrivacyOptions()),
                child: const Text('광고 개인정보 설정'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => showLicensePage(
              context: dialogContext,
              applicationName: '모이챗',
              applicationVersion: _appVersion,
              applicationIcon: const _AppMark(),
            ),
            child: const Text('라이선스 보기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Widget _banner() {
    final ads = _ads;
    if (ads == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: ads,
      builder: (context, _) {
        if (MediaQuery.viewInsetsOf(context).bottom > 0) {
          return const SizedBox.shrink();
        }
        final ad = ads.banner;
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
                  const Text(
                    '광고',
                    style: TextStyle(color: _muted, fontSize: 11),
                  ),
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
  }

  Widget _welcome() => Container(
    margin: const EdgeInsets.only(bottom: 23),
    padding: const EdgeInsets.fromLTRB(18, 19, 12, 19),
    decoration: BoxDecoration(
      color: const Color(0xffeaf0df),
      borderRadius: BorderRadius.circular(25),
      border: Border.all(color: const Color(0xffdce6d2)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final illustrationWidth = (constraints.maxWidth * .34)
            .clamp(64.0, 174.0)
            .toDouble();
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '오늘은 무슨 일을\n도와드릴까요?',
                    style: TextStyle(
                      fontSize: constraints.maxWidth < 310
                          ? 21
                          : constraints.maxWidth < 430
                          ? 27
                          : 36,
                      height: 1.19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.9,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    kIsWeb
                        ? '내 AI를 꾸미고 샘플로 대화해 보세요.'
                        : '나에게 맞는 AI와 오프라인에서도 이어서 대화해요.',
                    style: TextStyle(fontSize: 13, color: _muted, height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            _MoyiIllustration(width: illustrationWidth),
          ],
        );
      },
    ),
  );

  Widget _modelCard() {
    final downloading = _status == _ModelStatus.downloading;
    final checking =
        _status == _ModelStatus.verifying ||
        _status == _ModelStatus.loading ||
        _status == _ModelStatus.checking;
    final title = kIsWeb
        ? downloading
              ? '다운로드 흐름 테스트 중'
              : '다운로드 흐름 테스트'
        : switch (_status) {
            _ModelStatus.downloading => 'Kanana 다운로드 중',
            _ModelStatus.verifying => '모델 파일 확인 중',
            _ModelStatus.loading => 'Kanana 준비 중',
            _ModelStatus.checking => '저장 공간 확인 중',
            _ModelStatus.error => '모델을 준비할 수 없어요',
            _ => '오프라인 AI 준비하기',
          };
    final progress = (_received / (kIsWeb ? _previewBytes : ModelStore.bytes))
        .clamp(0.0, 1.0);
    final speed = _downloadSpeed;
    final rate = speed == null
        ? '속도 계산 중'
        : '${(speed / 1000000).toStringAsFixed(1)} MB/s';
    final details = kIsWeb
        ? downloading
              ? '${(progress * 100).round()}% · '
                    '${(_previewBytes / 18 / _previewTick.inMilliseconds / 1000).toStringAsFixed(1)} MB/s (샘플)'
              : '샘플 다운로드를 완료하면 채팅을 테스트할 수 있어요.'
        : _modelError ??
              (downloading
                  ? '${(_received / 1000000000).toStringAsFixed(2)} / 1.52 GB · $rate'
                  : 'Kanana · 1.52 GB\n한 번 받으면 인터넷 없이 대화할 수 있어요.');
    return Container(
      margin: const EdgeInsets.only(bottom: 23),
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w800,
              fontSize: 19,
            ),
          ),
          const SizedBox(height: 6),
          Text(details, style: const TextStyle(color: _muted, height: 1.55)),
          if (downloading || checking) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: downloading ? progress : null,
              backgroundColor: _mint,
              color: _pine,
              borderRadius: BorderRadius.circular(5),
            ),
          ],
          if (!checking) ...[
            const SizedBox(height: 13),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _pine,
                foregroundColor: Colors.white,
              ),
              onPressed: kIsWeb
                  ? downloading
                        ? _pausePreviewDownload
                        : _requestDownload
                  : downloading
                  ? _store?.pause
                  : _store == null
                  ? _initialize
                  : _installed
                  ? _loadModel
                  : _requestDownload,
              icon: Icon(
                downloading
                    ? _controlIcon(Icons.pause_rounded, CupertinoIcons.pause)
                    : !kIsWeb && (_installed || _store == null)
                    ? _controlIcon(
                        Icons.refresh_rounded,
                        CupertinoIcons.arrow_clockwise,
                      )
                    : _controlIcon(
                        Icons.download_rounded,
                        CupertinoIcons.arrow_down_to_line,
                      ),
              ),
              label: Text(
                downloading
                    ? '일시 정지'
                    : !kIsWeb && (_installed || _store == null)
                    ? '다시 시도'
                    : _received > 0
                    ? '이어받기'
                    : kIsWeb
                    ? '샘플 다운로드'
                    : '모델 다운로드',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _taskGrid({required bool keyboardVisible}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
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
          final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
          final columns = constraints.maxWidth >= 310 && !largeText ? 2 : 1;
          final cardWidth =
              (constraints.maxWidth - (columns - 1) * 10) / columns;
          final tasks = _Task.values;
          return Column(
            children: [
              for (var start = 0; start < tasks.length; start += columns) ...[
                if (start > 0) const SizedBox(height: 10),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final task in tasks.skip(start).take(columns)) ...[
                        if (task != tasks[start]) const SizedBox(width: 10),
                        Expanded(
                          child: _taskCard(
                            task,
                            horizontal: cardWidth >= 195,
                            keyboardVisible: keyboardVisible,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    ],
  );

  Widget _taskCard(
    _Task task, {
    required bool horizontal,
    required bool keyboardVisible,
  }) {
    final picture = Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: task.tint,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: task.illustration(48),
    );
    final caption = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(task.title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(task.detail, style: const TextStyle(color: _muted, fontSize: 12)),
      ],
    );
    final chevron = Icon(
      _controlIcon(Icons.chevron_right_rounded, CupertinoIcons.chevron_right),
      color: _muted,
      size: 16,
    );
    return Material(
      color: _task == task ? task.tint : _surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(19),
        side: const BorderSide(color: _line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(19),
        onTap: _readingImage || _writing
            ? null
            : () => _choose(task, keyboardVisible: keyboardVisible),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: horizontal
              ? Row(
                  children: [
                    picture,
                    const SizedBox(width: 12),
                    Expanded(child: caption),
                    const SizedBox(width: 5),
                    chevron,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [picture, const Spacer(), chevron]),
                    const SizedBox(height: 9),
                    caption,
                  ],
                ),
        ),
      ),
    );
  }

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
              Padding(
                padding: const EdgeInsets.only(bottom: 7, left: 3),
                child: Row(
                  children: [
                    _assistantPortrait(26),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        kIsWeb ? '$_assistantName · 샘플' : _assistantName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _pine,
                          fontWeight: FontWeight.w800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              width: message.isUser ? null : double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              decoration: BoxDecoration(
                color: message.isUser ? _mint : _surface,
                border: Border.all(color: _line),
                borderRadius: BorderRadius.circular(16),
              ),
              child: message.isUser
                  ? _userMessageBody(message)
                  : ReplyMarkdown(text: message.text, streaming: streaming),
            ),
            if (!message.isUser && !streaming)
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: message.text));
                  _notify('답변을 복사했어요.');
                },
                icon: Icon(
                  _controlIcon(Icons.copy_rounded, CupertinoIcons.doc_on_doc),
                  size: 15,
                ),
                label: const Text('복사'),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _userMessageBody(ChatMessage message) {
    final history = _history;
    if (history == null || message.photoIds.isEmpty) {
      return SelectableText(
        message.displayText,
        style: const TextStyle(fontSize: 15, height: 1.58),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (index, id) in message.photoIds.indexed)
              ChatPhotoThumbnail(
                key: ValueKey(id),
                photoId: id,
                number: index + 1,
                load: history.readPhoto,
              ),
          ],
        ),
        if (message.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          SelectableText(
            message.text,
            style: const TextStyle(fontSize: 15, height: 1.58),
          ),
        ],
      ],
    );
  }

  Widget _assistantPortrait(double size) => ClipOval(
    child: SizedBox.square(
      dimension: size,
      child: switch (_assistantAvatar) {
        final bytes? => Image.memory(
          bytes,
          fit: BoxFit.cover,
          semanticLabel: '$_assistantName 프로필 사진',
        ),
        null => ColoredBox(
          color: _mint,
          child: Center(child: _MoyiIllustration(width: size * .88)),
        ),
      },
    ),
  );

  Widget _attachmentChips({required bool short}) {
    final chips = Wrap(
      spacing: 8,
      children: [
        if (_task case final task?)
          InputChip(
            avatar: task.illustration(22),
            label: Text(task.title),
            onDeleted: _writing ? null : () => setState(() => _task = null),
            deleteButtonTooltipMessage: '작업 선택 해제',
          ),
        for (final (index, photo) in _attachedPhotos.indexed)
          InputChip(
            avatar: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image(
                image: ResizeImage.resizeIfNeeded(
                  72,
                  null,
                  _photoPreview(photo),
                ),
                width: 26,
                height: 26,
                fit: BoxFit.cover,
              ),
            ),
            label: Text('이미지 ${index + 1}'),
            onDeleted: _writing
                ? null
                : () => setState(() => _attachedPhotos.removeAt(index)),
            deleteButtonTooltipMessage: '첨부 이미지 제거',
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: short
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: chips,
            )
          : chips,
    );
  }

  Widget _composer({required bool short}) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: _line)),
    ),
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: _workspaceGutter,
        vertical: short ? 4 : 10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_task != null || _attachedPhotos.isNotEmpty)
            _attachmentChips(short: short),
          Container(
            decoration: BoxDecoration(
              color: _surface,
              border: Border.all(color: _line),
              borderRadius: BorderRadius.circular(25),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x10223b2d),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ],
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
                      : Icon(
                          _controlIcon(
                            Icons.add_photo_alternate_outlined,
                            CupertinoIcons.photo,
                          ),
                        ),
                ),
                Expanded(
                  child: TextField(
                    controller: _input,
                    groupId: _input,
                    focusNode: _focus,
                    onTapUpOutside: (_) => _focus.unfocus(),
                    readOnly: _writing,
                    minLines: 1,
                    maxLines: short ? 2 : 4,
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
                              (value.text.trim().isNotEmpty ||
                                  _attachedPhotos.isNotEmpty)
                        ? _send
                        : null,
                    icon: Icon(
                      _writing
                          ? _controlIcon(
                              Icons.stop_rounded,
                              CupertinoIcons.stop_fill,
                            )
                          : _controlIcon(
                              Icons.arrow_upward_rounded,
                              CupertinoIcons.arrow_up,
                            ),
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

class _MoyiIllustration extends StatelessWidget {
  const _MoyiIllustration({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/moyi-notebook.webp',
    width: width,
    height: width * .92,
    fit: BoxFit.contain,
    excludeFromSemantics: true,
  );
}

class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 35,
    height: 35,
    decoration: BoxDecoration(
      color: _mint,
      borderRadius: BorderRadius.circular(11),
    ),
    padding: const EdgeInsets.all(3),
    child: const _MoyiIllustration(width: 29),
  );
}

ImageProvider<Object> _photoPreview(PhotoFindings photo) =>
    switch (photo.imageBytes) {
      final bytes? => MemoryImage(bytes),
      null => const AssetImage('assets/preview-groceries.png'),
    };

class _PhotoReview extends StatefulWidget {
  const _PhotoReview({required this.findings, this.pickLocal});
  final PhotoFindings findings;
  final Future<PhotoFindings?> Function()? pickLocal;

  @override
  State<_PhotoReview> createState() => _PhotoReviewState();
}

class _PhotoReviewState extends State<_PhotoReview> {
  late PhotoFindings _selected = widget.findings;
  bool _picking = false;

  Future<void> _chooseLocal() async {
    setState(() => _picking = true);
    try {
      final image = await widget.pickLocal!();
      if (mounted && image != null) setState(() => _selected = image);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('이미지를 열 수 없어요.')));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '이미지',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: Image(
              image: ResizeImage.resizeIfNeeded(
                900,
                null,
                _photoPreview(_selected),
              ),
              semanticLabel: _selected.imageBytes == null
                  ? '샘플 장보기 목록 이미지'
                  : '첨부할 이미지',
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (widget.pickLocal != null)
          TextButton(
            onPressed: _picking ? null : _chooseLocal,
            child: const Text('내 이미지 선택'),
          ),
        FilledButton(
          onPressed: _picking ? null : () => Navigator.pop(context, _selected),
          child: const Text('이미지 추가하기'),
        ),
      ],
    ),
  );
}
