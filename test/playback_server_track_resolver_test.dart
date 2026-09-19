import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_server_track_resolver.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  const target = PlaybackTarget(
    title: 'Show',
    sourceId: 'fntv',
    streamUrl: 'https://nas/v/api/v1/media/range/file',
    sourceName: 'FNTV',
    sourceKind: MediaSourceKind.fntv,
    itemId: 'episode',
    preferredAudioStreamId: 'audio-zh',
    preferredSubtitleStreamId: 'subtitle-external',
    audioStreams: [
      PlaybackAudioStream(
        id: 'audio-en',
        title: 'English',
        language: 'en',
        codec: 'eac3',
        channels: 6,
        index: 1,
      ),
      PlaybackAudioStream(
        id: 'audio-zh',
        title: '国语',
        language: 'zh',
        codec: 'aac',
        channels: 2,
        isDefault: true,
        index: 0,
      ),
    ],
    subtitleStreams: [
      PlaybackSubtitleStream(
        id: 'subtitle-embedded',
        title: '简体中文',
        language: 'zh',
        codec: 'ass',
        isDefault: true,
        index: 0,
      ),
      PlaybackSubtitleStream(
        id: 'subtitle-external',
        title: 'English',
        language: 'en',
        codec: 'srt',
        isExternal: true,
        index: 1,
      ),
    ],
  );

  test('resolves preferred audio by stream identity and ordinal', () {
    const english = AudioTrack(
      '1',
      'English',
      'en',
      codec: 'eac3',
      channelscount: 6,
    );
    const mandarin = AudioTrack(
      '0',
      '国语',
      'zh',
      codec: 'aac',
      channelscount: 2,
    );

    expect(
      resolvePlaybackAudioTrack(
        target: target,
        tracks: const [english, mandarin],
      )?.id,
      '0',
    );
    expect(
      matchPlaybackAudioStreamForTrack(
        target: target,
        tracks: const [english, mandarin],
        track: english,
      )?.id,
      'audio-en',
    );
  });

  test('missing audio metadata does not prevent subtitle resolution', () {
    final withoutAudio = target.copyWith(audioStreams: const []);
    expect(preferredPlaybackAudioStream(withoutAudio), isNull);
    expect(resolvePlaybackAudioTrack(target: withoutAudio, tracks: const []),
        isNull);
    expect(
        preferredPlaybackSubtitleStream(withoutAudio)?.id, 'subtitle-external');
    expect(
        preferredPlaybackSubtitleStream(
            target.copyWith(subtitleStreams: const [])),
        isNull);
  });

  test(
      'language aliases resolve reordered tracks without guessing missing rows',
      () {
    const english =
        AudioTrack('1', 'English', 'eng', codec: 'eac3', channelscount: 6);
    const chinese =
        AudioTrack('2', '国语', 'zho', codec: 'aac', channelscount: 2);
    expect(
        resolvePlaybackAudioTrack(
            target: target, tracks: const [english, chinese]),
        chinese);
    expect(
        resolvePlaybackAudioTrack(
            target: target, tracks: const [AudioTrack('1', null, null)]),
        isNull);
  });

  test(
      'ambiguous reverse audio matching uses ordinal, not first language match',
      () {
    final duplicate = target.copyWith(audioStreams: const [
      PlaybackAudioStream(
          id: 'a',
          title: 'English',
          language: 'en',
          codec: 'aac',
          channels: 2,
          index: 0),
      PlaybackAudioStream(
          id: 'b',
          title: 'English',
          language: 'en',
          codec: 'aac',
          channels: 2,
          index: 1),
    ]);
    const tracks = [
      AudioTrack('1', 'English', 'eng', codec: 'aac'),
      AudioTrack('2', 'English', 'eng', codec: 'aac')
    ];
    expect(
        matchPlaybackAudioStreamForTrack(
                target: duplicate, tracks: tracks, track: tracks[1])
            ?.id,
        'b');
  });

  test('resolves embedded subtitle and leaves external subtitle for download',
      () {
    const chinese = SubtitleTrack(
      '0',
      '简体中文',
      'zh',
      codec: 'ass',
    );
    const english = SubtitleTrack(
      '1',
      'English',
      'en',
      codec: 'subrip',
    );

    expect(
      resolveEmbeddedPlaybackSubtitleTrack(
        target: target.copyWith(
          preferredSubtitleStreamId: 'subtitle-embedded',
        ),
        tracks: const [chinese, english],
      )?.id,
      '0',
    );
    expect(
      resolveEmbeddedPlaybackSubtitleTrack(
        target: target,
        tracks: const [chinese, english],
      ),
      isNull,
    );
    expect(
      preferredPlaybackSubtitleStream(target)?.isExternal,
      isTrue,
    );
  });
}
