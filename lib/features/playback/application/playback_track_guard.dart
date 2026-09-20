import 'dart:async';

/// Carries a session/user-selection fence across nested async track helpers.
class PlaybackTrackGuard {
  PlaybackTrackGuard(this.isCurrent);

  final bool Function() isCurrent;
  static final _key = Object();

  static bool get allowsWrite =>
      (Zone.current[_key] as PlaybackTrackGuard?)?.isCurrent() ?? true;

  Future<void> run(Iterable<Future<void> Function()> steps) {
    final parent = Zone.current[_key] as PlaybackTrackGuard?;
    final guard =
        PlaybackTrackGuard(() => isCurrent() && (parent?.isCurrent() ?? true));
    return runZoned(
      () async {
        for (final step in steps) {
          if (!guard.isCurrent()) return;
          await step();
        }
      },
      zoneValues: {_key: guard},
    );
  }
}
