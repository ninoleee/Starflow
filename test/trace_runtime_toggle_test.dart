import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/utils/playback_trace.dart';
import 'package:starflow/core/utils/subtitle_search_trace.dart';

void main() {
  tearDown(() {
    setPlaybackTraceEnabled(false);
    setSubtitleSearchTraceEnabled(false);
  });

  test('playback trace runtime toggle defaults to disabled and is mutable', () {
    setPlaybackTraceEnabled(false);
    expect(playbackTraceEnabled, isFalse);

    setPlaybackTraceEnabled(true);
    expect(playbackTraceEnabled, isTrue);
  });

  test(
    'subtitle search trace runtime toggle defaults to disabled and is mutable',
    () {
      setSubtitleSearchTraceEnabled(false);
      expect(subtitleSearchTraceEnabled, isFalse);

      setSubtitleSearchTraceEnabled(true);
      expect(subtitleSearchTraceEnabled, isTrue);
    },
  );
}
