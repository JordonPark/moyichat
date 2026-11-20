import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class PhotoAnalysis {
  final _picker = ImagePicker();
  static const _channel = MethodChannel('moyichat/photos');

  Future<PhotoFindings?> pickAndAnalyze() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,
      maxHeight: 2400,
      requestFullMetadata: false,
    );
    return image == null ? null : _recognize(image);
  }

  Future<PhotoFindings?> recoverInterruptedPick() async {
    final response = await _picker.retrieveLostData();
    if (response.exception case final exception?) throw exception;
    final files = response.files;
    return files == null || files.isEmpty ? null : _recognize(files.first);
  }

  Future<PhotoFindings> _recognize(XFile image) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'analyze',
      image.path,
    );
    return PhotoFindings(
      text: (result?['text'] as String?)?.trim(),
      labels: (result?['labels'] as List<Object?>?)
          ?.whereType<String>()
          .toList(),
    );
  }
}

class PhotoFindings {
  const PhotoFindings({required this.text, required this.labels});

  // A null field indicates that its recognizer failed.
  final String? text;
  final List<String>? labels;

  bool get hasFindings =>
      (text?.isNotEmpty ?? false) || (labels?.isNotEmpty ?? false);

  String get transcript => [
    if (labels case final values? when values.isNotEmpty)
      '사진 분류 후보\n${values.join(', ')}',
    if (text case final value? when value.isNotEmpty) '사진에서 읽은 글자\n$value',
  ].join('\n\n');
}
