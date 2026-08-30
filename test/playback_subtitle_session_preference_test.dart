import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:starflow/features/playback/application/playback_subtitle_session_preference.dart';

void main() {
  test('matches a selected subtitle across episodes without reusing track id',
      () {
    const previous = SubtitleTrack(
      '3',
      '简体中文',
      'zh-CN',
      codec: 'subrip',
    );
    const nextTracks = <SubtitleTrack>[
      SubtitleTrack('3', 'English', 'en', codec: 'subrip'),
      SubtitleTrack('8', '简体中文', 'zh-CN', codec: 'ass'),
    ];

    final match = matchPlaybackSubtitleTrack(
      nextTracks,
      PlaybackSubtitleTrackFingerprint.fromTrack(previous),
    );

    expect(match?.id, '8');
  });

  test('matches primary and secondary dual subtitles independently', () {
    const primary = SubtitleTrack('1', '中文', 'zh');
    const secondary = SubtitleTrack('2', 'English SDH', 'en');
    const nextTracks = <SubtitleTrack>[
      SubtitleTrack('6', 'English', 'en'),
      SubtitleTrack('7', '简体中文', 'zh-CN'),
    ];
    final preference = PlaybackSubtitleSessionPreference.dual(
      primary: primary,
      secondary: secondary,
    );

    final nextPrimary = matchPlaybackSubtitleTrack(
      nextTracks,
      preference.primary!,
      textOnly: true,
    );
    final nextSecondary = matchPlaybackSubtitleTrack(
      nextTracks,
      preference.secondary!,
      excludedIds: {nextPrimary!.id},
      textOnly: true,
    );

    expect(nextPrimary.id, '7');
    expect(nextSecondary?.id, '6');
  });

  test('does not match an unrelated track only because its codec is equal', () {
    const previous = SubtitleTrack('4', '日本語', 'ja', codec: 'ass');
    const nextTracks = <SubtitleTrack>[
      SubtitleTrack('9', 'English', 'en', codec: 'ass'),
    ];

    final match = matchPlaybackSubtitleTrack(
      nextTracks,
      PlaybackSubtitleTrackFingerprint.fromTrack(previous),
    );

    expect(match, isNull);
  });

  test('does not reuse a stable id when the language clearly changed', () {
    const previous = SubtitleTrack('4', '日本語', 'ja', codec: 'ass');
    const nextTracks = <SubtitleTrack>[
      SubtitleTrack('4', 'English', 'en', codec: 'ass'),
    ];

    final match = matchPlaybackSubtitleTrack(
      nextTracks,
      PlaybackSubtitleTrackFingerprint.fromTrack(previous),
    );

    expect(match, isNull);
  });

  test('uses the title when the next episode language is unknown', () {
    const previous = SubtitleTrack('1', '简体中文', 'zh-CN');
    const nextTracks = <SubtitleTrack>[
      SubtitleTrack('5', 'English', 'und'),
      SubtitleTrack('6', '简体中文', 'und'),
    ];

    final match = matchPlaybackSubtitleTrack(
      nextTracks,
      PlaybackSubtitleTrackFingerprint.fromTrack(previous),
    );

    expect(match?.id, '6');
  });
}
