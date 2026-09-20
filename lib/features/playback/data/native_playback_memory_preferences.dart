import 'package:flutter/services.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';

class PlaybackMemoryWriteConflict implements Exception {
  const PlaybackMemoryWriteConflict();
}

/// Mobile writes share the native player's queue instead of racing its snapshot.
class NativePlaybackMemoryPreferences extends SharedPreferencesStore {
  NativePlaybackMemoryPreferences({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('starflow/platform'),
        super.reloading();

  static const storageKey = 'starflow.playback.memory.v1';
  final MethodChannel _channel;
  String? _expected;
  bool _hasRead = false;

  @override
  Future<String?> getString(String key) async {
    if (key != storageKey) return super.getString(key);
    _expected = await _channel.invokeMethod<String>('readPlaybackMemory');
    _hasRead = true;
    return _expected;
  }

  Future<void> _commit(String? value) async {
    if (!_hasRead) await getString(storageKey);
    final accepted = await _channel.invokeMethod<bool>(
      'compareAndSetPlaybackMemory',
      {'expected': _expected, 'value': value},
    );
    _hasRead = false;
    if (accepted != true) throw const PlaybackMemoryWriteConflict();
  }

  @override
  Future<void> setString(String key, String value) =>
      key == storageKey ? _commit(value) : super.setString(key, value);

  @override
  Future<void> remove(String key) =>
      key == storageKey ? _commit(null) : super.remove(key);
}
