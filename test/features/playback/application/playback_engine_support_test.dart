import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/application/playback_engine_support.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  test('Android and iOS expose all playback engines', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      expect(
        supportedPlaybackEngines(isWeb: false, platform: platform),
        PlaybackEngine.values,
      );
    }
  });

  test('Windows and macOS hide the unavailable native engine', () {
    for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
      expect(
        supportedPlaybackEngines(isWeb: false, platform: platform),
        const [PlaybackEngine.embeddedMpv, PlaybackEngine.systemPlayer],
      );
    }
  });

  test('persisted desktop native selection resolves to embedded MPV', () {
    expect(
      effectivePlaybackEngine(
        selected: PlaybackEngine.nativeContainer,
        isWeb: false,
        platform: TargetPlatform.windows,
      ),
      PlaybackEngine.embeddedMpv,
    );
  });
}
