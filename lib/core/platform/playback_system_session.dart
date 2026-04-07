import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef PlaybackRemoteCommandListener = Future<void> Function(
  PlaybackRemoteCommand command,
);

enum PlaybackRemoteCommandType {
  play,
  pause,
  toggle,
  seekForward,
  seekBackward,
  seekTo,
  stop,
  next,
  previous,
  becomingNoisy,
  interruptionPause,
  interruptionResume,
}

class PlaybackRemoteCommand {
  const PlaybackRemoteCommand(this.type, {this.position});

  final PlaybackRemoteCommandType type;
  final Duration? position;
}

class PlaybackSystemSessionState {
  const PlaybackSystemSessionState({
    required this.title,
    this.subtitle = '',
    required this.position,
    required this.duration,
    required this.playing,
    this.buffering = false,
    this.speed = 1.0,
    this.canSeek = true,
    this.hasPrevious = false,
    this.hasNext = false,
  });

  final String title;
  final String subtitle;
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;
  final double speed;
  final bool canSeek;
  final bool hasPrevious;
  final bool hasNext;

  Map<String, Object?> toMap() {
    return {
      'title': title,
      'subtitle': subtitle,
      'positionMs': position.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'playing': playing,
      'buffering': buffering,
      'speed': speed,
      'canSeek': canSeek,
      'hasPrevious': hasPrevious,
      'hasNext': hasNext,
    };
  }
}

class PlaybackSystemSessionController {
  PlaybackSystemSessionController._();

  static const MethodChannel _channel = MethodChannel(
    'starflow/playback_session',
  );

  static PlaybackRemoteCommandListener? _listener;

  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get supportsAirPlayPicker =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> attach(PlaybackRemoteCommandListener listener) async {
    if (!isSupportedPlatform) {
      return;
    }
    _listener = listener;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static Future<void> detach() async {
    if (!isSupportedPlatform) {
      return;
    }
    _listener = null;
    _channel.setMethodCallHandler(null);
  }

  static Future<void> setActive(bool active) async {
    if (!isSupportedPlatform) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setActive', {'active': active});
    } catch (_) {
      // Keep playback available even when the native session bridge fails.
    }
  }

  static Future<void> update(PlaybackSystemSessionState state) async {
    if (!isSupportedPlatform) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('update', state.toMap());
    } catch (_) {
      // Ignore transient platform bridge failures.
    }
  }

  static Future<bool> showAirPlayPicker() async {
    if (!supportsAirPlayPicker) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('showAirPlayPicker') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'onPlaybackRemoteCommand') {
      return;
    }
    final listener = _listener;
    if (listener == null) {
      return;
    }

    final arguments = call.arguments;
    final map = arguments is Map<Object?, Object?> ? arguments : const {};
    final rawCommand = '${map['command'] ?? ''}'.trim();
    final type = _commandTypeFor(rawCommand);
    if (type == null) {
      return;
    }

    final positionMs = map['positionMs'];
    final position =
        positionMs is num ? Duration(milliseconds: positionMs.round()) : null;
    await listener(PlaybackRemoteCommand(type, position: position));
  }

  static PlaybackRemoteCommandType? _commandTypeFor(String raw) {
    switch (raw) {
      case 'play':
        return PlaybackRemoteCommandType.play;
      case 'pause':
        return PlaybackRemoteCommandType.pause;
      case 'toggle':
        return PlaybackRemoteCommandType.toggle;
      case 'seekForward':
        return PlaybackRemoteCommandType.seekForward;
      case 'seekBackward':
        return PlaybackRemoteCommandType.seekBackward;
      case 'seekTo':
        return PlaybackRemoteCommandType.seekTo;
      case 'stop':
        return PlaybackRemoteCommandType.stop;
      case 'next':
        return PlaybackRemoteCommandType.next;
      case 'previous':
        return PlaybackRemoteCommandType.previous;
      case 'becomingNoisy':
        return PlaybackRemoteCommandType.becomingNoisy;
      case 'interruptionPause':
        return PlaybackRemoteCommandType.interruptionPause;
      case 'interruptionResume':
        return PlaybackRemoteCommandType.interruptionResume;
    }
    return null;
  }
}
