import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:starflow/features/playback/application/subtitle_content_decoder.dart';
import 'package:file_selector/file_selector.dart';
import 'package:starflow/features/playback/data/subtitle_file_picker.dart';

SubtitleFilePicker createSubtitleFilePicker() {
  return const LocalSubtitleFilePicker();
}

Future<String> readLocalSubtitleText(String path) =>
    compute(_readSubtitleText, path);

String _readSubtitleText(String path) {
  final file = File(path);
  if (file.lengthSync() > maxSubtitleBytes) {
    throw const SubtitleContentException('字幕超过 16 MiB 限制');
  }
  final text = decodeSubtitleBytes(file.readAsBytesSync());
  detectSubtitleFormat(text);
  return text;
}

class LocalSubtitleFilePicker implements SubtitleFilePicker {
  const LocalSubtitleFilePicker();

  @override
  bool get isSupported => true;

  @override
  String get unsupportedReason => '';

  @override
  Future<String?> pickSubtitlePath() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: '字幕',
          extensions: ['srt', 'ass', 'ssa', 'vtt'],
        ),
      ],
      confirmButtonText: '加载这个字幕',
    );
    return file?.path;
  }
}
