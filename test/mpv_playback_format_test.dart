import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/data/mpv_playback_format.dart';

void main() {
  test('format shows active resolution and codecs without container or bitrate',
      () async {
    final values = {
      'video-params/w': '1920',
      'video-params/h': '1080',
      'file-format': 'matroska,webm',
      'video-format': 'hevc',
      'audio-codec-name': 'aac',
    };
    expect(await readMpvPlaybackFormat((key) async => values[key] ?? ''),
        '1920x1080 · HEVC · AAC');
    values['video-format'] = 'h264';
    values['file-format'] = 'mpegts';
    expect(await readMpvPlaybackFormat((key) async => values[key] ?? ''),
        '1920x1080 · H.264 · AAC');
  });

  test('missing properties omit only unknown fields', () async {
    expect(
        await readMpvPlaybackFormat((key) async {
          if (key == 'video-format') return 'av1';
          throw StateError('Unavailable');
        }),
        'AV1');
    expect(await readMpvPlaybackFormat((_) async => ''), isNull);
  });
}
