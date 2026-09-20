import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/application/playback_completion_state.dart';

void main() {
  test('starts incomplete and ignores marks without a media item', () {
    final state = PlaybackCompletionState();
    expect(state.completedByAutoSkip, isFalse);
    state.markCompletedByAutoSkip();
    expect(state.completedByAutoSkip, isFalse);
    state.startMedia('');
    state.markCompletedByAutoSkip();
    expect(state.completedByAutoSkip, isFalse);
  });

  test('retains explicit completion across repeated reads and marks', () {
    final state = PlaybackCompletionState()..startMedia('episode-1');
    state.markCompletedByAutoSkip();
    for (var index = 0; index < 3; index++) {
      expect(state.completedByAutoSkip, isTrue);
      state.markCompletedByAutoSkip();
    }
  });

  test('preserves same-media recovery but clears after manual seek', () {
    final state = PlaybackCompletionState()
      ..startMedia('episode-1')
      ..markCompletedByAutoSkip();
    state.startMedia('episode-1', isRecovery: true);
    expect(state.completedByAutoSkip, isTrue);
    state.clearForManualSeek();
    expect(state.completedByAutoSkip, isFalse);
    state.startMedia('episode-1', isRecovery: true);
    expect(state.completedByAutoSkip, isFalse);
    state.markCompletedByAutoSkip();
    expect(state.completedByAutoSkip, isTrue);
  });

  test('new media never inherits completion, even on a recovery path', () {
    for (final isRecovery in [false, true]) {
      final state = PlaybackCompletionState()
        ..startMedia('episode-1')
        ..markCompletedByAutoSkip();
      state.startMedia('episode-2', isRecovery: isRecovery);
      expect(state.completedByAutoSkip, isFalse);
      state.startMedia('episode-1', isRecovery: true);
      expect(state.completedByAutoSkip, isFalse);
    }
  });

  test('fresh replay of the same media clears completion', () {
    final state = PlaybackCompletionState()
      ..startMedia('episode-1')
      ..markCompletedByAutoSkip();
    state.startMedia('episode-1');
    expect(state.completedByAutoSkip, isFalse);
  });

  test('separate playback sessions do not share completion', () {
    final first = PlaybackCompletionState()
      ..startMedia('episode-1')
      ..markCompletedByAutoSkip();
    final second = PlaybackCompletionState()..startMedia('episode-1');
    expect(first.completedByAutoSkip, isTrue);
    expect(second.completedByAutoSkip, isFalse);
  });
}
