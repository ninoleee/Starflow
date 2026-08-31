import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ApplicationExitController {
  ApplicationExitController._();

  static const MethodChannel _channel = MethodChannel('starflow/platform');

  static bool get isNativeExitSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> exitNativeTask() async {
    if (!isNativeExitSupported) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('exitApplication') ?? false;
    } catch (_) {
      return false;
    }
  }
}
