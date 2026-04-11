import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_naming.dart';
import 'package:starflow/features/library/domain/nas_media_recognition.dart';

void main() {
  test('NasMediaRecognizer skips wrapper folders when inferring series title',
      () {
    final result = NasMediaRecognizer.recognize(
      '繁城之下/会员版/Episode 01.mkv',
    );

    expect(result.itemType, 'episode');
    expect(result.episodeNumber, 1);
    expect(result.parentTitle, '繁城之下');
    expect(result.title, '繁城之下');
  });

  test('NasMediaRecognizer recognizes variety issue labels as episodes', () {
    final result = NasMediaRecognizer.recognize(
      '食贫道/第12期 会员版.mp4',
    );

    expect(result.itemType, 'episode');
    expect(result.episodeNumber, 12);
    expect(result.parentTitle, '食贫道');
    expect(result.title, '食贫道');
  });

  test('NasMediaRecognizer distinguishes upper and lower variety parts', () {
    final upper = NasMediaRecognizer.recognize(
      '乘风2026/2026.04.03-第1期（上）.mp4',
    );
    final lower = NasMediaRecognizer.recognize(
      '乘风2026/2026.04.04-第1期（下）.mp4',
    );

    expect(upper.itemType, 'episode');
    expect(upper.episodeNumber, 1);
    expect(upper.episodePart, 'upper');
    expect(lower.itemType, 'episode');
    expect(lower.episodeNumber, 1);
    expect(lower.episodePart, 'lower');
  });

  test('NasMediaRecognizer does not attach part tokens to variety specials',
      () {
    final result = NasMediaRecognizer.recognize(
      '乘风2026/2026.04.04-舞台纯享版第1期（上）.mp4',
      specialEpisodeKeywords: const ['舞台纯享版'],
    );

    expect(result.itemType, 'episode');
    expect(result.episodeNumber, 1);
    expect(result.episodePart, isEmpty);
  });

  test('NasMediaRecognizer does not attach part tokens to english extras',
      () {
    final result = NasMediaRecognizer.recognize(
      'Show/2026.04.04-Behind.The.Scenes 第1期（上）.mp4',
      specialEpisodeKeywords: const ['behind the scenes'],
    );

    expect(result.itemType, 'episode');
    expect(result.episodeNumber, 1);
    expect(result.episodePart, isEmpty);
  });

  test(
      'NasMediaRecognizer keeps leading episode cues when remainder is only a version label',
      () {
    final result = NasMediaRecognizer.recognize(
      '奔跑吧/01 会员版 1080p.mkv',
    );

    expect(result.itemType, 'episode');
    expect(result.episodeNumber, 1);
    expect(result.parentTitle, '奔跑吧');
    expect(result.title, '奔跑吧');
  });

  test('NasMediaRecognizer stops upward series inference at filtered folders',
      () {
    final result = NasMediaRecognizer.recognize(
      '怪奇物语/Stranger.Things.S04.2160p.NF.WEB-DL.x265.10bit.HDR/Stranger.Things.S04E01.2160p.NF.WEB-DL.x265.10bit.HDR.strm',
      seriesTitleFilterKeywords: const ['2160p'],
    );

    expect(result.itemType, 'episode');
    expect(result.parentTitle, 'Stranger Things');
    expect(result.title, 'Stranger Things');
  });

  test('NasMediaRecognizer keeps composite season folders under filtered roots',
      () {
    final result = NasMediaRecognizer.recognize(
      'strm/quark/十三邀 第九季/十三邀 第01集.strm',
      seriesTitleFilterKeywords: const ['strm', 'quark'],
    );

    expect(result.itemType, 'episode');
    expect(result.parentTitle, '十三邀 第九季');
    expect(result.title, '十三邀 第九季');
  });

  test(
      'NasMediaRecognizer treats mixed-case resolution wrapper folders as wrappers',
      () {
    final result = NasMediaRecognizer.recognize(
      'movies/strm/quark/拼桌/4k hDr60FpS高码率/2025.2160p.60FpS.HDR.Web-DL.H265.DDP2.0.(mkv).strm',
    );

    expect(result.parentTitle, '拼桌');
    expect(result.preferSeries, isFalse);
  });

  test('NasMediaRecognizer recognizes expanded wrapper tokens from open-source conventions',
      () {
    expect(
      NasMediaRecognizer.matchesWrapperFolderLabel(
        'HdTv 1080i 3D HSBS x265 FLAC Dual Audio',
      ),
      isTrue,
    );
  });

  test('MediaSourceConfig matches expanded extras keywords ignoring case', () {
    const source = MediaSourceConfig(
      id: 'quark-source',
      name: 'Quark',
      kind: MediaSourceKind.quark,
      endpoint: '/quark',
      enabled: true,
    );

    expect(
      source.matchesWebDavSpecialEpisodeKeyword(
        'SHOW/Behind.The.Scenes.Featurette.mp4',
      ),
      isTrue,
    );
    expect(
      source.matchesWebDavSpecialEpisodeKeyword('show/DELETED SCENES.mp4'),
      isTrue,
    );
  });

  test('MediaNaming normalizes expanded release tokens from shared lexicon', () {
    expect(
      MediaNaming.normalizeLookupTitle(
        'Movie.1080i.HDTV.3D.HSBS.x265.FLAC.Dual-Audio',
      ),
      'movie',
    );
  });
}
