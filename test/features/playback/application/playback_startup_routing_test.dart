import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_startup_routing.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  const baseTarget = PlaybackTarget(
    title: 'Demo',
    sourceId: 'emby-main',
    streamUrl: 'https://example.com/stream.mkv',
    sourceName: 'Emby',
    sourceKind: MediaSourceKind.emby,
  );

  test('decidePlaybackStartupRoute honors every engine and source constraint',
      () {
    final cases = <({
      String name,
      PlaybackEngine engine,
      PlaybackTarget target,
      PlaybackStartupRouteAction expected,
    })>[
      (
        name: 'selected system player',
        engine: PlaybackEngine.systemPlayer,
        target: baseTarget,
        expected: PlaybackStartupRouteAction.launchSystemPlayer,
      ),
      (
        name: 'header-protected Quark stays embedded',
        engine: PlaybackEngine.systemPlayer,
        target: baseTarget.copyWith(
          sourceId: 'quark-main',
          sourceName: 'Quark',
          sourceKind: MediaSourceKind.quark,
          headers: const <String, String>{
            'Cookie': 'kps=test; sign=test;',
            'Referer': 'https://drive-pc.quark.cn',
          },
        ),
        expected: PlaybackStartupRouteAction.openEmbeddedMpv,
      ),
      (
        name: 'authenticated Emby supports system player',
        engine: PlaybackEngine.systemPlayer,
        target: baseTarget.copyWith(
          headers: const <String, String>{'X-Emby-Token': 'token'},
        ),
        expected: PlaybackStartupRouteAction.launchSystemPlayer,
      ),
      (
        name: 'authenticated WebDAV supports system player',
        engine: PlaybackEngine.systemPlayer,
        target: baseTarget.copyWith(
          sourceKind: MediaSourceKind.nas,
          headers: const <String, String>{'Authorization': 'Basic abc123'},
        ),
        expected: PlaybackStartupRouteAction.launchSystemPlayer,
      ),
      (
        name: 'selected native container',
        engine: PlaybackEngine.nativeContainer,
        target: baseTarget,
        expected: PlaybackStartupRouteAction.launchNativeContainer,
      ),
      for (final container in <String>['iso', 'avi'])
        (
          name: 'native container keeps $container',
          engine: PlaybackEngine.nativeContainer,
          target: baseTarget.copyWith(container: container),
          expected: PlaybackStartupRouteAction.launchNativeContainer,
        ),
      (
        name: 'heavy video stays on selected embedded MPV',
        engine: PlaybackEngine.embeddedMpv,
        target: baseTarget.copyWith(
          width: 3840,
          height: 2160,
          bitrate: 30000000,
          videoCodec: 'hevc',
        ),
        expected: PlaybackStartupRouteAction.openEmbeddedMpv,
      ),
    ];

    for (final scenario in cases) {
      expect(
        decidePlaybackStartupRoute(
          PlaybackStartupRouteInput(
            playbackEngine: scenario.engine,
            target: scenario.target,
          ),
        ),
        scenario.expected,
        reason: scenario.name,
      );
    }
  });
}
