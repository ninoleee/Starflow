import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

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

// Backward-compatible aggregate flag used by older callers/tests.
final backgroundWorkSuspendedProvider = Provider<bool>((ref) {
  final state = ref.watch(backgroundWorkSuspensionStateProvider);
  return state.animationsSuspended &&
      state.imageLoadingSuspended &&
      state.enrichmentSuspended;
});
