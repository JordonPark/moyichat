import 'package:flutter/services.dart';

enum GenerationSize {
  small('작게', 1536, 600, 192),
  normal('보통', 2048, 1000, 384),
  large('많음', 3072, 1800, 640);

  const GenerationSize(this.label, this.context, this.prompt, this.reply);

  final String label;
  final int context;
  final int prompt;
  final int reply;
}

class DeviceMemory {
  const DeviceMemory({
    required this.totalBytes,
    required this.availableBytes,
    this.lowMemory = false,
  });

  final int totalBytes;
  final int availableBytes;
  final bool lowMemory;

  GenerationSize get recommended {
    if (lowMemory || totalBytes < 3800000000 || availableBytes < 1000000000) {
      return GenerationSize.small;
    }
    if (totalBytes >= 5800000000 && availableBytes >= 2300000000) {
      return GenerationSize.large;
    }
    return GenerationSize.normal;
  }

  static Future<DeviceMemory?> read() async {
    const channel = MethodChannel('moyichat/device');
    try {
      final value = await channel.invokeMapMethod<String, Object?>('memory');
      if (value == null) return null;
      return DeviceMemory(
        totalBytes: value['total'] as int,
        availableBytes: value['available'] as int,
        lowMemory: value['low'] as bool? ?? false,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
