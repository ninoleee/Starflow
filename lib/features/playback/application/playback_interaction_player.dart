import 'package:media_kit/media_kit.dart';

/// Captures explicit control commands before the backend can publish events.
///
/// Pass this instance to video controls even when their field type is [Player].
/// Internal startup, intro skipping and recovery must use the automatic methods
/// instead. Direct calls to [platform] bypass this boundary.
class PlaybackInteractionPlayer extends Player {
  PlaybackInteractionPlayer({
    required this.onUserSeek,
    this.onUserPlaybackIntent,
    super.configuration,
    super.platformPlayer,
  });

  /// Runs synchronously before every manual seek, even if that seek later fails.
  /// The callback must complete its intent bookkeeping without awaiting work.
  final void Function(Duration position) onUserSeek;

  /// Runs once before an explicit play, pause or toggle command is delegated.
  ///
  /// `true` means play intent and `false` means pause intent. Toggle intent uses
  /// the current [state]. This is not a playback-state notification: EOF and
  /// other backend events never call it. Use either intent to cancel pending
  /// automatic transitions, and `false` for pause-specific bookkeeping.
  final void Function(bool playing)? onUserPlaybackIntent;

  @override
  Future<void> seek(Duration duration) async {
    onUserSeek(duration);
    return super.seek(duration);
  }

  Future<void> seekAutomatically(Duration duration) => super.seek(duration);

  @override
  Future<void> play() async {
    onUserPlaybackIntent?.call(true);
    return super.play();
  }

  @override
  Future<void> pause() async {
    onUserPlaybackIntent?.call(false);
    return super.pause();
  }

  @override
  Future<void> playOrPause() async {
    onUserPlaybackIntent?.call(!state.playing);
    return super.playOrPause();
  }

  Future<void> playAutomatically() => super.play();

  Future<void> pauseAutomatically() => super.pause();

  Future<void> playOrPauseAutomatically() => super.playOrPause();
}
