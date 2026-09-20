import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

const _emby = MediaSourceConfig(
    id: 'e',
    name: 'Emby',
    kind: MediaSourceKind.emby,
    endpoint: 'https://nas.test/emby',
    enabled: true,
    username: 'test',
    accessToken: 'synthetic-private-token',
    userId: 'user',
    deviceId: 'device');
const _target = PlaybackTarget(
    title: 'Movie',
    sourceId: 'e',
    sourceName: 'Emby',
    sourceKind: MediaSourceKind.emby,
    streamUrl: '',
    itemId: 'movie');
const _nas = MediaSourceConfig(
    id: 'n',
    name: 'NAS',
    kind: MediaSourceKind.nas,
    endpoint: 'https://nas.test/dav/',
    enabled: true,
    username: 'test',
    password: 'synthetic-password');

void main() {
  test('old cached Emby targets cannot retain source session headers',
      () async {
    final client = EmbyApiClient(MockClient((_) async =>
        throw StateError('Cached targets must not fetch PlaybackInfo')));
    final target = await client.resolvePlaybackTarget(
        source: _emby,
        target:
            _target.copyWith(streamUrl: 'https://foreign.test/movie', headers: {
          'X-Emby-Token': _emby.accessToken,
          'Authorization': 'Bearer ${_emby.accessToken}',
          'User-Agent': 'Stream Agent'
        }));
    expect(target.headers, {'User-Agent': 'Stream Agent'});
  });

  test('NFO redirect cannot forward Basic credentials and media remains usable',
      () async {
    final seen = <String>[];
    final client = WebDavNasClient(MockClient((request) async {
      seen.add(request.url.toString());
      if (request.method == 'PROPFIND') {
        return http.Response(
            _xml([
              ('/dav/', true),
              ('/dav/movie.mkv', false),
              ('/dav/movie.nfo', false),
            ]),
            207);
      }
      expect(request.followRedirects, isFalse);
      expect(request.headers['authorization'], startsWith('Basic '));
      return http.Response('', 302,
          headers: {'location': 'https://foreign.test/movie.nfo'});
    }));
    final items = await client.fetchLibrary(_nas, limit: 10);
    expect(items, hasLength(1));
    expect(seen, ['https://nas.test/dav/', 'https://nas.test/dav/movie.nfo']);
  });

  for (final url in [
    'https://foreign.test/video',
    '//foreign.test/video',
    'http://nas.test/video',
    'https://nas.test:444/video'
  ]) {
    for (final addKey in [false, true]) {
      test('Emby isolates stream auth for $url addKey=$addKey', () async {
        final client = EmbyApiClient(MockClient((request) async {
          expect(request.followRedirects, isFalse);
          return http.Response(
              jsonEncode({
                'MediaSources': [
                  {
                    'Id': 'v',
                    'DirectStreamUrl': url,
                    'AddApiKeyToDirectStreamUrl': addKey,
                    'RequiredHttpHeaders': {
                      'User-Agent': 'Stream Agent',
                      'Authorization': 'Bearer cdn-only',
                      'x-emby-token': _emby.accessToken,
                      'X-Emby-Authorization':
                          'Emby Token="${_emby.accessToken}"',
                      'X-Echo': _emby.accessToken,
                    },
                  }
                ]
              }),
              200);
        }));
        final target =
            await client.resolvePlaybackTarget(source: _emby, target: _target);
        expect(target.streamUrl, isNot(contains(_emby.accessToken)));
        expect(target.headers.toString(), isNot(contains(_emby.accessToken)));
        expect(target.headers['User-Agent'], 'Stream Agent');
        expect(target.headers['Authorization'], 'Bearer cdn-only');
        expect(
            target.headers.keys
                .any((k) => k.toLowerCase().startsWith('x-emby-')),
            isFalse);
      });
    }
  }

  test('same-origin Emby stream uses URL auth, not redirect-forwarded headers',
      () async {
    final client = EmbyApiClient(MockClient((_) async => http.Response(
        jsonEncode({
          'MediaSources': [
            {
              'DirectStreamUrl': '/Videos/a',
              'AddApiKeyToDirectStreamUrl': false
            }
          ]
        }),
        200)));
    final target =
        await client.resolvePlaybackTarget(source: _emby, target: _target);
    expect(Uri.parse(target.streamUrl).queryParameters['api_key'],
        _emby.accessToken);
    expect(target.headers, isEmpty);
  });

  test('Emby rejects userInfo and echoed session tokens in external URLs',
      () async {
    for (final url in [
      'https://u:p@foreign.test/video',
      'https://foreign.test/video?api_key=${_emby.accessToken}'
    ]) {
      final client = EmbyApiClient(MockClient((_) async => http.Response(
          jsonEncode({
            'MediaSources': [
              {'DirectStreamUrl': url}
            ]
          }),
          200)));
      await expectLater(
          client.resolvePlaybackTarget(source: _emby, target: _target),
          throwsA(isA<EmbyApiException>()));
    }
  });

  test('Emby API redirect rejects foreign destination before sending',
      () async {
    final destinations = <Uri>[];
    final client = EmbyApiClient(MockClient((request) async {
      destinations.add(request.url);
      expect(request.followRedirects, isFalse);
      return http.Response('', 307,
          headers: {'location': 'https://foreign.test/api'});
    }));
    await expectLater(
        client.fetchCollections(_emby), throwsA(isA<EmbyApiException>()));
    expect(destinations.every((u) => u.host == 'nas.test'), isTrue);
  });

  test('WebDAV skips hostile directory, NFO, artwork and file hrefs', () async {
    final seen = <Uri>[];
    final client = WebDavNasClient(MockClient((request) async {
      seen.add(request.url);
      expect(request.followRedirects, isFalse);
      if (request.url.path == '/dav/') {
        return http.Response(
            _xml([
              ('/dav/', true),
              ('/dav/movie.mkv', false),
              ('https://foreign.test/evil/', true),
              ('//foreign.test/movie.nfo', false),
              ('http://nas.test/poster.jpg', false),
              ('https://nas.test:444/movie.mkv', false),
              ('/private/escape/', true),
              ('/dav-other/escape/', true),
              ('/dav/%2e%2e/escape/', true),
              ('/dav/a%2f..%2fescape/', true),
            ]),
            207);
      }
      return http.Response('', 404);
    }));
    final items = await client.fetchLibrary(_nas, limit: 10);
    expect(items, hasLength(1));
    expect(items.single.streamUrl, 'https://nas.test/dav/movie.mkv');
    expect(items.single.posterUrl, isEmpty);
    expect(seen, [Uri.parse('https://nas.test/dav/')]);
  });

  test('WebDAV direct STRM/delete and selected root cannot escape source',
      () async {
    var requests = 0;
    final client = WebDavNasClient(MockClient((_) async {
      requests++;
      return http.Response('', 200);
    }));
    for (final path in ['https://foreign.test/a.strm', '/private/a.strm']) {
      await expectLater(
          client.resolveStrmTargetUrl(source: _nas, resourcePath: path),
          throwsA(isA<WebDavNasException>()));
      await expectLater(client.deleteResource(_nas, resourcePath: path),
          throwsA(isA<WebDavNasException>()));
    }
    await expectLater(
        client.fetchCollections(_nas, directoryId: 'https://foreign.test/'),
        throwsA(isA<WebDavNasException>()));
    expect(requests, 0);
  });

  test('WebDAV NFO and PROPFIND redirects stay inside endpoint directory',
      () async {
    final seen = <String>[];
    final client = WebDavNasClient(MockClient((request) async {
      seen.add(request.url.toString());
      expect(request.followRedirects, isFalse);
      return http.Response('', 307, headers: {'location': '/private/'});
    }));
    await expectLater(
        client.fetchCollections(_nas), throwsA(isA<http.ClientException>()));
    await expectLater(
        client.resolveStrmTargetUrl(source: _nas, resourcePath: '/dav/a.strm'),
        throwsA(isA<http.ClientException>()));
    expect(seen, ['https://nas.test/dav/', 'https://nas.test/dav/a.strm']);
  });
}

String _xml(List<(String, bool)> entries) =>
    '<d:multistatus xmlns:d="DAV:">${entries.map((e) => '<d:response><d:href>${const HtmlEscape().convert(e.$1)}</d:href>'
        '<d:propstat><d:prop><d:resourcetype>${e.$2 ? '<d:collection/>' : ''}'
        '</d:resourcetype></d:prop></d:propstat></d:response>').join()}</d:multistatus>';
