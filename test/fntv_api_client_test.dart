import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/library/data/fntv_api_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_source_identity.dart';
import 'package:starflow/features/library/presentation/library_page.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

const source = MediaSourceConfig(
  id: 'fntv-source',
  name: 'NAS Video',
  kind: MediaSourceKind.fntv,
  endpoint: 'https://nas.example.com',
  enabled: true,
  username: 'alice',
  accessToken: 'session-token',
  userId: 'user-1',
);

http.Response ok(Object? data) => http.Response(
      jsonEncode({'code': 0, 'data': data}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('configuration, navigation and source identity preserve fntv', () {
    final restored = MediaSourceConfig.fromJson(source.toJson());
    expect(restored.kind, MediaSourceKind.fntv);
    expect(restored.connectionStatusLabel, '已登录');
    expect(
        mediaSourceResourceIdentity(restored),
        isNot(mediaSourceResourceIdentity(
            source.copyWith(kind: MediaSourceKind.emby))));
    expect(visibleLibraryFiltersForSources([source]),
        [LibraryFilter.all, LibraryFilter.fntv]);
    expect(FntvApiClient.baseUri('https://nas.example.com/proxy/v/').toString(),
        'https://nas.example.com/proxy');
    expect(() => FntvApiClient.baseUri('https://user:password@nas.example.com'),
        throwsA(isA<FntvApiException>()));
  });

  test('Authx signs the exact JSON bytes and sorted query', () {
    String digest(String data) => md5.convert(utf8.encode(data)).toString();
    const body = '{"username":"alice","password":" p "}';
    final expected = digest([
      'NDzZTVxnRKP8Z0jXg1VAMonaG8akvh',
      '/v/api/v1/login',
      '123456',
      '1700000000000',
      digest(body),
      '16CCEB3D-AB42-077D-36A1-F355324E4237',
    ].join('_'));
    expect(
        FntvApiClient.buildAuthx(
            path: '/v/api/v1/login',
            nonce: '123456',
            timestamp: 1700000000000,
            body: body),
        'nonce=123456&timestamp=1700000000000&sign=$expected');
    expect(
        FntvApiClient.buildAuthx(
            path: '/test',
            nonce: '123456',
            timestamp: 1,
            query: {'b': '2', 'a': '1'}),
        FntvApiClient.buildAuthx(
            path: '/test',
            nonce: '123456',
            timestamp: 1,
            query: {'a': '1', 'b': '2'}));
  });

  test('login sends no old session and validates user before saving', () async {
    final requests = <http.Request>[];
    final client = FntvApiClient(MockClient((request) async {
      requests.add(request);
      expect(request.followRedirects, false);
      expect(request.headers['Authx'], contains('sign='));
      if (request.url.path.endsWith('/login')) {
        expect(request.headers.containsKey('Authorization'), false);
        expect(jsonDecode(request.body), {
          'username': 'alice',
          'password': ' p ',
          'app_name': 'trimemedia-web',
        });
        return ok({'token': 'new-token'});
      }
      expect(request.url.path, '/v/api/v1/user/info');
      expect(request.headers['Authorization'], 'new-token');
      expect(request.headers['Cookie'], 'Trim-MC-token=new-token');
      return ok({'guid': 'new-user', 'username': 'Alice'});
    }));
    final result = await client.authenticate(source: source, password: ' p ');
    expect(result.accessToken, 'new-token');
    expect(result.userId, 'new-user');
    expect(result.username, 'Alice');
    expect(requests, hasLength(2));
  });

  test('library paginates, maps artwork and only queries selected sections',
      () async {
    final pages = <int>[];
    final client = FntvApiClient(MockClient((request) async {
      if (request.url.path.endsWith('/mediadb/list')) {
        return ok([
          {'guid': 'movies', 'title': 'Movies', 'category': 'Movie'},
          {'guid': 'other', 'title': 'Other', 'category': 'Movie'},
          {'guid': 'live', 'title': 'Live', 'category': 'IPTV'},
        ]);
      }
      final body = jsonDecode(request.body) as Map;
      expect(body['ancestor_guid'], 'movies');
      expect(body['exclude_grouped_video'], 1);
      expect(body['tags'], {
        'type': ['Movie', 'TV', 'Directory', 'Video', 'LiveChannel'],
      });
      final page = body['page'] as int;
      pages.add(page);
      return ok({
        'total': 101,
        'list': [
          for (var i = 0; i < (page == 1 ? 100 : 1); i++)
            {
              'guid': 'movie-$page-$i',
              'title': 'Movie $page $i',
              'type': 'Movie',
              'poster': i == 0
                  ? '/covers/poster.jpg'
                  : 'https://images.example.com/poster.jpg',
              'release_date': '2024-01-01',
              'duration': 5400,
              'create_time': 1700000000,
            },
        ]
      });
    }));
    final items = await client.fetchLibrary(
        source.copyWith(featuredSectionIds: ['movies']),
        limit: 150);
    expect(items, hasLength(101));
    expect(pages, [1, 2]);
    expect(items.first.sourceKind, MediaSourceKind.fntv);
    final localPosterItem = items.firstWhere((item) => item.id == 'movie-1-0');
    expect(localPosterItem.posterUrl,
        'https://nas.example.com/v/api/v1/sys/img/covers/poster.jpg?w=480');
    expect(localPosterItem.posterHeaders['Authorization'], 'session-token');
    expect(items.firstWhere((item) => item.id == 'movie-1-1').posterHeaders,
        isEmpty);
    expect(items.first.year, 2024);
    expect(PlaybackTarget.fromMediaItem(items.first).needsResolution, true);
    pages.clear();
    expect(
        await client.fetchLibrary(
            source.copyWith(featuredSectionIds: [kNoSectionsSelectedSentinel])),
        isEmpty);
    expect(
        await client.fetchLibrary(
            source.copyWith(featuredSectionIds: ['movies']),
            sectionId: 'other'),
        isEmpty);
    expect(pages, isEmpty);
  });

  test('series and season children map to app hierarchy in episode order',
      () async {
    final client = FntvApiClient(MockClient((request) async {
      switch (request.url.path) {
        case '/v/api/v1/item/show':
          return ok({'type': 'TV'});
        case '/v/api/v1/item/season':
          return ok({'type': 'Season'});
        case '/v/api/v1/season/list/show':
          return ok([
            {
              'guid': 'season',
              'title': 'Season 1',
              'type': 'Season',
              'season_number': 1
            },
          ]);
        case '/v/api/v1/episode/list/season':
          return ok([
            for (final n in [2, 1])
              {
                'guid': 'episode-$n',
                'title': 'Episode $n',
                'type': 'Episode',
                'season_number': 1,
                'episode_number': n
              },
          ]);
      }
      fail('Unexpected path ${request.url.path}');
    }));
    final seasons = await client.fetchChildren(source, parentId: 'show');
    expect(seasons.single.isFolder, true);
    final episodes = await client.fetchChildren(source, parentId: 'season');
    expect(episodes.map((item) => item.episodeNumber), [1, 2]);
    expect(episodes.every((item) => item.isPlayable), true);
  });

  test('folder children keep grouped episodes visible in title order',
      () async {
    final requests = <http.Request>[];
    final client = FntvApiClient(MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/v/api/v1/item/folder') {
        return ok({'type': 'Directory'});
      }
      expect(request.url.path, '/v/api/v1/item/list');
      expect(jsonDecode(request.body), {
        'parent_guid': 'folder',
        'exclude_grouped_video': 0,
        'sort_type': 'ASC',
        'sort_column': 'sort_title',
        'page_size': 50,
        'page': 1,
        'tags': {
          'type': ['Movie', 'TV', 'Directory', 'Video', 'LiveChannel'],
        },
      });
      return ok({
        'total': 2,
        'list': [
          {
            'guid': 'episode',
            'title': 'Episode 1',
            'type': 'Episode',
            'episode_number': 1,
          },
          {
            'guid': 'show',
            'title': 'Show',
            'type': 'TV',
          },
        ],
      });
    }));

    final items =
        await client.fetchChildren(source, parentId: 'folder', limit: 50);
    expect(items.map((item) => item.itemType), ['episode', 'Series']);
    expect(items.map((item) => item.isPlayable), [true, false]);
    expect(requests, hasLength(2));
  });

  for (final stage in ['parent', 'season', 'episode']) {
    test('child browsing reports $stage business failure without retry',
        () async {
      var calls = 0;
      final client = FntvApiClient(MockClient((request) async {
        calls++;
        if (stage != 'parent' && request.url.path.contains('/item/')) {
          return ok({'type': stage == 'season' ? 'TV' : 'Season'});
        }
        return http.Response(
          jsonEncode({'code': -6, 'message': 'secret=session-token'}),
          200,
        );
      }));
      await expectLater(
        client.fetchChildren(source, parentId: 'missing'),
        throwsA(isA<FntvApiException>()
            .having((error) => error.isMissingItem, 'isMissingItem', true)
            .having((error) => error.businessCode, 'businessCode', -6)
            .having((error) => error.message, 'message',
                '飞牛影视条目已不存在，请更新媒体库后重新打开（错误码 -6）')),
      );
      expect(calls, stage == 'parent' ? 1 : 2);
    });
  }

  test('unnamed seasons and episodes remain browsable', () async {
    final client = FntvApiClient(MockClient((request) async {
      if (request.url.path.endsWith('/item/show')) return ok({'type': 'TV'});
      if (request.url.path.endsWith('/item/season')) {
        return ok({'type': 'Season'});
      }
      if (request.url.path.contains('/season/list/')) {
        return ok([
          {'guid': 'season', 'type': 'Season', 'title': '', 'season_number': -1}
        ]);
      }
      return ok([
        {'guid': 'ep-10', 'type': 'Episode', 'title': '', 'episode_number': 10},
        {
          'guid': 'ep-11',
          'type': 'Episode',
          'title': '',
          'episode_number': 11,
          'file_name': 'episode.strm'
        },
      ]);
    }));
    expect((await client.fetchChildren(source, parentId: 'show')).single.title,
        '未分季');
    final episodes = await client.fetchChildren(source, parentId: 'season');
    expect(episodes.map((item) => item.title), ['第 10 集', 'episode.strm']);
    expect(episodes.every((item) => item.isPlayable), isTrue);
  });

  test('playback resolves media guid, preserves artwork and carries NAS auth',
      () async {
    final client = FntvApiClient(MockClient((request) async {
      if (request.url.path.endsWith('/play/info')) {
        expect(jsonDecode(request.body)['item_guid'], 'movie');
        return ok({'media_guid': 'file'});
      }
      expect(request.url.path, '/v/api/v1/stream');
      expect(jsonDecode(request.body)['media_guid'], 'file');
      return ok({
        'file_stream': {
          'guid': 'file',
          'path': '/media/movie.mkv',
          'size': 1000,
          'can_play': 1
        }
      });
    }));
    final target =
        await client.resolvePlaybackTarget(source: source, target: _target());
    expect(
        target.streamUrl, 'https://nas.example.com/v/api/v1/media/range/file');
    expect(target.headers['Authorization'], 'session-token');
    expect(target.posterUrl, 'https://images.example.com/poster.jpg');
    expect(target.actualAddress, '/media/movie.mkv');
  });

  test('stream track metadata maps to existing player selectors', () async {
    final requests = <http.Request>[];
    final client = FntvApiClient(MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/play/info')) {
        return ok({
          'media_guid': 'file',
          'audio_guid': 'audio-zh',
          'subtitle_guid': 'subtitle-external',
        });
      }
      if (request.url.path.endsWith('/stream')) {
        return ok({
          'file_stream': {'guid': 'file', 'can_play': 1},
          'audio_streams': [
            {
              'guid': 'audio-en',
              'title': 'English',
              'language': 'en',
              'codec_name': 'eac3',
              'channels': 6,
              'index': 1,
            },
            {
              'guid': 'audio-zh',
              'title': '国语',
              'language': 'zh',
              'codec_name': 'aac',
              'channels': 2,
              'is_default': 1,
              'index': 0,
            },
          ],
          'subtitle_streams': [
            {
              'guid': 'subtitle-embedded',
              'title': '简体中文',
              'language': 'zh',
              'codec_name': 'ass',
              'is_default': 1,
              'is_external': 0,
              'index': 0,
            },
            {
              'guid': 'subtitle-external',
              'title': 'English',
              'language': 'en',
              'format': 'srt',
              'is_external': 1,
              'index': 1,
            },
          ],
        });
      }
      expect(request.url.path, '/v/api/v1/subtitle/dl/subtitle-external');
      expect(request.method, 'GET');
      expect(request.headers['Authorization'], 'session-token');
      final authx = Uri.splitQueryString(request.headers['Authx']!);
      expect(
        request.headers['Authx'],
        FntvApiClient.buildAuthx(
          path: '/v/api/v1/subtitle/dl/subtitle-external',
          nonce: authx['nonce']!,
          timestamp: int.parse(authx['timestamp']!),
        ),
      );
      return http.Response('1\n00:00:00,000 --> 00:00:02,000\nEnglish\n', 200);
    }));

    final target =
        await client.resolvePlaybackTarget(source: source, target: _target());
    expect(target.preferredAudioStreamId, 'audio-zh');
    expect(target.preferredSubtitleStreamId, 'subtitle-external');
    expect(target.audioStreams.map((stream) => stream.id),
        ['audio-en', 'audio-zh']);
    expect(target.audioStreams.last.channels, 2);
    expect(target.audioStreams.last.codec, 'aac');
    expect(target.subtitleStreams.map((stream) => stream.id),
        ['subtitle-embedded', 'subtitle-external']);
    expect(target.subtitleStreams.last.isExternal, true);
    expect(target.subtitleStreams.last.codec, 'srt');

    final restored = PlaybackTarget.fromJson(target.toJson());
    expect(restored.preferredAudioStreamId, 'audio-zh');
    expect(restored.audioStreams.last.title, '国语');
    expect(restored.subtitleStreams.last.isExternal, true);

    final subtitle = await client.downloadExternalSubtitle(
      source: source,
      subtitleId: 'subtitle-external',
    );
    expect(subtitle, contains('English'));
    expect(requests, hasLength(3));
  });

  test('direct-link qualities are mapped and selected by index', () async {
    final client = FntvApiClient(MockClient((request) async {
      if (request.url.path.endsWith('/play/info')) {
        return ok({'media_guid': 'file'});
      }
      return ok({
        'cloud_storage_info': {'cloud_storage_type': 9001},
        'file_stream': {'guid': 'file', 'can_play': 1},
        'video_stream': {'guid': 'video', 'width': 3840, 'height': 2160},
        'direct_link_qualities': [
          {
            'resolution': '1080P',
            'bitrate': 8000000,
            'url': 'https://cdn/1080'
          },
          {'resolution': '4K', 'bitrate': 25000000, 'url': 'https://cdn/4k'},
        ],
      });
    }));
    final target = await client.resolvePlaybackTarget(
      source: source,
      target: _target().copyWith(preferredPlaybackQualityIndex: 1),
    );
    expect(target.streamUrl, 'https://cdn/4k');
    expect(target.videoStreamId, 'video');
    expect(target.playbackQualities.map((quality) => quality.label), [
      '1080P · 8.0 Mbps',
      '4K · 25.0 Mbps',
    ]);
    expect(target.preferredPlaybackQualityIndex, 1);
  });

  test('Blu-ray PCM transport stream prefers the seek-safe range endpoint',
      () async {
    final client = FntvApiClient(MockClient((request) async {
      if (request.url.path.endsWith('/play/info')) {
        return ok({'media_guid': 'file'});
      }
      return ok({
        'cloud_storage_info': {'cloud_storage_type': 9001},
        'file_stream': {'guid': 'file', 'can_play': 1},
        'video_stream': {'guid': 'video', 'wrapper': 'MPEGTS'},
        'audio_streams': [
          {'guid': 'audio', 'codec_name': 'pcm_bluray'},
        ],
        'direct_link_qualities': [
          {'resolution': '1080P', 'url': 'https://cdn/episode.ts'},
        ],
      });
    }));

    final target =
        await client.resolvePlaybackTarget(source: source, target: _target());

    expect(
      target.streamUrl,
      'https://nas.example.com/v/api/v1/media/range/file'
      '?direct_link_quality_index=0',
    );
  });

  test('Blu-ray PCM in a non-transport container keeps the direct link',
      () async {
    final client = FntvApiClient(MockClient((request) async {
      if (request.url.path.endsWith('/play/info')) {
        return ok({'media_guid': 'file'});
      }
      return ok({
        'cloud_storage_info': {'cloud_storage_type': 9001},
        'file_stream': {'guid': 'file', 'can_play': 1},
        'video_stream': {'guid': 'video', 'wrapper': 'MKV'},
        'audio_streams': [
          {'guid': 'audio', 'codec_name': 'pcm_bluray'},
        ],
        'direct_link_qualities': [
          {'resolution': '1080P', 'url': 'https://cdn/movie.mkv'},
        ],
      });
    }));

    final target =
        await client.resolvePlaybackTarget(source: source, target: _target());

    expect(target.streamUrl, 'https://cdn/movie.mkv');
  });

  test(
      'server library refresh targets selected roots and falls back to all roots',
      () async {
    final refreshRequests = <Map<String, dynamic>>[];
    final client = FntvApiClient(MockClient((request) async {
      if (request.url.path.endsWith('/mediadb/list')) {
        return ok([
          {'guid': 'movies', 'title': 'Movies', 'category': 'Movie'},
          {'guid': 'shows', 'title': 'Shows', 'category': 'TV'},
          {'guid': 'music', 'title': 'Music', 'category': 'Music'},
        ]);
      }
      expect(request.url.path, '/v/api/v1/item/refresh');
      refreshRequests.add(jsonDecode(request.body) as Map<String, dynamic>);
      return ok(true);
    }));

    await client.requestLibraryRefresh(
      source.copyWith(featuredSectionIds: ['movies', 'shows']),
    );
    expect(refreshRequests, [
      {'item_guid': 'movies'},
      {'item_guid': 'shows'},
    ]);

    refreshRequests.clear();
    await client.requestLibraryRefresh(source);
    expect(refreshRequests, [
      {'item_guid': 'movies'},
      {'item_guid': 'shows'},
    ]);
  });

  test('server library refresh is skipped when no section is selected',
      () async {
    final client = FntvApiClient(MockClient((request) async {
      fail('unexpected request: ${request.url}');
    }));
    await client.requestLibraryRefresh(
      source.copyWith(featuredSectionIds: [kNoSectionsSelectedSentinel]),
    );
  });

  test(
      'quality selection retains server indices after empty entries are filtered',
      () async {
    final client = FntvApiClient(MockClient((request) async {
      if (request.url.path.endsWith('/play/info')) {
        return ok({'media_guid': 'file'});
      }
      return ok({
        'file_stream': {'guid': 'file', 'can_play': 1},
        'direct_link_qualities': [
          {},
          {'resolution': '1080P', 'url': 'https://cdn/1080'},
          {'resolution': '4K', 'url': 'https://cdn/4k'},
        ],
      });
    }));
    final selected = await client.resolvePlaybackTarget(
      source: source,
      target: _target().copyWith(preferredPlaybackQualityIndex: 2),
    );
    expect(selected.playbackQualities.map((quality) => quality.index), [1, 2]);
    expect(selected.preferredPlaybackQualityIndex, 2);
    expect(
        Uri.parse(selected.streamUrl)
            .queryParameters['direct_link_quality_index'],
        '2');
    final fallback = await client.resolvePlaybackTarget(
      source: source,
      target: _target().copyWith(preferredPlaybackQualityIndex: 99),
    );
    expect(fallback.preferredPlaybackQualityIndex, 1);
    expect(
        Uri.parse(fallback.streamUrl)
            .queryParameters['direct_link_quality_index'],
        '1');
  });

  test('play record sends clamped progress without leaking into logs',
      () async {
    http.Request? recorded;
    final client = FntvApiClient(MockClient((request) async {
      recorded = request;
      return ok({});
    }));
    final target = _target().copyWith(
      preferredMediaSourceId: 'media',
      videoStreamId: 'video',
      preferredAudioStreamId: 'audio',
      preferredSubtitleStreamId: 'subtitle',
      width: 1920,
      height: 1080,
      bitrate: 6000000,
      streamUrl: 'https://cdn.example.com/private.mkv?token=secret',
    );
    await client.reportPlaybackProgress(
      source: source,
      target: target,
      position: const Duration(seconds: 120),
      duration: const Duration(seconds: 90),
    );
    expect(recorded!.url.path, '/v/api/v1/play/record');
    final body = jsonDecode(recorded!.body) as Map<String, dynamic>;
    expect(body, {
      'item_guid': 'movie',
      'media_guid': 'media',
      'video_guid': 'video',
      'audio_guid': 'audio',
      'subtitle_guid': 'subtitle',
      'resolution': '1920x1080',
      'bitrate': 6000000,
      'ts': 90,
      'duration': 90,
      'play_link': 'https://cdn.example.com/private.mkv?token=secret',
      'device_id': isA<String>(),
      'direct_link_audio_index': -1,
      'lan': 'zh-CN',
      'device_name': 'Starflow',
    });
  });

  for (final token in ['session-token', ' refreshed-token ']) {
    test('stream negotiation includes session hash and player headers: $token',
        () async {
      final requests = <http.Request>[];
      final configuredSource = source.copyWith(accessToken: token);
      const userAgent =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36';
      final client = FntvApiClient(MockClient((request) async {
        requests.add(request);
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], token.trim());
        if (request.url.path == '/v/api/v1/play/info') {
          return ok({'media_guid': 'file'});
        }
        expect(request.url.path, '/v/api/v1/stream');
        expect(jsonDecode(request.body), {
          'media_guid': 'file',
          'ip': md5.convert(utf8.encode(token.trim())).toString(),
          'level': 1,
          'header': {
            'User-Agent': [userAgent],
          },
        });
        final authx = Uri.splitQueryString(request.headers['Authx']!);
        expect(
          request.headers['Authx'],
          FntvApiClient.buildAuthx(
            path: '/v/api/v1/stream',
            nonce: authx['nonce']!,
            timestamp: int.parse(authx['timestamp']!),
            body: request.body,
          ),
        );
        return ok({
          'file_stream': {'guid': 'file', 'can_play': 1},
        });
      }));

      final target = await client.resolvePlaybackTarget(
          source: configuredSource, target: _target());
      expect(target.headers['User-Agent'], userAgent);
      expect(target.streamUrl,
          'https://nas.example.com/v/api/v1/media/range/file');
      expect(Uri.parse(target.streamUrl).hasQuery, false);
      expect(requests, hasLength(2));
    });
  }

  for (final stage in const {
    'play/info': '读取播放信息',
    'stream': '解析媒体流',
  }.entries) {
    test('${stage.key} business failure identifies the stage without secrets',
        () async {
      var requestCount = 0;
      final client = FntvApiClient(MockClient((request) async {
        requestCount++;
        if (request.url.path == '/v/api/v1/${stage.key}') {
          return http.Response(
              jsonEncode({
                'code': -1,
                'msg': 'secret session-token https://private.example.com',
              }),
              200);
        }
        expect(request.url.path, '/v/api/v1/play/info');
        return ok({'media_guid': 'file'});
      }));
      await expectLater(
        client.resolvePlaybackTarget(source: source, target: _target()),
        throwsA(isA<FntvApiException>()
            .having((error) => error.message, 'stage', contains(stage.value))
            .having((error) => error.message, 'code', contains('-1'))
            .having(
                (error) => error.message, 'secret', isNot(contains('secret')))
            .having((error) => error.message, 'token',
                isNot(contains('session-token')))
            .having((error) => error.message, 'URL',
                isNot(contains('private.example.com')))),
      );
      expect(requestCount, stage.key == 'stream' ? 2 : 1);
    });
  }

  test('external STRM URL receives provider headers but never NAS credentials',
      () async {
    final client = FntvApiClient(MockClient((request) async {
      if (request.url.path.endsWith('/play/info')) {
        return ok({'media_guid': 'file'});
      }
      return ok({
        'cloud_storage_info': {'cloud_storage_type': 9001},
        'direct_link_qualities': [
          {'url': 'https://cdn.example.com/movie.mkv'}
        ],
        'header': {
          'user-agent': ['ProviderPlayer/1.0'],
          'Referer': ['https://cdn.example.com/'],
          'Authorization': 'session-token',
          'Cookie': 'secret'
        },
      });
    }));
    final target =
        await client.resolvePlaybackTarget(source: source, target: _target());
    expect(target.streamUrl, 'https://cdn.example.com/movie.mkv');
    expect(target.headers, {
      'user-agent': 'ProviderPlayer/1.0',
      'Referer': 'https://cdn.example.com/',
    });
  });

  test('HTTP, business and invalid JSON failures never echo server secrets',
      () async {
    for (final response in [
      http.Response('secret', 401),
      http.Response('secret', 302),
      http.Response('secret', 200),
      http.Response(jsonEncode({'code': -1, 'msg': 'secret'}), 200),
    ]) {
      final client = FntvApiClient(MockClient((_) async => response));
      await expectLater(
          client.fetchCollections(source),
          throwsA(isA<FntvApiException>().having(
              (error) => error.message, 'message', isNot(contains('secret')))));
    }
  });

  test('file variants remain unresolved and selected media guid is honored',
      () async {
    final client = FntvApiClient(MockClient((request) async {
      if (request.url.path.endsWith('/stream/list/movie')) {
        return ok({
          'files': [
            {'guid': 'hd', 'path': '/media/movie-hd.mkv', 'can_play': 1},
            {'guid': 'uhd', 'path': '/media/movie-uhd.mkv', 'can_play': 1},
            {'guid': 'unavailable', 'can_play': 0},
          ]
        });
      }
      expect(jsonDecode(request.body)['media_guid'], 'uhd');
      if (request.url.path.endsWith('/play/info')) {
        return ok({'media_guid': 'hd'});
      }
      return ok({
        'file_stream': {'guid': 'uhd', 'can_play': 1},
        'video_stream': {
          'wrapper': 'mkv',
          'bps': 50000000,
          'codec_name': 'hevc'
        }
      });
    }));
    final variants =
        await client.fetchPlaybackVariants(source: source, target: _target());
    expect(
        variants.map((target) => target.preferredMediaSourceId), ['hd', 'uhd']);
    expect(variants.every((target) => target.needsResolution), true);
    final target = await client.resolvePlaybackTarget(
        source: source, target: variants.last);
    expect(target.streamUrl, endsWith('/media/range/uhd'));
    expect(target.container, 'mkv');
    expect(target.bitrate, 50000000);
  });

  test(
      'malformed successful payload fails instead of looking like an empty library',
      () async {
    final client = FntvApiClient(MockClient((_) async => ok(null)));
    await expectLater(
        client.fetchCollections(source), throwsA(isA<FntvApiException>()));
    await expectLater(client.fetchLibrary(source, sectionId: 'movies'),
        throwsA(isA<FntvApiException>()));
  });

  test('episode endpoint accepts a bare list response', () async {
    final client = FntvApiClient(MockClient((request) async {
      if (request.url.path.contains('/item/')) return ok({'type': 'Season'});
      return http.Response(
          jsonEncode([
            {
              'guid': 'episode',
              'title': 'Episode 1',
              'type': 'Episode',
              'episode_number': 1
            },
          ]),
          200);
    }));
    expect(
        (await client.fetchChildren(source, parentId: 'season'))
            .single
            .isPlayable,
        true);
  });
}

PlaybackTarget _target() => const PlaybackTarget(
      title: 'Movie',
      sourceId: 'fntv-source',
      sourceName: 'NAS Video',
      sourceKind: MediaSourceKind.fntv,
      itemId: 'movie',
      streamUrl: '',
      posterUrl: 'https://images.example.com/poster.jpg',
    );
