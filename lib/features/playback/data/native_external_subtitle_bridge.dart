import 'package:flutter/services.dart';

/// Bridge for the iOS AVPlayer external subtitle overlay.
///
/// AVPlayer cannot expose a downloaded SRT/ASS/VTT file as an AVMediaSelection
/// option. iOS therefore parses and renders supported text subtitles in the
/// native controller overlay. The bridge is intentionally separate from the
/// native playback launcher so callers can adopt it without changing launch
/// arguments or episode transport ownership.
class NativeExternalSubtitleBridge {
  NativeExternalSubtitleBridge._();

  static const MethodChannel _channel = MethodChannel('starflow/platform');

  static Future<bool> openMenu() async =>
      await _channel.invokeMethod<bool>('openNativeSubtitleMenu') ?? false;

  static Future<bool> applyFile(
    String path, {
    String displayName = '',
  }) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return false;
    return await _channel.invokeMethod<bool>('applyNativeExternalSubtitle', {
          'path': trimmed,
          'displayName': displayName.trim(),
        }) ??
        false;
  }

  static Future<bool> download(
    String url, {
    Map<String, String> headers = const <String, String>{},
    String displayName = 'subtitle.srt',
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    return await _channel.invokeMethod<bool>('downloadNativeExternalSubtitle', {
          'url': trimmed,
          'headers': headers,
          'displayName':
              displayName.trim().isEmpty ? 'subtitle.srt' : displayName.trim(),
        }) ??
        false;
  }

  static Future<bool> cancel() async =>
      await _channel.invokeMethod<bool>('cancelNativeExternalSubtitle') ??
      false;

  static Future<bool> clear() async =>
      await _channel.invokeMethod<bool>('clearNativeExternalSubtitle') ?? false;
}
