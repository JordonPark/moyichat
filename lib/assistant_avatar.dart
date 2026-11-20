import 'dart:typed_data';
import 'dart:ui' as ui;

Future<Uint8List> makeAssistantAvatar(Uint8List source) async {
  final codec = await ui.instantiateImageCodec(
    source,
    targetWidth: 480,
    allowUpscaling: false,
  );
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final side = image.width < image.height ? image.width : image.height;
      final crop = ui.Rect.fromCenter(
        center: ui.Offset(image.width / 2, image.height / 2),
        width: side.toDouble(),
        height: side.toDouble(),
      );
      const size = 160;
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        image,
        crop,
        const ui.Rect.fromLTWH(0, 0, 160, 160),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      final picture = recorder.endRecording();
      try {
        final avatar = await picture.toImage(size, size);
        try {
          final png = await avatar.toByteData(format: ui.ImageByteFormat.png);
          return png!.buffer.asUint8List();
        } finally {
          avatar.dispose();
        }
      } finally {
        picture.dispose();
      }
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
