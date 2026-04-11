import 'package:riverpod/misc.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/playback/application/playback_engine_router.dart';
import 'package:starflow/features/playback/application/playback_startup_preparation.dart';
import 'package:starflow/features/playback/application/playback_startup_routing.dart';
import 'package:starflow/features/playback/application/playback_target_resolver.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

typedef PlaybackStartupCoordinatorReader = T Function<T>(
    ProviderListenable<T> provider);

class PlaybackStartupCoordinator {
  PlaybackStartupCoordinator({
    required this.read,
    required this.targetResolver,
    required this.engineRouter,
  });

  final PlaybackStartupCoordinatorReader read;
  final PlaybackTargetResolver targetResolver;
  final PlaybackEngineRouter engineRouter;

  Future<PlaybackStartupOutcome> start({
    required PlaybackTarget initialTarget,
    required bool isTelevision,
    required bool isWeb,
  }) async {
    await read(mediaRepositoryProvider).cancelActiveWebDavRefreshes(
      includeForceFull: false,
    );
    final resolvedTarget = await targetResolver.resolve(initialTarget);
    final settings = read(appSettingsProvider);
    final startupPreparation = await preparePlaybackStartup(
      PlaybackStartupPreparationInput(
        resolvedTarget: resolvedTarget,
        settings: settings,
        isTelevision: isTelevision,
        isWeb: isWeb,
      ),
      playbackMemoryRepository: read(playbackMemoryRepositoryProvider),
    );
    final routeAction =
        engineRouter.route(startupPreparation.startupRouteInput);
    return PlaybackStartupOutcome(
      resolvedTarget: resolvedTarget,
      settings: settings,
      startupPreparation: startupPreparation,
      routeAction: routeAction,
    );
  }
}

class PlaybackStartupOutcome {
  const PlaybackStartupOutcome({
    required this.resolvedTarget,
    required this.settings,
    required this.startupPreparation,
    required this.routeAction,
  });

  final PlaybackTarget resolvedTarget;
  final AppSettings settings;
  final PlaybackStartupPreparationResult startupPreparation;
  final PlaybackStartupRouteAction routeAction;
}
