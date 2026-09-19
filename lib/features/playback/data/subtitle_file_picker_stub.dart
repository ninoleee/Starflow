import 'package:starflow/features/playback/data/subtitle_file_picker.dart';

Future<String> readLocalSubtitleText(String path) async =>
    throw UnsupportedError('当前平台不支持本地字幕');

SubtitleFilePicker createSubtitleFilePicker() {
  return const UnsupportedSubtitleFilePicker();
}

class UnsupportedSubtitleFilePicker implements SubtitleFilePicker {
  const UnsupportedSubtitleFilePicker();

  @override
  bool get isSupported => false;

  @override
  String get unsupportedReason => '当前平台暂不支持从本地选择字幕文件。';

  @override
  Future<String?> pickSubtitlePath() async {
    return null;
  }
}
