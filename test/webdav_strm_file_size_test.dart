import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

const _source = MediaSourceConfig(
  id: 'nas',
  name: 'NAS',
  kind: MediaSourceKind.nas,
  endpoint: 'https://nas.example.com/dav/',
  enabled: true,
  username: 'alice',
  password: 'secret',
);
const _target = PlaybackTarget(
  title: 'Movie',
  sourceId: 'nas',
  sourceName: 'NAS',
  sourceKind: MediaSourceKind.nas,
  streamUrl: 'https://nas.example.com/dav/movie.strm',
  actualAddress: '/dav/movie.strm',
  container: 'strm',
  fileSizeBytes: 128,
);

Future<PlaybackTarget> _resolve(
  Future<http.Response> Function(http.Request) handler, {
  String mediaUrl = 'https://media.example.com/movie.mkv',
}) {
  final client = WebDavNasClient(MockClient((request) async {
    if (request.url.path.endsWith('.strm')) {
      return http.Response(mediaUrl, 200);
    }
    return handler(request);
  }));
  return client.resolvePlaybackTarget(source: _source, target: _target);
}

void main() {
  test('failed probe clears the STRM wrapper size', () async {
    final resolved = await _resolve((_) async => http.Response('', 403));
    expect(resolved.streamUrl, 'https://media.example.com/movie.mkv');
    expect(resolved.fileSizeBytes, 0);
    expect(resolved.fileSizeLabel, isEmpty);
    expect(resolved.actualAddress, _target.actualAddress);
  });

  for (final method in ['HEAD', 'GET']) {
    test('$method partial response uses total size instead of chunk length',
        () async {
      final resolved = await _resolve((request) async {
        if (request.method != method) return http.Response('', 405);
        return http.Response('', 206, headers: {
          'content-length': '1',
          'content-range': 'Bytes 0-0/3221225472',
        });
      });
      expect(resolved.fileSizeBytes, 3221225472);
    });
  }

  for (final range in [null, 'bytes 0-0/*', 'bytes 5-2/10', 'bytes 0-10/10']) {
    test('partial response with invalid total $range never uses chunk size',
        () async {
      final resolved =
          await _resolve((_) async => http.Response('', 206, headers: {
                'content-length': '1',
                if (range != null) 'content-range': range,
              }));
      expect(resolved.fileSizeLabel, isEmpty);
    });
  }

  test('Range ignored with 200 uses complete content length', () async {
    final resolved = await _resolve((request) async {
      if (request.method == 'HEAD') return http.Response('', 405);
      expect(request.headers['range'], 'bytes=0-0');
      expect(request.headers['accept-encoding'], 'identity');
      return http.Response('', 200, headers: {'content-length': '4294967296'});
    });
    expect(resolved.fileSizeBytes, 4294967296);
  });

  for (final type in [
    'text/html',
    'application/json',
    'application/vnd.apple.mpegurl',
    'application/x-mpegURL',
    'application/dash+xml',
  ]) {
    test('$type document length is not a video size', () async {
      final resolved = await _resolve((_) async => http.Response('', 200,
          headers: {'content-length': '512', 'content-type': type}));
      expect(resolved.fileSizeLabel, isEmpty);
    });
  }

  test('playlist URLs are not probed for a file size', () async {
    final resolved = await _resolve((_) async {
      fail('Playlist byte size is not the video size');
    }, mediaUrl: 'https://media.example.com/movie.m3u8');
    expect(resolved.fileSizeLabel, isEmpty);
  });

  test('compressed response length is not used as original file size',
      () async {
    final resolved = await _resolve((_) async => http.Response('', 200,
        headers: {'content-length': '512', 'content-encoding': 'gzip'}));
    expect(resolved.fileSizeLabel, isEmpty);
  });

  for (final method in ['HEAD', 'GET']) {
    test('$method follows redirects without forwarding NAS credentials',
        () async {
      final visited = <String>[];
      final resolved = await _resolve((request) async {
        if (request.method != method) return http.Response('', 405);
        visited.add(request.url.toString());
        if (request.url.path == '/dav/video') {
          expect(request.headers['authorization'], startsWith('Basic '));
          return http.Response('', 302, headers: {'location': 'next'});
        }
        if (request.url.path == '/dav/next') {
          expect(request.headers['authorization'], startsWith('Basic '));
          return http.Response('', 307, headers: {
            'location': 'https://cdn.example.com/video?signature=cdn',
          });
        }
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.headers.containsKey('cookie'), isFalse);
        if (request.url.host == 'cdn.example.com') {
          return http.Response('', 302,
              headers: {'location': 'https://nas.example.com/dav/final'});
        }
        return http.Response('', 200,
            headers: {'content-length': '3221225472'});
      }, mediaUrl: 'https://nas.example.com/dav/video');
      expect(visited, hasLength(4));
      expect(resolved.fileSizeBytes, 3221225472);
    });
  }

  test('redirect loops stop at a bounded number of requests', () async {
    var count = 0;
    final resolved = await _resolve((_) async {
      count++;
      return http.Response('', 302, headers: {'location': '/loop'});
    });
    expect(count, 12);
    expect(resolved.fileSizeLabel, isEmpty);
  });

  test('non-HTTP redirect targets are not requested', () async {
    final resolved = await _resolve((request) async {
      expect(request.url.scheme, 'https');
      return http.Response('', 302, headers: {'location': 'file:///movie.mkv'});
    });
    expect(resolved.fileSizeLabel, isEmpty);
  });

  test('probe cancels the video body without waiting for stream completion',
      () async {
    var cancelled = false;
    final body = StreamController<List<int>>(
      onCancel: () => cancelled = true,
    );
    final client = WebDavNasClient(MockClient.streaming((request, _) async {
      if (request.url.path.endsWith('.strm')) {
        return http.StreamedResponse(
          Stream.value('https://media.example.com/video'.codeUnits),
          200,
        );
      }
      if (request.method == 'HEAD') {
        return http.StreamedResponse(const Stream.empty(), 405);
      }
      return http.StreamedResponse(body.stream, 200,
          headers: {'content-length': '3221225472'});
    }));
    final resolved =
        await client.resolvePlaybackTarget(source: _source, target: _target);
    expect(resolved.fileSizeBytes, 3221225472);
    expect(cancelled, isTrue);
    await body.close();
  });
}
