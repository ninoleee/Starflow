import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_remote_preflight.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  group('PlaybackRemotePreflight', () {
    test('returns unsupported scheme for non-http urls', () async {
      final helper = PlaybackRemotePreflight(
        clientFactory: () => MockClient((_) async => http.Response('', 200)),
      );
      const target = PlaybackTarget(
        title: 'Local File',
        sourceId: 'nas-main',
        streamUrl: 'file:///D:/Movies/video.mkv',
        sourceName: 'NAS',
        sourceKind: MediaSourceKind.nas,
      );

      final result = await helper.probe(target);

      expect(result.attempted, isFalse);
      expect(
        result.failureReason,
        PlaybackRemotePreflightFailureReason.unsupportedScheme,
      );
      expect(result.canStream, isFalse);
    });

    test('sends short GET with range header and marks range-capable response',
        () async {
      http.BaseRequest? capturedRequest;
      final helper = PlaybackRemotePreflight(
        clientFactory: () => MockClient((request) async {
          capturedRequest = request;
          return http.Response.bytes(
            List<int>.filled(2048, 1),
            206,
            headers: const <String, String>{
              'content-range': 'bytes 0-2047/4096',
            },
          );
        }),
      );
      const target = PlaybackTarget(
        title: 'Remote Media',
        sourceId: 'emby-main',
        streamUrl: 'https://media.example.com/video.mkv',
        sourceName: 'Emby',
        sourceKind: MediaSourceKind.emby,
        headers: <String, String>{'Authorization': 'Bearer token'},
      );

      final result = await helper.probe(target);

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.method, 'GET');
      expect(capturedRequest!.headers['Authorization'], 'Bearer token');
      expect(capturedRequest!.headers['Range'], 'bytes=0-262143');
      expect(result.canStream, isTrue);
      expect(result.acceptableStatus, isTrue);
      expect(result.supportsByteRange, isTrue);
      expect(result.failureReason, PlaybackRemotePreflightFailureReason.none);
    });

    test('accepts 200 with accept-ranges bytes', () async {
      final helper = PlaybackRemotePreflight(
        clientFactory: () => MockClient((_) async {
          return http.Response.bytes(
            List<int>.filled(1024, 1),
            200,
            headers: const <String, String>{'accept-ranges': 'bytes'},
          );
        }),
      );
      const target = PlaybackTarget(
        title: 'Remote Media',
        sourceId: 'nas-main',
        streamUrl: 'https://webdav.example.com/video.mp4',
        sourceName: 'WebDAV',
        sourceKind: MediaSourceKind.nas,
      );

      final result = await helper.probe(target);

      expect(result.canStream, isTrue);
      expect(result.acceptableStatus, isTrue);
      expect(result.supportsByteRange, isTrue);
    });

    test('reports auth failure for 401', () async {
      final helper = PlaybackRemotePreflight(
        clientFactory: () => MockClient((_) async => http.Response('', 401)),
      );
      const target = PlaybackTarget(
        title: 'Auth Required',
        sourceId: 'emby-main',
        streamUrl: 'https://emby.example.com/Videos/123/stream.mkv',
        sourceName: 'Emby',
        sourceKind: MediaSourceKind.emby,
      );

      final result = await helper.probe(target);

      expect(result.canStream, isFalse);
      expect(result.authLikelyInvalid, isTrue);
      expect(result.failureReason, PlaybackRemotePreflightFailureReason.unauthorized);
    });

    test('reports likely expired link for 410', () async {
      final helper = PlaybackRemotePreflight(
        clientFactory: () => MockClient((_) async => http.Response('', 410)),
      );
      const target = PlaybackTarget(
        title: 'Expired',
        sourceId: 'quark-main',
        streamUrl: 'https://download.example.com/temp/video.mkv?token=abc',
        sourceName: 'Quark',
        sourceKind: MediaSourceKind.quark,
      );

      final result = await helper.probe(target);

      expect(result.canStream, isFalse);
      expect(result.linkLikelyExpired, isTrue);
      expect(result.failureReason, PlaybackRemotePreflightFailureReason.linkExpired);
    });

    test('reports timeout when request exceeds short timeout', () async {
      final helper = PlaybackRemotePreflight(
        clientFactory: () => MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          return http.Response('', 200);
        }),
      );
      const target = PlaybackTarget(
        title: 'Slow Media',
        sourceId: 'nas-main',
        streamUrl: 'https://slow.example.com/video.mkv',
        sourceName: 'NAS',
        sourceKind: MediaSourceKind.nas,
      );

      final result = await helper.probe(
        target,
        options: const PlaybackRemotePreflightOptions(
          requestTimeout: Duration(milliseconds: 20),
          streamSampleTimeout: Duration(milliseconds: 20),
        ),
      );

      expect(result.canStream, isFalse);
      expect(result.failureReason, PlaybackRemotePreflightFailureReason.timeout);
    });

    test('reports server failure for 5xx', () async {
      final helper = PlaybackRemotePreflight(
        clientFactory: () => MockClient((_) async => http.Response('', 503)),
      );
      const target = PlaybackTarget(
        title: 'Server Error',
        sourceId: 'nas-main',
        streamUrl: 'https://cdn.example.com/video.mkv',
        sourceName: 'NAS',
        sourceKind: MediaSourceKind.nas,
      );

      final result = await helper.probe(target);

      expect(result.canStream, isFalse);
      expect(result.acceptableStatus, isFalse);
      expect(result.failureReason, PlaybackRemotePreflightFailureReason.serverError);
    });

    test('prefers actual remote address when stream url points to loopback relay',
        () async {
      http.BaseRequest? capturedRequest;
      final helper = PlaybackRemotePreflight(
        clientFactory: () => MockClient((request) async {
          capturedRequest = request;
          return http.Response.bytes(
            List<int>.filled(512, 1),
            206,
            headers: const <String, String>{
              'content-range': 'bytes 0-511/4096',
            },
          );
        }),
      );
      const target = PlaybackTarget(
        title: 'Relay Media',
        sourceId: 'quark-main',
        streamUrl: 'http://127.0.0.1:55065/playback-relay/session/video.mp4',
        actualAddress: 'https://download.example.com/video.mp4?token=abc',
        sourceName: 'Quark',
        sourceKind: MediaSourceKind.quark,
      );

      final result = await helper.probe(target);

      expect(capturedRequest, isNotNull);
      expect(
        capturedRequest!.url.toString(),
        'https://download.example.com/video.mp4?token=abc',
      );
      expect(result.canStream, isTrue);
    });
  });
}
