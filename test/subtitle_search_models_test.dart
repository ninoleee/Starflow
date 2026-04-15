import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/online_subtitle_search_request_builder.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

void main() {
  test('subtitle search prefers cleaned file name and keeps episode token', () {
    const target = PlaybackTarget(
      title: '你要为了一个虚名而嫁给我？',
      sourceId: 'nas-main',
      streamUrl:
          'https://example.com/21%E4%B8%96%E7%BA%AA%E5%A4%A7%E5%90%9B%E5%A4%AB%E4%BA%BA.S01E02.2160p.WEB-DL.H265.10bit.DDP5.1&DTS5.1.(mkv).strm',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
      itemType: 'episode',
      seriesTitle: '21世纪大君夫人',
      seasonNumber: 1,
      episodeNumber: 2,
    );

    expect(buildSubtitleSearchFileName(target), '21世纪大君夫人 S01E02');
    expect(buildSubtitleSearchQuery(target), '21世纪大君夫人 S01E02');
    expect(buildSubtitleSearchInitialInput(target), '21世纪大君夫人 S01E02');
  });

  test('route builder keeps remote file path for subtitle file name matching',
      () async {
    const request = SubtitleSearchRequest(
      query: 'Stranger Things S01E01',
      title: '怪奇物语',
      filePath:
          'https://example.com/Stranger.Things.S01E01.2160p.WEB-DL.H265.10bit.(mkv).strm',
    );

    final built = await buildOnlineSubtitleSearchRequestForRoute(request);

    expect(built.filePath, request.filePath);
  });

  test('episode scoring prefers the currently playing episode file', () {
    final currentScore = scoreSubtitleEpisodeMatch(
      'Stranger.Things.S01E02.720p.BluRay.x264.DD5.1-HDChina.srt',
      seasonNumber: 1,
      episodeNumber: 2,
    );
    final otherScore = scoreSubtitleEpisodeMatch(
      'Stranger.Things.S01E01.720p.BluRay.x264.DD5.1-HDChina.srt',
      seasonNumber: 1,
      episodeNumber: 2,
    );

    expect(currentScore, greaterThan(otherScore));
  });
}
