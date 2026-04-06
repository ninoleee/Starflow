import 'package:flutter_riverpod/flutter_riverpod.dart';

final playbackPerformanceModeProvider = StateProvider<bool>((ref) => false);

final backgroundWorkSuspendedProvider = Provider<bool>((ref) {
  return ref.watch(playbackPerformanceModeProvider);
});
