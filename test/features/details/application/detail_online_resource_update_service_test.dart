import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/details/application/detail_online_resource_update_service.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/domain/cloud_save_feedback.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

http.Response _jsonResponse(
  Object? body, {
  int statusCode = 200,
  Map<String, String> headers = const {},
}) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    statusCode,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      ...headers,
    },
  );
}

void main() {
  group('DetailOnlineResourceUpdateService', () {
    const target115 = MediaDetailTarget(
        title: 'Show',
        posterUrl: '',
        overview: '',
        itemType: 'series',
        searchQuery: 'Show');
    const favorite115 = SearchResult(
        id: '115',
        title: 'Show',
        posterUrl: '',
        providerId: 'online',
        providerName: 'Online',
        quality: '',
        sizeLabel: '',
        seeders: 0,
        summary: '',
        resourceUrl: 'https://115.com/s/abc',
        password: 'abcd',
        favoriteFolderName: 'Show',
        metadataMediaType: 'series');

    test(
        'mixed online matches are stable and exclude local or unsupported favorites',
        () {
      const service = DetailOnlineResourceUpdateService();
      final matches =
          service.resolveFavoriteMatches(target: target115, favorites: [
        favorite115,
        favorite115.copyWith(resourceUrl: 'https://pan.quark.cn/s/abc'),
        favorite115.copyWith(detailTarget: target115),
        favorite115.copyWith(resourceUrl: 'https://example.com/s/abc'),
      ]);
      expect(matches.map((m) => m.drive),
          [CloudSaveDrive.cloud115, CloudSaveDrive.quark]);
      expect(searchResultSharePassword(matches.first.result), 'abcd');
      expect(
          Uri.parse(matches.first.result.resourceUrl)
              .queryParameters['password'],
          'abcd');
    });

    test('115 check uses only its configured cookie, folder and name rules',
        () async {
      const service = DetailOnlineResourceUpdateService();
      final match = service
          .resolveFavoriteMatch(target: target115, favorites: [favorite115])!;
      final quark =
          QuarkSaveClient(MockClient((_) async => fail('No Quark requests')));
      final cloud115 = Cloud115SaveClient(MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.headers['cookie'], '115-cookie');
        if (request.url.path == '/share/snap') {
          expect(request.url.queryParameters['receive_code'], 'abcd');
          return _jsonResponse({
            'state': true,
            'data': {
              'count': 2,
              'list': [
                {'fid': '1', 'n': '#E01.mkv'},
                {'fid': '2', 'n': '#E02.mkv'},
              ]
            }
          });
        }
        expect(request.url.path, '/files');
        expect(request.url.queryParameters['cid'], '42');
        return _jsonResponse({
          'state': true,
          'count': 1,
          'data': [
            {'fid': '101', 'n': 'E01.mkv'}
          ]
        });
      }));
      await expectLater(
          service.checkForUpdates(
              target: target115,
              favoriteMatch: match,
              networkStorage:
                  const NetworkStorageConfig(quarkCookie: 'quark-cookie'),
              quarkSaveClient: quark,
              cloud115SaveClient: cloud115),
          throwsA(isA<QuarkSaveException>()
              .having((e) => e.message, 'message', contains('115 Cookie'))));
      const config = NetworkStorageConfig(
          cloud115Cookie: '115-cookie',
          cloud115SaveFolderId: '42',
          cloud115SaveFolderPath: '/115/Show',
          cloud115SanitizeSavedNamesEnabled: true,
          cloud115SanitizedNameCharacters: '#',
          quarkSaveFolderId: 'unused',
          quarkSaveFolderPath: '/quark');
      final result = await service.checkForUpdates(
          target: target115,
          favoriteMatch: match,
          networkStorage: config,
          quarkSaveClient: quark,
          cloud115SaveClient: cloud115);
      expect(result.updatedEpisodeLabels, ['#E02.mkv']);
      expect(result.buildDialogMessage(), contains('115目录：/115/Show'));
      expect(result.buildDialogMessage(), isNot(contains('夸克')));
      final uncleaned = await service.checkForUpdates(
          target: target115,
          favoriteMatch: match,
          networkStorage:
              config.copyWith(cloud115SanitizeSavedNamesEnabled: false),
          quarkSaveClient: quark,
          cloud115SaveClient: cloud115);
      expect(uncleaned.updatedEpisodeLabels, ['#E01.mkv', '#E02.mkv']);
    });

    test('prefers an exact favorite folder-name match', () {
      const service = DetailOnlineResourceUpdateService();
      const target = MediaDetailTarget(
        title: '三体',
        posterUrl: '',
        overview: '',
        itemType: 'series',
        searchQuery: '三体',
      );
      const favorites = [
        SearchResult(
          id: '1',
          title: '三体全集',
          posterUrl: '',
          providerId: 'quark-1',
          providerName: 'Quark',
          quality: '',
          sizeLabel: '',
          seeders: 0,
          summary: '',
          resourceUrl: 'https://pan.quark.cn/s/abc123',
          favoriteFolderName: '三体',
          metadataMediaType: 'series',
        ),
        SearchResult(
          id: '2',
          title: '三体 第1季',
          posterUrl: '',
          providerId: 'quark-2',
          providerName: 'Quark',
          quality: '',
          sizeLabel: '',
          seeders: 0,
          summary: '',
          resourceUrl: 'https://pan.quark.cn/s/def456',
          favoriteFolderName: '别的名字',
          metadataMediaType: 'series',
        ),
      ];

      final match = service.resolveFavoriteMatch(
        target: target,
        favorites: favorites,
      );

      expect(match, isNotNull);
      expect(match!.result.id, '1');
      expect(match.folderName, '三体');
    });

    test('prefers an external-id match over title-only matches', () {
      const service = DetailOnlineResourceUpdateService();
      const target = MediaDetailTarget(
        title: '9号秘事',
        posterUrl: '',
        overview: '',
        itemType: 'series',
        searchQuery: '9号秘事',
        tmdbId: '65707',
        imdbId: 'tt2674806',
      );
      const favorites = [
        SearchResult(
          id: 'title-only',
          title: '9号秘事 全集',
          posterUrl: '',
          providerId: 'quark-a',
          providerName: 'Quark',
          quality: '',
          sizeLabel: '',
          seeders: 0,
          summary: '',
          resourceUrl: 'https://pan.quark.cn/s/title-only',
          favoriteFolderName: '9号秘事',
          tmdbId: '99999',
          metadataMediaType: 'series',
        ),
        SearchResult(
          id: 'external-id',
          title: 'Inside No. 9 第1季',
          posterUrl: '',
          providerId: 'quark-b',
          providerName: 'Quark',
          quality: '',
          sizeLabel: '',
          seeders: 0,
          summary: '',
          resourceUrl: 'https://pan.quark.cn/s/external-id',
          favoriteFolderName: 'Inside No. 9',
          imdbId: 'tt2674806',
          tmdbId: '65707',
          metadataMediaType: 'series',
        ),
      ];

      final match = service.resolveFavoriteMatch(
        target: target,
        favorites: favorites,
      );

      expect(match, isNotNull);
      expect(match!.result.id, 'external-id');
      expect(match.folderName, 'Inside No. 9');
    });

    test('supports movie targets with tmdb id matches', () {
      const service = DetailOnlineResourceUpdateService();
      const target = MediaDetailTarget(
        title: '乘风破浪',
        posterUrl: '',
        overview: '',
        itemType: 'movie',
        searchQuery: '乘风破浪',
        tmdbId: '381902',
      );
      const favorites = [
        SearchResult(
          id: 'movie-favorite',
          title: 'Duckweed 2017',
          posterUrl: '',
          providerId: 'quark-movie',
          providerName: 'Quark',
          quality: '',
          sizeLabel: '',
          seeders: 0,
          summary: '',
          resourceUrl: 'https://pan.quark.cn/s/movie-favorite',
          favoriteFolderName: '乘风破浪',
          tmdbId: '381902',
          metadataMediaType: 'movie',
        ),
      ];

      final match = service.resolveFavoriteMatch(
        target: target,
        favorites: favorites,
      );

      expect(match, isNotNull);
      expect(match!.result.id, 'movie-favorite');
      expect(match.folderName, '乘风破浪');
    });

    test('returns only episodes that are missing from the quark folder',
        () async {
      final client = QuarkSaveClient(
        MockClient((request) async {
          if (request.url.path == '/1/clouddrive/share/sharepage/token') {
            return _jsonResponse({
              'code': 0,
              'data': {'stoken': 'st-1'},
            });
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/detail') {
            final pdirFid = request.url.queryParameters['pdir_fid'] ?? '';
            if (pdirFid == '0') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'share-root',
                      'file_name': '分享目录',
                      'share_fid_token': 'token-root',
                      'dir': true,
                    },
                  ],
                },
                'metadata': {'_total': 1},
              });
            }
            if (pdirFid == 'share-root') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'share-ep1',
                      'file_name': '三体.S01E01.mkv',
                      'share_fid_token': 'token-ep1',
                    },
                    {
                      'fid': 'share-ep2',
                      'file_name': '三体.S01E02.mkv',
                      'share_fid_token': 'token-ep2',
                    },
                  ],
                },
                'metadata': {'_total': 2},
              });
            }
          }
          if (request.url.path == '/1/clouddrive/file/sort') {
            final parentFid = request.url.queryParameters['pdir_fid'] ?? '';
            if (parentFid == '0') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'dir-series-root',
                      'dir': true,
                      'file_name': '剧集',
                      'file_path': '/剧集',
                    },
                  ],
                },
              });
            }
            if (parentFid == 'dir-series-root') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'dir-santi',
                      'dir': true,
                      'file_name': '三体',
                      'file_path': '/剧集/三体',
                    },
                  ],
                },
              });
            }
            if (parentFid == 'dir-santi') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'local-ep1',
                      'dir': false,
                      'file_name': '三体.S01E01.mkv',
                      'file_path': '/剧集/三体/三体.S01E01.mkv',
                    },
                  ],
                },
              });
            }
          }
          return http.Response('Not found', 404);
        }),
      );

      const service = DetailOnlineResourceUpdateService();
      const target = MediaDetailTarget(
        title: '三体',
        posterUrl: '',
        overview: '',
        itemType: 'series',
        searchQuery: '三体',
      );
      const favorites = [
        SearchResult(
          id: 'favorite-1',
          title: '三体全集',
          posterUrl: '',
          providerId: 'quark-1',
          providerName: 'Quark',
          quality: '',
          sizeLabel: '',
          seeders: 0,
          summary: '',
          resourceUrl: 'https://pan.quark.cn/s/abc123',
          favoriteFolderName: '三体',
          metadataMediaType: 'series',
        ),
      ];
      final favoriteMatch = service.resolveFavoriteMatch(
        target: target,
        favorites: favorites,
      );

      final result = await service.checkForUpdates(
        target: target,
        favoriteMatch: favoriteMatch!,
        networkStorage: const NetworkStorageConfig(
          quarkCookie: 'kps=test; sign=test; vcode=test;',
          quarkSaveFolderId: 'dir-series-root',
          quarkSaveFolderPath: '/剧集',
        ),
        quarkSaveClient: client,
      );

      expect(result.targetFolderPath, '/剧集/三体');
      expect(result.localFolderExists, isTrue);
      expect(result.onlineVideoCount, 2);
      expect(result.localVideoCount, 1);
      expect(result.updatedEpisodeLabels, ['三体.S01E02.mkv']);
    });
  });
}
