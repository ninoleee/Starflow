import 'package:file_selector/file_selector.dart';
import 'package:starflow/features/playback/data/subtitle_file_picker.dart';

SubtitleFilePicker createSubtitleFilePicker() {
  return const LocalSubtitleFilePicker();
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
          extensions: ['srt', 'ass', 'ssa', 'vtt', 'sub', 'idx'],
        ),
      ],
      confirmButtonText: '加载这个字幕',
    );
    return file?.path;
  }
}
