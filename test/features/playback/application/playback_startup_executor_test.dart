import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_startup_executor.dart';
import 'package:starflow/features/playback/application/playback_startup_routing.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  const target = PlaybackTarget(
    title: 'Demo',
    sourceId: 'emby-main',
    streamUrl: 'https://example.com/video.mkv',
    sourceName: 'Emby',
    sourceKind: MediaSourceKind.emby,
  );

  test('native flow exit does not continue with embedded MPV', () async {
    final executor = PlaybackStartupExecutor(
      launchSystemPlayer: (_) async {},
      launchNativeContainer: (_) async {},
    );

    expect(
      await executor.execute(
        PlaybackStartupRouteAction.launchNativeContainer,
        target,
      ),
      isFalse,
    );
  });

  test('native first-frame success closes embedded startup path', () async {
    final executor = PlaybackStartupExecutor(
      launchSystemPlayer: (_) async {},
      launchNativeContainer: (_) async {},
    );

    expect(
      await executor.execute(
        PlaybackStartupRouteAction.launchNativeContainer,
        target,
      ),
      isFalse,
    );
  });
}
