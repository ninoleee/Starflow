import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

PlaybackStreamRelayService createPlaybackStreamRelayService(
    {int diskCacheMiB = 0}) {
  return const _NoopPlaybackStreamRelayService();
}

Future<void> clearPlaybackDiskCache() async {}

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
