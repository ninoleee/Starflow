import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef PictureInPictureModeChanged = void Function(bool enabled);

class AndroidPictureInPictureController {
  AndroidPictureInPictureController._();

  static const MethodChannel _channel = MethodChannel('starflow/platform');
  static PictureInPictureModeChanged? _listener;

  static bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> isSupported() async {
    if (!isSupportedPlatform) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('isPictureInPictureSupported') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> attach(PictureInPictureModeChanged listener) async {
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

  static Future<void> setPlaybackEnabled({
    required bool enabled,
    required int aspectRatioWidth,
    required int aspectRatioHeight,
  }) async {
    if (!isSupportedPlatform) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setPlaybackPictureInPictureEnabled', {
        'enabled': enabled,
        'aspectRatioWidth': aspectRatioWidth,
        'aspectRatioHeight': aspectRatioHeight,
      });
    } catch (_) {
      // Keep playback available even if PiP registration fails.
    }
  }

  static Future<bool> enter({
    required int aspectRatioWidth,
    required int aspectRatioHeight,
  }) async {
    if (!isSupportedPlatform) {
      return false;
    }
    try {
      return await _channel
              .invokeMethod<bool>('enterPlaybackPictureInPicture', {
            'aspectRatioWidth': aspectRatioWidth,
            'aspectRatioHeight': aspectRatioHeight,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'onPictureInPictureModeChanged') {
      return;
    }
    final arguments = call.arguments;
    final enabled =
        arguments is Map ? arguments['enabled'] == true : arguments == true;
    _listener?.call(enabled);
  }
}
