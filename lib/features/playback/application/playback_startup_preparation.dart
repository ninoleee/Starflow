import 'package:starflow/features/playback/application/playback_startup_routing.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

class PlaybackStartupPreparationInput {
  const PlaybackStartupPreparationInput({
    required this.resolvedTarget,
    required this.settings,
    required this.isTelevision,
    required this.isWeb,
  });

  final PlaybackTarget resolvedTarget;
  final AppSettings settings;
  final bool isTelevision;
  final bool isWeb;
}

class PlaybackStartupPreparationResult {
  const PlaybackStartupPreparationResult({
    required this.resolvedTarget,
    required this.resumeEntry,
    required this.skipPreference,
    required this.startupRouteInput,
    required this.startupRoute,
  });

  final PlaybackTarget resolvedTarget;
  final PlaybackProgressEntry? resumeEntry;
  final SeriesSkipPreference? skipPreference;
  final PlaybackStartupRouteInput startupRouteInput;
  final PlaybackStartupRouteAction startupRoute;
}

Future<PlaybackStartupPreparationResult> preparePlaybackStartup(
  PlaybackStartupPreparationInput input, {
  required PlaybackMemoryRepository playbackMemoryRepository,
}) async {
  final resumeEntry = await playbackMemoryRepository.loadEntryForTarget(
    input.resolvedTarget,
  );
  final skipPreference = await playbackMemoryRepository.loadSkipPreference(
    input.resolvedTarget,
  );
  final startupRouteInput = PlaybackStartupRouteInput(
    playbackEngine: input.settings.playbackEngine,
    performanceAutoDowngradeHeavyPlaybackEnabled:
        input.settings.performanceAutoDowngradeHeavyPlaybackEnabled,
    isTelevision: input.isTelevision,
    isWeb: input.isWeb,
    target: input.resolvedTarget,
  );
  final startupRoute = decidePlaybackStartupRoute(startupRouteInput);
  return PlaybackStartupPreparationResult(
    resolvedTarget: input.resolvedTarget,
    resumeEntry: resumeEntry,
    skipPreference: skipPreference,
    startupRouteInput: startupRouteInput,
    startupRoute: startupRoute,
  );
}
