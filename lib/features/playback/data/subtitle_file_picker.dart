import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/playback/data/subtitle_file_picker_stub.dart'
    if (dart.library.io)
        'package:starflow/features/playback/data/subtitle_file_picker_io.dart'
    as impl;

final subtitleFilePickerProvider = Provider<SubtitleFilePicker>((ref) {
  return impl.createSubtitleFilePicker();
});

abstract class SubtitleFilePicker {
  bool get isSupported;

  String get unsupportedReason;

  Future<String?> pickSubtitlePath();
}
