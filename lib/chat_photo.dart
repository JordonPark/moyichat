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
                return const Center(child: Icon(Icons.image_outlined));
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
      useSafeArea: false,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                maxScale: 5,
                child: SizedBox.expand(
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    semanticLabel: '사진 ${widget.number}',
                    errorBuilder: (_, _, _) => const Center(
                      child: Text(
                        '사진을 열 수 없어요.',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: IconButton.filled(
                    tooltip: '사진 닫기',
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.black54,
                    ),
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
