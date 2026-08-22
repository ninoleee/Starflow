import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/native_playback_capability.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  const baseTarget = PlaybackTarget(
    title: 'Demo',
    sourceId: 'emby-main',
    streamUrl: 'https://example.com/video.mkv',
    sourceName: 'Emby',
    sourceKind: MediaSourceKind.emby,
  );

  test('accepts Matroska and unknown extension for runtime probing', () {
    expect(supportsNativePlayback(baseTarget), isTrue);
    expect(
      supportsNativePlayback(
        baseTarget.copyWith(streamUrl: 'https://example.com/play?id=1'),
      ),
      isTrue,
    );
  });

  test('rejects ISO and BDMV optical media resources', () {
    expect(
      resolveNativePlaybackCapability(
        baseTarget.copyWith(streamUrl: 'https://example.com/movie.iso'),
      ),
      NativePlaybackCapability.opticalMediaImage,
    );
    expect(
      resolveNativePlaybackCapability(
        baseTarget.copyWith(
          streamUrl: 'file:///storage/movies/Disc/BDMV/index.bdmv',
        ),
      ),
      NativePlaybackCapability.opticalMediaImage,
    );
  });

  test('rejects containers that ExoPlayer cannot extract', () {
    for (final container in const ['avi', 'wmv', 'rmvb', 'divx']) {
      expect(
        resolveNativePlaybackCapability(
          baseTarget.copyWith(container: container),
        ),
        NativePlaybackCapability.unsupportedContainer,
      );
    }
  });
}
