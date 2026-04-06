import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/playback/data/native_playback_launcher_stub.dart'
    if (dart.library.io) 'package:starflow/features/playback/data/native_playback_launcher_io.dart'
    as impl;
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final nativePlaybackLauncherProvider = Provider<NativePlaybackLauncher>((ref) {
  return impl.createNativePlaybackLauncher();
});

abstract class NativePlaybackLauncher {
  Future<NativePlaybackLaunchResult> launch(
    PlaybackTarget target, {
    required PlaybackDecodeMode decodeMode,
  });
}

class NativePlaybackLaunchResult {
  const NativePlaybackLaunchResult({
    required this.launched,
    this.message = '',
  });

  final bool launched;
  final String message;
}
