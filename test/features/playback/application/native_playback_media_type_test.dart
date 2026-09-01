import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/native_playback_media_type.dart';
import 'package:starflow/features/playback/application/playback_remote_preflight.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  test('probes only ambiguous smartstrm hash paths', () {
    expect(
      shouldProbeNativeSmartStrmMediaType(
        _target(
          'https://smartstrm.example.com/smartstrm/my/Talk%20%2323.mp4',
        ),
      ),
      isTrue,
    );
    expect(
      shouldProbeNativeSmartStrmMediaType(
        _target('https://smartstrm.example.com/smartstrm/my/movie.mp4'),
      ),
      isFalse,
    );
    expect(
      shouldProbeNativeSmartStrmMediaType(
        _target(
          'https://smartstrm.example.com/smartstrm_fid/quark/Talk%20%2323.mp4',
        ),
      ),
      isTrue,
    );
    expect(
      shouldProbeNativeSmartStrmMediaType(
        _target('https://media.example.com/Talk%20%2323.mp4'),
      ),
      isFalse,
    );
    expect(
      shouldProbeNativeSmartStrmMediaType(
        _target(
          'https://media.example.com/not-smartstrm_fid/Talk%20%2323.mp4',
        ),
      ),
      isFalse,
    );
  });

  test('maps successful HLS preflight to native HLS mime type', () {
    const result = PlaybackRemotePreflightResult(
      attempted: true,
      canStream: true,
      acceptableStatus: true,
      supportsByteRange: false,
      authLikelyInvalid: false,
      linkLikelyExpired: false,
      statusCode: 200,
      sampledBytes: 0,
      failureReason: PlaybackRemotePreflightFailureReason.none,
      duration: Duration(milliseconds: 800),
      contentType: 'application/vnd.apple.mpegurl',
    );

    expect(resolveNativePlaybackMimeType(result), kNativePlaybackHlsMimeType);
  });

  test('keeps normal native inference for direct MP4 responses', () {
    const result = PlaybackRemotePreflightResult(
      attempted: true,
      canStream: true,
      acceptableStatus: true,
      supportsByteRange: true,
      authLikelyInvalid: false,
      linkLikelyExpired: false,
      statusCode: 206,
      sampledBytes: 0,
      failureReason: PlaybackRemotePreflightFailureReason.none,
      duration: Duration(milliseconds: 800),
      contentType: 'video/mp4',
    );

    expect(resolveNativePlaybackMimeType(result), isNull);
  });
}

PlaybackTarget _target(String streamUrl) {
  return PlaybackTarget(
    title: 'Talk',
    sourceId: 'nas-main',
    streamUrl: streamUrl,
    sourceName: 'NAS',
    sourceKind: MediaSourceKind.nas,
    container: 'mp4',
  );
}
