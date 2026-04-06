import 'package:flutter/services.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

class SubtitleSearchHostBridge {
  SubtitleSearchHostBridge._();

  static const MethodChannel _channel = MethodChannel('starflow/subtitle_search');

  static Future<bool> finishSelection(SubtitleSearchSelection selection) async {
    try {
      return await _channel.invokeMethod<bool>('finishSubtitleSearch', {
            'cachedPath': selection.cachedPath,
            'subtitleFilePath': selection.subtitleFilePath ?? '',
            'displayName': selection.displayName,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> cancel() async {
    try {
      return await _channel.invokeMethod<bool>('cancelSubtitleSearch') ?? false;
    } catch (_) {
      return false;
    }
  }
}
