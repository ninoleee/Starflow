import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

PlaybackStreamRelayService createPlaybackStreamRelayService() {
  return const _NoopPlaybackStreamRelayService();
}

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
