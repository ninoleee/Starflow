import 'package:flutter_riverpod/flutter_riverpod.dart';

final playbackPerformanceModeProvider = StateProvider<bool>((ref) => false);

class BackgroundWorkSuspensionState {
  const BackgroundWorkSuspensionState({
    required this.animationsSuspended,
    required this.imageLoadingSuspended,
    required this.enrichmentSuspended,
  });

  final bool animationsSuspended;
  final bool imageLoadingSuspended;
  final bool enrichmentSuspended;

  bool get anySuspended =>
      animationsSuspended || imageLoadingSuspended || enrichmentSuspended;
}

final backgroundWorkSuspensionStateProvider =
    Provider<BackgroundWorkSuspensionState>((ref) {
  final performanceModeEnabled = ref.watch(playbackPerformanceModeProvider);
  return BackgroundWorkSuspensionState(
    animationsSuspended: performanceModeEnabled,
    imageLoadingSuspended: performanceModeEnabled,
    enrichmentSuspended: performanceModeEnabled,
  );
});

final backgroundAnimationsSuspendedProvider = Provider<bool>((ref) {
  return ref.watch(
    backgroundWorkSuspensionStateProvider.select(
      (state) => state.animationsSuspended,
    ),
  );
});

final backgroundImageLoadingSuspendedProvider = Provider<bool>((ref) {
  return ref.watch(
    backgroundWorkSuspensionStateProvider.select(
      (state) => state.imageLoadingSuspended,
    ),
  );
});

final backgroundEnrichmentSuspendedProvider = Provider<bool>((ref) {
  return ref.watch(
    backgroundWorkSuspensionStateProvider.select(
      (state) => state.enrichmentSuspended,
    ),
  );
});

final backgroundWorkSuspendedProvider = Provider<bool>((ref) {
  return ref.watch(
    backgroundWorkSuspensionStateProvider.select((state) => state.anySuspended),
  );
});
