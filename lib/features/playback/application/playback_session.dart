import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

final playbackPerformanceModeProvider = StateProvider<bool>((ref) => false);

final backgroundWorkSuspendedProvider = Provider<bool>((ref) {
  return ref.watch(playbackPerformanceModeProvider);
});

final backgroundAnimationsSuspendedProvider = Provider<bool>((ref) {
  return ref.watch(backgroundWorkSuspendedProvider);
});

final backgroundImageLoadingSuspendedProvider = Provider<bool>((ref) {
  return ref.watch(backgroundWorkSuspendedProvider);
});

final backgroundEnrichmentSuspendedProvider = Provider<bool>((ref) {
  return ref.watch(backgroundWorkSuspendedProvider);
});
