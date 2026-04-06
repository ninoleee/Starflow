import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/playback/data/system_playback_launcher_stub.dart'
    if (dart.library.io)
        'package:starflow/features/playback/data/system_playback_launcher_io.dart'
    as impl;
import 'package:starflow/features/playback/domain/playback_models.dart';

final systemPlaybackLauncherProvider = Provider<SystemPlaybackLauncher>((ref) {
  return impl.createSystemPlaybackLauncher();
});

abstract class SystemPlaybackLauncher {
  Future<SystemPlaybackLaunchResult> launch(PlaybackTarget target);
}

class SystemPlaybackLaunchResult {
  const SystemPlaybackLaunchResult({
    required this.launched,
    this.message = '',
  });

  final bool launched;
  final String message;
}
