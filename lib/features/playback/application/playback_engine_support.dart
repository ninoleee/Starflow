import 'package:flutter/foundation.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

String playbackEnginePlatformLabel(
  PlaybackEngine engine, {
  required TargetPlatform platform,
}) {
  if (engine != PlaybackEngine.nativeContainer) {
    return engine.label;
  }
  return switch (platform) {
    TargetPlatform.android => 'ExoPlayer（原生）',
    TargetPlatform.iOS => 'AVPlayer（原生）',
    _ => engine.label,
  };
}

List<PlaybackEngine> supportedPlaybackEngines({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) {
    return const [PlaybackEngine.embeddedMpv];
  }
  return switch (platform) {
    TargetPlatform.android || TargetPlatform.iOS => PlaybackEngine.values,
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux =>
      const [
        PlaybackEngine.embeddedMpv,
        PlaybackEngine.systemPlayer,
      ],
    TargetPlatform.fuchsia => const [PlaybackEngine.embeddedMpv],
  };
}

PlaybackEngine effectivePlaybackEngine({
  required PlaybackEngine selected,
  required bool isWeb,
  required TargetPlatform platform,
}) {
  final supported = supportedPlaybackEngines(
    isWeb: isWeb,
    platform: platform,
  );
  return supported.contains(selected) ? selected : PlaybackEngine.embeddedMpv;
}
