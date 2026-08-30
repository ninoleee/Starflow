import 'package:starflow/features/playback/domain/playback_episode_queue.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

PlaybackEpisodeQueue? buildDeferredNativeEpisodeQueue({
  required PlaybackEpisodeQueue? queue,
  required PlaybackTarget? resolvedTarget,
}) {
  if (queue == null || resolvedTarget == null || !queue.hasCurrent) {
    return null;
  }
  final entries = queue.entries.toList();
  if (entries.length <= 1) {
    return null;
  }
  entries[queue.currentIndex] = entries[queue.currentIndex].copyWith(
    target: resolvedTarget,
  );
  return PlaybackEpisodeQueue(
    entries: entries,
    currentIndex: queue.currentIndex,
  );
}
