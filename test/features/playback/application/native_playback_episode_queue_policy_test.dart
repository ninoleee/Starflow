import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/native_playback_episode_queue_policy.dart';
import 'package:starflow/features/playback/domain/playback_episode_queue.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  test('keeps unresolved strm entries as deferred native metadata', () {
    final queue = PlaybackEpisodeQueue(
      entries: [
        _entry(_target('https://media.example.com/current.mp4')),
        _entry(_target('https://nas.example.com/next.strm')),
      ],
    );

    final deferred = buildDeferredNativeEpisodeQueue(
      queue: queue,
      resolvedTarget: queue.currentEntry!.target,
    );

    expect(deferred, isNotNull);
    expect(deferred!.entries, hasLength(2));
    expect(deferred.entries[1].target.needsResolution, isTrue);
  });

  test('keeps an already resolved direct queue without network work', () {
    final resolvedCurrent = _target('https://media.example.com/current.mp4');
    final queue = PlaybackEpisodeQueue(
      entries: [
        _entry(_target('https://nas.example.com/current.strm')),
        _entry(_target('https://media.example.com/next.mp4')),
      ],
    );

    final immediate = buildDeferredNativeEpisodeQueue(
      queue: queue,
      resolvedTarget: resolvedCurrent,
    );

    expect(immediate, isNotNull);
    expect(immediate!.entries, hasLength(2));
    expect(immediate.currentEntry!.target.streamUrl, resolvedCurrent.streamUrl);
  });

  test('keeps episodes before and after the current episode', () {
    final resolvedCurrent = _target('https://media.example.com/current.mp4');
    final queue = PlaybackEpisodeQueue(
      currentIndex: 1,
      entries: [
        _entry(_target('https://nas.example.com/previous.strm')),
        _entry(_target('https://nas.example.com/current.strm')),
        _entry(_target('https://nas.example.com/next.strm')),
      ],
    );

    final deferred = buildDeferredNativeEpisodeQueue(
      queue: queue,
      resolvedTarget: resolvedCurrent,
    );

    expect(deferred, isNotNull);
    expect(deferred!.entries, hasLength(3));
    expect(deferred.currentIndex, 1);
    expect(deferred.entries[0].target.needsResolution, isTrue);
    expect(deferred.currentEntry!.target.streamUrl, resolvedCurrent.streamUrl);
    expect(deferred.entries[2].target.needsResolution, isTrue);
  });
}

PlaybackEpisodeQueueEntry _entry(PlaybackTarget target) {
  return PlaybackEpisodeQueueEntry(
    target: target,
    playbackItemKey: target.streamUrl,
    seriesKey: 'series',
  );
}

PlaybackTarget _target(String streamUrl) {
  return PlaybackTarget(
    title: 'Episode',
    sourceId: 'nas-main',
    streamUrl: streamUrl,
    sourceName: 'NAS',
    sourceKind: MediaSourceKind.nas,
    container: streamUrl.endsWith('.strm') ? 'strm' : 'mp4',
  );
}
