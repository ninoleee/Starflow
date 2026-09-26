import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

PlaybackStreamRelayService createPlaybackStreamRelayService(
    {int diskCacheMiB = 0}) {
  return const _NoopPlaybackStreamRelayService();
}

Future<void> clearPlaybackDiskCache() async {}
Future<void> disablePlaybackDiskCache() async {}
Future<LocalStorageCacheSummary> inspectPlaybackDiskCache() async =>
    const LocalStorageCacheSummary(
      type: LocalStorageCacheType.playbackDiskCache,
      entryCount: 0,
      totalBytes: 0,
    );

class _NoopPlaybackStreamRelayService implements PlaybackStreamRelayService {
  const _NoopPlaybackStreamRelayService();

  @override
  Future<void> clear({String reason = ''}) async {}

  @override
  Future<void> close() async {}

  @override
  Future<PlaybackTarget> prepareTarget(PlaybackTarget target) async {
    return target;
  }
}
