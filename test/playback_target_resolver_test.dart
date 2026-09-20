import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/media_server_client.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_target_resolver.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  const nasSource = MediaSourceConfig(
    id: 'nas',
    name: 'NAS',
    kind: MediaSourceKind.nas,
    endpoint: 'https://nas.test/dav/',
    enabled: true,
    username: 'current-user',
    password: 'current-password',
  );
  final nasTarget = PlaybackTarget(
    title: 'Cached NAS',
    sourceId: nasSource.id,
    sourceName: nasSource.name,
    sourceKind: MediaSourceKind.nas,
    streamUrl: '${nasSource.endpoint}movie.mkv',
    headers: {
      'Authorization':
          'Basic ${base64Encode(utf8.encode('old-user:old-password'))}',
      'Cookie': 'old-session=synthetic',
    },
  );

  PlaybackTargetResolver nasResolver(
      {List<MediaSourceConfig> sources = const [nasSource]}) {
    final transport = MockClient((_) async =>
        fail('Resolving a cached NAS direct URL must not issue HTTP requests'));
    addTearDown(transport.close);
    final container = ProviderContainer(overrides: [
      appSettingsProvider.overrideWithValue(
          SeedData.defaultSettings.copyWith(mediaSources: sources)),
      webDavNasClientProvider.overrideWithValue(WebDavNasClient(transport)),
    ]);
    addTearDown(container.dispose);
    return PlaybackTargetResolver(read: container.read);
  }

  for (final url in [
    'https://foreign.test/movie.mkv?signature=a%2Fb&part=1&part=2',
    'http://nas.test/dav/movie.mkv',
    'https://nas.test:444/dav/movie.mkv',
    'https://nas.test/private/movie.mkv',
    'https://nas.test/dav-other/movie.mkv',
    'https://nas.test/dav/%2e%2e/private/movie.mkv',
    'https://nas.test/dav/a%2f..%2fmovie.mkv',
  ]) {
    test('resolver strips cached NAS authentication outside source $url',
        () async {
      final target = nasTarget.copyWith(streamUrl: url);
      expect(target.needsResolution, isFalse);
      final resolved = await nasResolver().resolve(target);
      expect(resolved.headers, isEmpty);
      expect(resolved.streamUrl, url);
    });
  }

  test('resolver replaces cached NAS Basic with current source credentials',
      () async {
    final resolved = await nasResolver().resolve(
        nasTarget.copyWith(streamUrl: 'https://nas.test:443/dav/movie.mkv'));
    expect(resolved.headers, {
      'Accept': '*/*',
      'Authorization':
          'Basic ${base64Encode(utf8.encode('current-user:current-password'))}',
    });
  });

  test('resolver does not retain NAS auth after endpoint or username changes',
      () async {
    final moved = nasSource.copyWith(endpoint: 'https://new-nas.test/dav/');
    expect((await nasResolver(sources: [moved]).resolve(nasTarget)).headers,
        isEmpty);
    final anonymous = nasSource.copyWith(username: '', password: '');
    expect((await nasResolver(sources: [anonymous]).resolve(nasTarget)).headers,
        {'Accept': '*/*'});
  });

  test('resolver rejects cached NAS targets with removed or replaced source',
      () async {
    for (final sources in [
      <MediaSourceConfig>[],
      [nasSource.copyWith(kind: MediaSourceKind.emby)],
    ]) {
      await expectLater(nasResolver(sources: sources).resolve(nasTarget),
          throwsA(isA<Exception>()));
    }
  });

  test('foreign NAS direct receiver never sees old Basic credentials',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = <Map<String, String>>[];
    server.listen((request) async {
      final headers = <String, String>{};
      request.headers
          .forEach((name, values) => headers[name] = values.join(','));
      received.add(headers);
      request.response.write('synthetic-media');
      await request.response.close();
    });
    final resolved = await nasResolver().resolve(nasTarget.copyWith(
        streamUrl: 'http://127.0.0.1:${server.port}/movie.mkv'));
    final transport = IOClient();
    addTearDown(transport.close);
    final response = await transport
        .get(Uri.parse(resolved.streamUrl), headers: resolved.headers)
        .timeout(const Duration(seconds: 5));
    expect(response.body, 'synthetic-media');
    expect(received, hasLength(1));
    expect(received.single, isNot(contains('authorization')));
    expect(received.single, isNot(contains('cookie')));
  });

  const embySource = MediaSourceConfig(
    id: 'emby',
    name: 'Emby',
    kind: MediaSourceKind.emby,
    endpoint: 'https://nas.test/emby',
    enabled: true,
    accessToken: 'synthetic-session-token',
    userId: 'user',
    deviceId: 'device',
  );
  const embyTarget = PlaybackTarget(
    title: 'Cached Emby',
    sourceId: 'emby',
    sourceName: 'Emby',
    sourceKind: MediaSourceKind.emby,
    streamUrl: 'https://cdn.test/movie.mkv',
    itemId: 'movie',
    headers: {
      'X-Emby-Token': 'synthetic-session-token',
      'x-emby-authorization': 'Emby Token="synthetic-session-token"',
      'Authorization': 'Bearer synthetic-session-token',
      'X-Echo': 'synthetic-session-token',
      'User-Agent': 'Stream Agent',
      'Referer': 'https://player.test/',
    },
  );

  PlaybackTargetResolver embyResolver(
      {List<MediaSourceConfig> sources = const [embySource]}) {
    final transport = MockClient((_) async =>
        fail('Resolving a cached Emby URL must not issue HTTP requests'));
    addTearDown(transport.close);
    final container = ProviderContainer(overrides: [
      appSettingsProvider.overrideWithValue(
          SeedData.defaultSettings.copyWith(mediaSources: sources)),
      mediaServerClientProvider(MediaSourceKind.emby)
          .overrideWithValue(EmbyApiClient(transport)),
    ]);
    addTearDown(container.dispose);
    return PlaybackTargetResolver(read: container.read);
  }

  for (final url in [
    'https://cdn.test/movie.mkv?signature=cdn-only',
    '//cdn.test/movie.mkv',
    'http://nas.test/emby/movie.mkv',
    'https://nas.test:444/emby/movie.mkv',
  ]) {
    test('resolver sanitizes cached Emby direct URL $url', () async {
      final target = embyTarget.copyWith(streamUrl: url);
      expect(target.needsResolution, isFalse);
      final resolved = await embyResolver().resolve(target);
      expect(resolved.streamUrl, url.startsWith('//') ? 'https:$url' : url);
      expect(resolved.headers, {
        'User-Agent': 'Stream Agent',
        'Referer': 'https://player.test/',
      });
      expect(resolved.streamUrl, isNot(contains(embySource.accessToken)));
      expect(resolved.itemId, target.itemId);
    });
  }

  for (final url in [
    '/Videos/movie.mkv',
    'https://nas.test/emby/Videos/movie.mkv',
    'https://nas.test:443/emby/Videos/movie.mkv',
  ]) {
    test('resolver preserves authenticated same-origin Emby direct URL $url',
        () async {
      final resolved =
          await embyResolver().resolve(embyTarget.copyWith(streamUrl: url));
      final uri = Uri.parse(resolved.streamUrl);
      expect(uri.path, '/emby/Videos/movie.mkv');
      expect(uri.queryParameters['api_key'], embySource.accessToken);
      expect(resolved.headers, {
        'User-Agent': 'Stream Agent',
        'Referer': 'https://player.test/',
      });
    });
  }

  test('resolver preserves CDN-specific auth without an active Emby login',
      () async {
    final source = embySource.copyWith(userId: '');
    expect(source.hasActiveSession, isFalse);
    final resolved = await embyResolver(sources: [source]).resolve(
      embyTarget.copyWith(headers: {
        ...embyTarget.headers,
        'Authorization': 'Bearer cdn-only',
      }),
    );
    expect(resolved.streamUrl, embyTarget.streamUrl);
    expect(resolved.headers['Authorization'], 'Bearer cdn-only');
    expect(resolved.headers.toString(), isNot(contains(source.accessToken)));
  });

  for (final url in [
    'https://cdn.test/movie?api_key=synthetic-session-token',
    'https://cdn.test/movie?echo=synthetic%2Dsession%2Dtoken',
    'https://user:password@cdn.test/movie',
    'file:///movie.mkv',
  ]) {
    test('resolver rejects unsafe cached Emby URL $url', () async {
      await expectLater(
          embyResolver().resolve(embyTarget.copyWith(streamUrl: url)),
          throwsA(isA<EmbyApiException>()));
    });
  }

  test('resolver fails closed for removed or replaced Emby sources', () async {
    for (final sources in [
      <MediaSourceConfig>[],
      [embySource.copyWith(kind: MediaSourceKind.nas)],
    ]) {
      await expectLater(embyResolver(sources: sources).resolve(embyTarget),
          throwsA(isA<Exception>()));
    }
  });

  for (final auth in [
    {'X-Emby-Token': 'historical-session'},
    {'x-emby-authorization': 'Emby Client="old", Token="historical-session"'},
    {'Authorization': 'MediaBrowser Token="historical-session"'},
    {'Authorization': 'Emby Token=historical-session'},
  ]) {
    test('resolver isolates rotated session from cached ${auth.keys.single}',
        () async {
      final resolved = await embyResolver().resolve(embyTarget.copyWith(
        headers: {
          ...auth,
          'X-Echo': 'historical-session',
          'Cookie': 'session=historical-session',
          'User-Agent': 'Stream Agent',
        },
      ));
      expect(resolved.headers, {'User-Agent': 'Stream Agent'});
      await expectLater(
          embyResolver().resolve(embyTarget.copyWith(
            streamUrl: 'https://cdn.test/movie?echo=historical-session',
            headers: auth,
          )),
          throwsA(isA<EmbyApiException>()));
    });
  }

  test('old x-emby token also removes its cached Bearer alias', () async {
    final resolved = await embyResolver().resolve(embyTarget.copyWith(headers: {
      'X-Emby-Token': 'historical-session',
      'Authorization': 'Bearer historical-session',
      'User-Agent': 'Stream Agent',
    }));
    expect(resolved.headers, {'User-Agent': 'Stream Agent'});
  });

  for (final key in ['api_key', 'API_KEY', '%61pi_key']) {
    test('external cached $key is rejected even without a matching header',
        () async {
      await expectLater(
          embyResolver().resolve(embyTarget.copyWith(
            streamUrl:
                'https://cdn.test/movie?$key=historical-session&signature=independent',
            headers: const {'User-Agent': 'Stream Agent'},
          )),
          throwsA(isA<EmbyApiException>()));
    });
  }

  test('same-origin historical keys become one current key without query loss',
      () async {
    final resolved = await embyResolver().resolve(embyTarget.copyWith(
      streamUrl:
          '/Videos/movie?signature=a%2Fb%2Bc&part=1&part=2&api_key=historical-session&API_KEY=older-session',
      headers: const {
        'Authorization': 'Bearer historical-session',
        'X-Echo': 'older-session',
        'User-Agent': 'Stream Agent',
      },
    ));
    expect(Uri.parse(resolved.streamUrl).query,
        'signature=a%2Fb%2Bc&part=1&part=2&api_key=${embySource.accessToken}');
    expect(resolved.headers, {'User-Agent': 'Stream Agent'});
  });

  test('missing current token never reuses a historical same-origin session',
      () async {
    final source = embySource.copyWith(accessToken: '');
    await expectLater(
        embyResolver(sources: [source]).resolve(embyTarget.copyWith(
            streamUrl: '${source.endpoint}/movie?api_key=historical-session')),
        throwsA(isA<EmbyApiException>()));
  });

  test('independent external signed query and auth survive session cleanup',
      () async {
    const url =
        'https://cdn.test/movie?token=cdn-token&X-Amz-Signature=a%2Fb%2Bc&part=1&part=2';
    final resolved = await embyResolver().resolve(embyTarget.copyWith(
      streamUrl: url,
      headers: const {
        'X-Emby-Token': 'historical-session',
        'X-Emby-Authorization': 'Emby Token="historical-session"',
        'Authorization': 'Bearer cdn-token',
        'Cookie': 'cdn_session=independent',
      },
    ));
    expect(resolved.streamUrl, url);
    expect(resolved.headers, {
      'Authorization': 'Bearer cdn-token',
      'Cookie': 'cdn_session=independent',
    });
  });

  test('resolved Emby playback does not forward source headers on redirect',
      () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final destination = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => origin.close(force: true));
    addTearDown(() => destination.close(force: true));
    final seen = <({Uri uri, Map<String, String> headers})>[];
    void record(HttpRequest request) {
      final headers = <String, String>{};
      request.headers
          .forEach((name, values) => headers[name] = values.join(','));
      seen.add((uri: request.uri, headers: headers));
    }

    origin.listen((request) async {
      record(request);
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(HttpHeaders.locationHeader,
          'http://127.0.0.1:${destination.port}/movie.mkv');
      await request.response.close();
    });
    destination.listen((request) async {
      record(request);
      request.response.write('synthetic-media');
      await request.response.close();
    });
    final source =
        embySource.copyWith(endpoint: 'http://127.0.0.1:${origin.port}/emby');
    final resolved =
        await embyResolver(sources: [source]).resolve(embyTarget.copyWith(
      streamUrl: '${source.endpoint}/movie.mkv?api_key=historical-session',
      headers: const {
        'X-Emby-Token': 'historical-session',
        'Authorization': 'Bearer historical-session',
        'User-Agent': 'Stream Agent',
      },
    ));
    expect(resolved.headers['User-Agent'], 'Stream Agent');
    final transport = IOClient();
    addTearDown(transport.close);
    final response = await transport
        .get(Uri.parse(resolved.streamUrl), headers: resolved.headers)
        .timeout(const Duration(seconds: 5));
    expect(response.body, 'synthetic-media');
    expect(seen, hasLength(2));
    expect(seen.first.uri.queryParameters['api_key'], source.accessToken);
    for (final request in seen) {
      expect(request.headers.toString(), isNot(contains(source.accessToken)));
      expect(request.headers.toString(), isNot(contains('historical-session')));
      expect(request.headers.keys.any((key) => key.startsWith('x-emby-')),
          isFalse);
    }
    expect(seen.last.uri.query, isEmpty);
  });

  test('PlaybackTargetResolver returns direct Quark targets with headers',
      () async {
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWithValue(
          SeedData.defaultSettings.copyWith(
            mediaSources: const [
              MediaSourceConfig(
                id: 'quark-main',
                name: 'Quark Drive',
                kind: MediaSourceKind.quark,
                endpoint: '0',
                libraryPath: '/',
                enabled: true,
              ),
            ],
            networkStorage: const NetworkStorageConfig(
              quarkCookie: 'kps=test; sign=test;',
            ),
          ),
        ),
        quarkSaveClientProvider.overrideWithValue(
          QuarkSaveClient(
            MockClient((request) async {
              expect(request.url.path, '/1/clouddrive/file/download');
              return http.Response(
                jsonEncode({
                  'code': 0,
                  'data': {
                    'download_list': [
                      {
                        'fid': 'quark-file-1',
                        'download_url':
                            'https://download.example.com/quark-file-1.mkv',
                        'size': 3221225472,
                      },
                    ],
                  },
                }),
                200,
                headers: const {
                  'set-cookie': '__puus=abc; Path=/',
                },
              );
            }),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final resolver = PlaybackTargetResolver(read: container.read);
    final target = const PlaybackTarget(
      title: '请求救援 S01E01',
      sourceId: 'quark-main',
      sourceName: 'Quark Drive',
      sourceKind: MediaSourceKind.quark,
      allowResume: false,
      streamUrl: '',
      itemId: 'quark-file-1',
      itemType: 'episode',
      container: 'mkv',
    );

    final resolved = await resolver.resolve(target);

    expect(
      resolved.streamUrl,
      'https://download.example.com/quark-file-1.mkv',
    );
    expect(resolved.actualAddress,
        'https://download.example.com/quark-file-1.mkv');
    expect(resolved.headers['Cookie'], contains('__puus=abc'));
    expect(resolved.fileSizeBytes, 3221225472);
    expect(resolved.allowResume, isFalse);
  });

  test('PlaybackTargetResolver resolves Quark resource ids to file ids',
      () async {
    final requestedFids = <String>[];
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWithValue(
          SeedData.defaultSettings.copyWith(
            mediaSources: const [
              MediaSourceConfig(
                id: 'quark-main',
                name: 'Quark Drive',
                kind: MediaSourceKind.quark,
                endpoint: '0',
                libraryPath: '/',
                enabled: true,
              ),
            ],
            networkStorage: const NetworkStorageConfig(
              quarkCookie: 'kps=test; sign=test;',
            ),
          ),
        ),
        quarkSaveClientProvider.overrideWithValue(
          QuarkSaveClient(
            MockClient((request) async {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              requestedFids.addAll(
                (body['fids'] as List<dynamic>? ?? const [])
                    .map((item) => '$item'),
              );
              return http.Response(
                jsonEncode({
                  'code': 0,
                  'data': {
                    'download_list': [
                      {
                        'fid': 'quark-file-2',
                        'download_url':
                            'https://download.example.com/quark-file-2.mkv',
                        'size': 1234,
                      },
                    ],
                  },
                }),
                200,
              );
            }),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final resolver = PlaybackTargetResolver(read: container.read);
    final target = const PlaybackTarget(
      title: 'Quark Movie',
      sourceId: 'quark-main',
      streamUrl: '',
      sourceName: 'Quark Drive',
      sourceKind: MediaSourceKind.quark,
      itemId: 'quark://entry/quark-file-2?path=%2FMovies%2FMovie.2024.mkv',
      itemType: 'movie',
    );

    final resolved = await resolver.resolve(target);

    expect(requestedFids, ['quark-file-2']);
    expect(resolved.itemId, 'quark-file-2');
    expect(
      resolved.streamUrl,
      'https://download.example.com/quark-file-2.mkv',
    );
    expect(resolved.actualAddress,
        'https://download.example.com/quark-file-2.mkv');
  });

  test('PlaybackTargetResolver resets stale loopback relay targets for Quark',
      () async {
    final requestedFids = <String>[];
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWithValue(
          SeedData.defaultSettings.copyWith(
            mediaSources: const [
              MediaSourceConfig(
                id: 'quark-main',
                name: 'Quark Drive',
                kind: MediaSourceKind.quark,
                endpoint: '0',
                libraryPath: '/',
                enabled: true,
              ),
            ],
            networkStorage: const NetworkStorageConfig(
              quarkCookie: 'kps=test; sign=test;',
            ),
          ),
        ),
        quarkSaveClientProvider.overrideWithValue(
          QuarkSaveClient(
            MockClient((request) async {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              requestedFids.addAll(
                (body['fids'] as List<dynamic>? ?? const [])
                    .map((item) => '$item'),
              );
              return http.Response(
                jsonEncode({
                  'code': 0,
                  'data': {
                    'download_list': [
                      {
                        'fid': 'quark-file-stale',
                        'download_url':
                            'https://download.example.com/fresh-quark-file.mp4',
                        'size': 2048,
                      },
                    ],
                  },
                }),
                200,
                headers: const {
                  'set-cookie': '__puus=fresh; Path=/',
                },
              );
            }),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final resolver = PlaybackTargetResolver(read: container.read);
    final target = const PlaybackTarget(
      title: 'Quark Resume',
      sourceId: 'quark-main',
      sourceName: 'Quark Drive',
      sourceKind: MediaSourceKind.quark,
      streamUrl: 'http://127.0.0.1:55065/playback-relay/stale/movie.mp4',
      actualAddress: 'https://webdav.example.com/quark/movie.strm',
      itemId: 'quark-file-stale',
      itemType: 'movie',
      container: 'mp4',
    );

    final resolved = await resolver.resolve(target);

    expect(requestedFids, ['quark-file-stale']);
    expect(
      resolved.streamUrl,
      'https://download.example.com/fresh-quark-file.mp4',
    );
    expect(
      resolved.actualAddress,
      'https://download.example.com/fresh-quark-file.mp4',
    );
    expect(resolved.headers['Cookie'], contains('__puus=fresh'));
  });
}
