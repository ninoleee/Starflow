import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/details/application/detail_online_resource_update_service.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
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
