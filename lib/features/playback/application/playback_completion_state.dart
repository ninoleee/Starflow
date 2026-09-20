/// Session-local auto-skip completion, independent of real playback progress.
class PlaybackCompletionState {
  String? _itemKey;
  bool _completedByAutoSkip = false;

  /// Pass this value on every progress save, including shutdown saves.
  bool get completedByAutoSkip => _completedByAutoSkip;

  /// Use the stable playback item key, not a stream URL or a series key.
  /// Only recovery of the same item retains the marker. A fresh session,
  /// including replay of the same item, always clears it.
  void startMedia(String itemKey, {bool isRecovery = false}) {
    if (!isRecovery || itemKey != _itemKey || itemKey.isEmpty) {
      _completedByAutoSkip = false;
    }
    _itemKey = itemKey;
  }

  void markCompletedByAutoSkip() {
    if (_itemKey?.isNotEmpty ?? false) {
      _completedByAutoSkip = true;
    }
  }

  /// Call for user-initiated seeks, not internal recovery or auto-skip seeks.
  void clearForManualSeek() {
    _completedByAutoSkip = false;
  }
}
