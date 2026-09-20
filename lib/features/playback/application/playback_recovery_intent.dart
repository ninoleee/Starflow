/// A recovery may act only while the intent and foreground lease it captured
/// are unchanged. Backend playing/position notifications do not change intent.
class PlaybackRecoveryIntent {
  PlaybackRecoveryIntent({this.onInvalidated});

  final void Function()? onInvalidated;
  int _revision = 0;
  bool _playing = true;
  bool _foreground = true;

  int get revision => _revision;
  bool allows(int revision) => revision == _revision && _playing && _foreground;

  void playback(bool playing) {
    _playing = playing;
    invalidate();
  }

  void foreground(bool foreground) {
    _foreground = foreground;
    invalidate();
  }

  void invalidate() {
    _revision++;
    onInvalidated?.call();
  }

  Future<void> playAndSeek({
    required int revision,
    required bool Function() isCurrent,
    required Future<void> Function() play,
    required Future<void> Function() seek,
  }) async {
    if (!allows(revision) || !isCurrent()) return;
    await play();
    if (!allows(revision) || !isCurrent()) return;
    await seek();
  }
}
