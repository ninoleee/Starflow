import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/application/playback_episode_browser.dart';
import 'package:starflow/features/playback/application/playback_episode_queue_resolver.dart';
import 'package:starflow/features/playback/domain/playback_episode_queue.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';

const target = PlaybackTarget(
    title: 'Episode',
    sourceId: 'source',
    sourceName: 'NAS',
    sourceKind: MediaSourceKind.nas,
    streamUrl: '');
const season = PlaybackEpisodeSeason(id: 'season-2', number: 2, title: '第 2 季');

class FakeResolver extends PlaybackEpisodeQueueResolver {
  FakeResolver() : super(read: <T>(provider) => throw UnimplementedError());
  int seasonCalls = 0;
  int queueCalls = 0;
  bool fail = false;
  @override
  Future<List<PlaybackEpisodeSeason>> loadSeasons(PlaybackTarget target) async {
    seasonCalls++;
    if (fail) throw StateError('offline');
    return [season];
  }

  @override
  Future<PlaybackEpisodeQueue> loadSeason(
      PlaybackTarget target, PlaybackEpisodeSeason season) async {
    queueCalls++;
    if (fail) throw StateError('offline');
    return const PlaybackEpisodeQueue(entries: [], currentIndex: -1);
  }
}

void main() {
  test('metadata and in-flight season requests are cached per browser',
      () async {
    final resolver = FakeResolver();
    final browser = PlaybackEpisodeBrowser(resolver: resolver, target: target);
    await Future.wait([browser.loadSeasons(), browser.loadSeasons()]);
    await Future.wait([browser.loadSeason(season), browser.loadSeason(season)]);
    expect(resolver.seasonCalls, 1);
    expect(resolver.queueCalls, 1);
  });
  test('failed requests can be retried', () async {
    final resolver = FakeResolver()..fail = true;
    final browser = PlaybackEpisodeBrowser(resolver: resolver, target: target);
    await expectLater(browser.loadSeasons(), throwsStateError);
    await expectLater(browser.loadSeason(season), throwsStateError);
    resolver.fail = false;
    expect(await browser.loadSeasons(), [season]);
    expect((await browser.loadSeason(season)).hasCurrent, isFalse);
    expect(resolver.seasonCalls, 2);
    expect(resolver.queueCalls, 2);
  });
}
