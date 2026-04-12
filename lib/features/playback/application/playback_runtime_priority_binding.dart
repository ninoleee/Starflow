import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/playback/application/playback_session.dart';

final playbackRuntimePriorityBindingProvider = Provider<void>((ref) {
  ref.listen<bool>(playbackPerformanceModeProvider, (previous, next) {
    if (!next || previous == true) {
      return;
    }
    unawaited(
      ref.read(mediaRepositoryProvider).cancelActiveWebDavRefreshes(
            includeForceFull: true,
          ),
    );
  });
});
