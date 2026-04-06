import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BackgroundPlaybackController {
  BackgroundPlaybackController._();

  static const MethodChannel _channel = MethodChannel('starflow/platform');

  static bool get isAppleMobilePlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> setEnabled(bool enabled) async {
    if (!isAppleMobilePlatform) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setBackgroundPlaybackEnabled', {
        'enabled': enabled,
      });
    } catch (_) {
      // Keep playback available even if the native background session update fails.
    }
  }
}
