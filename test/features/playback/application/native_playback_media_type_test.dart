import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/native_playback_media_type.dart';
import 'package:starflow/features/playback/application/playback_remote_preflight.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  test('probes smartstrm fid and ambiguous smartstrm hash paths', () {
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
          'https://smartstrm.example.com/smartstrm_fid/quark/movie.mp4',
        ),
      ),
      isTrue,
    );
    expect(
      shouldProbeNativeSmartStrmMediaType(
        _target(
          'https://smartstrm.example.com/smartstrm_fid/quark/episode.mkv',
          container: 'mkv',
        ),
      ),
      isFalse,
    );
    expect(
      shouldProbeNativeSmartStrmMediaType(
        _target(
          'https://smartstrm.example.com/smartstrm_fid/quark/episode.mkv',
          container: '',
        ),
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

  test('recognizes HLS from a small body sample despite MP4 content type', () {
    const result = PlaybackRemotePreflightResult(
      attempted: true,
      canStream: true,
      acceptableStatus: true,
      supportsByteRange: false,
      authLikelyInvalid: false,
      linkLikelyExpired: false,
      statusCode: 200,
      sampledBytes: 32,
      samplePrefix: <int>[
        0xef,
        0xbb,
        0xbf,
        0x0a,
        0x23,
        0x45,
        0x58,
        0x54,
        0x4d,
        0x33,
        0x55,
      ],
      failureReason: PlaybackRemotePreflightFailureReason.none,
      duration: Duration(milliseconds: 120),
      contentType: 'video/mp4',
    );

    expect(resolveNativePlaybackMimeType(result), kNativePlaybackHlsMimeType);
  });

  test('recognizes a standard MP4 ftyp box from a small body sample', () {
    const result = PlaybackRemotePreflightResult(
      attempted: true,
      canStream: true,
      acceptableStatus: true,
      supportsByteRange: true,
      authLikelyInvalid: false,
      linkLikelyExpired: false,
      statusCode: 206,
      sampledBytes: 16,
      samplePrefix: <int>[
        0x00,
        0x00,
        0x00,
        0x18,
        0x66,
        0x74,
        0x79,
        0x70,
        0x69,
        0x73,
        0x6f,
        0x6d,
      ],
      failureReason: PlaybackRemotePreflightFailureReason.none,
      duration: Duration(milliseconds: 120),
      contentType: 'application/vnd.apple.mpegurl',
    );

    expect(resolveNativePlaybackMimeType(result), kNativePlaybackMp4MimeType);
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

PlaybackTarget _target(String streamUrl, {String container = 'mp4'}) {
  return PlaybackTarget(
    title: 'Talk',
    sourceId: 'nas-main',
    streamUrl: streamUrl,
    sourceName: 'NAS',
    sourceKind: MediaSourceKind.nas,
    container: container,
  );
}
