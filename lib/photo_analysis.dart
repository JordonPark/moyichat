import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class PhotoAnalysis {
  final _picker = ImagePicker();
  static const _channel = MethodChannel('moyichat/photos');

  Future<PhotoFindings?> pickAndAnalyze() async {
    final image = await _pickImage();
    return image == null ? null : _recognize(image);
  }

  Future<XFile?> _pickImage() => _picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 2400,
    maxHeight: 2400,
    requestFullMetadata: false,
  );

  Future<PhotoFindings?> pickPreviewImage() async {
    final bytes = await pickImageBytes();
    return bytes == null
        ? null
        : PhotoFindings(text: null, labels: null, imageBytes: bytes);
  }

  Future<Uint8List?> pickImageBytes() async {
    final image = await _pickImage();
    if (image == null) return null;
    try {
      return await image.readAsBytes();
    } finally {
      await _removeIosPickerCopy(image);
    }
  }

  Future<PhotoFindings?> recoverInterruptedPick() async {
    final response = await _picker.retrieveLostData();
    if (response.exception case final exception?) throw exception;
    final files = response.files;
    return files == null || files.isEmpty ? null : _recognize(files.first);
  }

  Future<PhotoFindings> _recognize(XFile image) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'analyze',
        image.path,
      );
      return PhotoFindings(
        imageBytes: await image.readAsBytes(),
        text: (result?['text'] as String?)?.trim(),
        labels: (result?['labels'] as List<Object?>?)
            ?.whereType<String>()
            .toList(),
      );
    } finally {
      await _removeIosPickerCopy(image);
    }
  }

  Future<void> _removeIosPickerCopy(XFile image) async {
    // image_picker_ios returns a private temporary copy with this prefix.
    if (kIsWeb || !Platform.isIOS || !image.name.startsWith('image_picker_')) {
      return;
    }
    try {
      await File(image.path).delete();
    } on FileSystemException {
      // A temporary-file cleanup error doesn't affect the selected image.
    }
  }
}

class PhotoFindings {
  const PhotoFindings({
    required this.text,
    required this.labels,
    this.imageBytes,
  });

  // A null field indicates that its recognizer failed.
  final String? text;
  final List<String>? labels;
  final Uint8List? imageBytes;

  String get modelContext {
    final recognizedText = text?.trim() ?? '';
    final objects = (labels ?? const <String>[])
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .where(
          (label) =>
              recognizedText.isEmpty ||
              !const {
                'document',
                'screenshot',
                'screen shot',
              }.contains(label.toLowerCase().replaceAll('_', ' ')),
        )
        .toSet()
        .toList();
    final evidence = {
      if (recognizedText.isNotEmpty) 'text': recognizedText,
      if (objects.isNotEmpty) 'objects': objects,
    };
    return evidence.isEmpty ? '' : jsonEncode(evidence);
  }
}
