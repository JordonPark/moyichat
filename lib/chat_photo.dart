import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

class ChatPhotoThumbnail extends StatefulWidget {
  const ChatPhotoThumbnail({
    super.key,
    required this.photoId,
    required this.number,
    required this.load,
  });

  final String photoId;
  final int number;
  final Future<Uint8List?> Function(String) load;

  @override
  State<ChatPhotoThumbnail> createState() => _ChatPhotoThumbnailState();
}

class _ChatPhotoThumbnailState extends State<ChatPhotoThumbnail> {
  late final _photo = widget.load(widget.photoId);

  @override
  Widget build(BuildContext context) {
    const unavailable = Center(
      child: Text('사진을 열 수 없어요.', textAlign: TextAlign.center),
    );
    return SizedBox(
      width: 156,
      height: 116,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: FutureBuilder<Uint8List?>(
            future: _photo,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: Icon(Icons.add_photo_alternate_outlined),
                );
              }
              final bytes = snapshot.data;
              if (bytes == null) return unavailable;
              return Semantics(
                label: '사진 ${widget.number} 확대',
                button: true,
                child: InkWell(
                  onTap: () => _openPhoto(context, bytes),
                  child: Image.memory(
                    bytes,
                    cacheWidth: (156 * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                    errorBuilder: (_, _, _) => unavailable,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _openPhoto(BuildContext context, Uint8List bytes) {
    final box = context.findRenderObject() as RenderBox;
    showDialog<void>(
      context: context,
      anchorPoint: box.localToGlobal(box.size.center(Offset.zero)),
      barrierColor: Colors.transparent,
      useSafeArea: false,
      builder: (_) => _ChatPhotoViewer(
        bytes: bytes,
        number: widget.number,
        thumbnailBounds: () => box.attached && box.hasSize
            ? box.localToGlobal(Offset.zero) & box.size
            : null,
      ),
    );
  }
}

class _ChatPhotoViewer extends StatefulWidget {
  const _ChatPhotoViewer({
    required this.bytes,
    required this.number,
    required this.thumbnailBounds,
  });

  final Uint8List bytes;
  final int number;
  final Rect? Function() thumbnailBounds;

  @override
  State<_ChatPhotoViewer> createState() => _ChatPhotoViewerState();
}

class _ChatPhotoViewerState extends State<_ChatPhotoViewer>
    with SingleTickerProviderStateMixin {
  final _viewport = GlobalKey();
  final _transformation = TransformationController();
  late final _settle = AnimationController(vsync: this);
  Offset? _dragStart;
  double _dragDistance = 0;
  bool _closing = false;
  Rect? _destination;

  @override
  void dispose() {
    _settle.dispose();
    _transformation.dispose();
    super.dispose();
  }

  void _startDrag(ScaleStartDetails details) {
    final atOriginalScale = _transformation.value.getMaxScaleOnAxis() <= 1.001;
    if (!_closing &&
        !_settle.isAnimating &&
        atOriginalScale &&
        details.pointerCount == 1) {
      _dragStart = details.focalPoint;
    }
  }

  void _updateDrag(ScaleUpdateDetails details) {
    final start = _dragStart;
    if (start == null || details.pointerCount != 1) return;

    final delta = details.focalPoint - start;
    if (_dragDistance == 0 && delta.dy <= delta.dx.abs()) return;
    setState(() => _dragDistance = math.max(0, delta.dy));
  }

  void _endDrag(ScaleEndDetails details) {
    _dragStart = null;
    if (_dragDistance == 0 || _settle.isAnimating || _closing) return;

    final viewport = _viewport.currentContext!.findRenderObject() as RenderBox;
    final threshold = (viewport.size.height * .18).clamp(76.0, 140.0);
    final velocity = details.velocity.pixelsPerSecond;
    final flickedDown =
        _dragDistance >= 28 &&
        velocity.dy >= 850 &&
        velocity.dy > velocity.dx.abs();
    // The scale recognizer also ends its current gesture when a finger joins.
    final dismiss =
        details.pointerCount == 0 &&
        (_dragDistance >= threshold || flickedDown);
    if (dismiss) {
      final thumbnail = widget.thumbnailBounds();
      final origin = viewport.localToGlobal(Offset.zero);
      if (thumbnail != null && (origin & viewport.size).overlaps(thumbnail)) {
        _destination = thumbnail.shift(-origin);
      }
    }
    _finishDrag(dismiss: dismiss);
  }

  Future<void> _finishDrag({required bool dismiss}) async {
    _closing = dismiss;
    _settle.duration = Duration(milliseconds: dismiss ? 240 : 190);
    try {
      await _settle.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;
    if (dismiss && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.pop(context);
      return;
    }
    _closing = false;
    _dragDistance = 0;
    _destination = null;
    _settle.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: AnimatedBuilder(
        animation: _settle,
        child: Image.memory(
          widget.bytes,
          fit: BoxFit.contain,
          semanticLabel: '사진 ${widget.number}',
          errorBuilder: (_, _, _) => const Center(
            child: Text('사진을 열 수 없어요.', style: TextStyle(color: Colors.white)),
          ),
        ),
        builder: (context, photo) {
          final progress = Curves.easeOutCubic.transform(_settle.value);
          final distance = _dragDistance * (_closing ? 1 : 1 - progress);
          final pull = (distance / 400).clamp(0.0, 1.0);
          final backdropOpacity =
              (1 - .7 * pull) * (_closing ? 1 - progress : 1);
          return ColoredBox(
            color: Colors.black.withValues(alpha: backdropOpacity),
            child: SafeArea(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  InteractiveViewer(
                    key: _viewport,
                    transformationController: _transformation,
                    maxScale: 5,
                    onInteractionStart: _startDrag,
                    onInteractionUpdate: _updateDrag,
                    onInteractionEnd: _endDrag,
                    child: LayoutBuilder(
                      builder: (context, bounds) => Stack(
                        children: [
                          Positioned.fromRect(
                            rect: _photoBounds(
                              bounds.biggest,
                              distance,
                              pull,
                              progress,
                            ),
                            child: Opacity(
                              opacity: _closing ? 1 - progress * progress : 1,
                              child: photo,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Opacity(
                      opacity: backdropOpacity,
                      child: IconButton.filled(
                        tooltip: '사진 닫기',
                        style: IconButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.black54,
                        ),
                        onPressed: _closing
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Rect _photoBounds(Size size, double distance, double pull, double progress) {
    final scale = 1 - .45 * pull;
    final pulled = Rect.fromCenter(
      center: size.center(Offset(0, distance)),
      width: size.width * scale,
      height: size.height * scale,
    );
    if (!_closing) return pulled;
    final target =
        _destination ??
        Rect.fromCenter(
          center: pulled.center + const Offset(0, 80),
          width: pulled.width * .4,
          height: pulled.height * .4,
        );
    return Rect.lerp(pulled, target, progress)!;
  }
}
