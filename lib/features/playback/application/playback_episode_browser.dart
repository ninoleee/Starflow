import 'package:starflow/features/playback/application/playback_episode_queue_resolver.dart';
import 'package:starflow/features/playback/domain/playback_episode_queue.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

/// A picker session caches metadata only, never playable addresses.
class PlaybackEpisodeBrowser {
  PlaybackEpisodeBrowser({required this.resolver, required this.target});
  final PlaybackEpisodeQueueResolver resolver;
  final PlaybackTarget target;
  Future<List<PlaybackEpisodeSeason>>? _seasons;
  final _queues = <String, Future<PlaybackEpisodeQueue>>{};

  Future<List<PlaybackEpisodeSeason>> loadSeasons() async {
    try {
      return await (_seasons ??=
          resolver.loadSeasons(target).timeout(const Duration(seconds: 30)));
    } catch (_) {
      _seasons = null;
      rethrow;
    }
  }

  Future<PlaybackEpisodeQueue> loadSeason(PlaybackEpisodeSeason season) async {
    try {
      return await (_queues[season.id] ??= resolver
          .loadSeason(target, season)
          .timeout(const Duration(seconds: 30)));
    } catch (_) {
      _queues.remove(season.id);
      rethrow;
    }
  }
}
