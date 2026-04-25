import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/data/cloud_saver_api_client.dart';
import 'package:starflow/features/search/data/mock_search_repository.dart';
import 'package:starflow/features/search/data/pansou_api_client.dart';
import 'package:starflow/features/search/domain/search_models.dart';

void main() {
  group('AppSearchRepository', () {
    test('searchLocal filters by configured media source', () async {
      final repository = AppSearchRepository(
        PanSouApiClient(
          MockClient((request) async => http.Response('{}', 200)),
        ),
        CloudSaverApiClient(
          MockClient((request) async => http.Response('{}', 200)),
        ),
        _FakeMediaRepository(
          items: [
            MediaItem(
              id: 'emby-1',
              title: '黑客帝国',
              originalTitle: 'The Matrix',
              overview: 'Neo discovers the truth.',
              posterUrl: '',
              year: 1999,
              durationLabel: '136分钟',
              genres: const ['科幻'],
              sectionId: 'movies',
              sectionName: '电影',
              sourceId: 'emby-main',
              sourceName: '客厅 Emby',
              sourceKind: MediaSourceKind.emby,
              streamUrl: 'https://emby.example.com/stream/1',
              addedAt: DateTime.utc(2026, 4, 4),
            ),
            MediaItem(
              id: 'nas-1',
              title: '黑客军团',
              overview: 'Mr. Robot',
              posterUrl: '',
              year: 2015,
              durationLabel: '剧集',
              genres: const ['剧情'],
              sectionId: 'shows',
              sectionName: '剧集',
              sourceId: 'webdav-main',
              sourceName: '家庭 WebDAV',
              sourceKind: MediaSourceKind.nas,
              streamUrl: 'https://nas.example.com/stream/1',
              addedAt: DateTime.utc(2026, 4, 3),
            ),
          ],
        ),
      );

      final embyResults = await repository.searchLocal(
        '黑客',
        sourceId: 'emby-main',
      );
      final allResults = await repository.searchLocal('黑客');

      expect(embyResults.items, hasLength(1));
      expect(embyResults.items.first.title, '黑客帝国');
      expect(embyResults.items.first.detailTarget, isNotNull);
      expect(embyResults.filteredCount, 0);

      expect(
        allResults.items.map((item) => item.title),
        containsAll(['黑客帝国', '黑客军团']),
      );
    });

    test('searchOnline returns empty for unsupported providers', () async {
      final repository = AppSearchRepository(
        PanSouApiClient(
          MockClient((request) async => http.Response('{}', 200)),
        ),
        CloudSaverApiClient(
          MockClient((request) async => http.Response('{}', 200)),
        ),
        const _FakeMediaRepository(items: []),
      );

      final results = await repository.searchOnline(
        '英雄本色',
        provider: const SearchProviderConfig(
          id: 'custom-indexer',
          name: '自定义索引',
          kind: SearchProviderKind.panSou,
          endpoint: 'https://search.example.com',
          enabled: true,
        ),
      );

      expect(results.items, isEmpty);
      expect(results.filteredCount, 0);
    });

    test('searchOnline routes strictly by provider kind', () async {
      var panSouRequests = 0;
      var cloudSaverRequests = 0;
      final repository = AppSearchRepository(
        PanSouApiClient(
          MockClient((request) async {
            panSouRequests += 1;
            return http.Response(
              '''
              {
                "code": 0,
                "data": {
                  "merged_by_type": {
                    "quark": [
                      {"url":"https://pan.quark.cn/s/pansou-only","note":"PanSou 结果","password":""}
                    ]
                  }
                }
              }
              ''',
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        ),
        CloudSaverApiClient(
          MockClient((request) async {
            cloudSaverRequests += 1;
            return http.Response(
              '''
              {
                "success": true,
                "code": 0,
                "data": [
                  {
                    "id": "channel-1",
                    "list": [
                      {
                        "title": "CloudSaver 结果",
                        "content": "",
                        "cloudLinks": ["https://pan.quark.cn/s/cloud-only"],
                        "cloudType": "夸克网盘",
                        "channel": "资源频道"
                      }
                    ]
                  }
                ]
              }
              ''',
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        ),
        const _FakeMediaRepository(items: []),
      );

      final panSouResults = await repository.searchOnline(
        '黑客帝国',
        provider: const SearchProviderConfig(
          id: 'provider-pan',
          name: 'PanSou',
          kind: SearchProviderKind.panSou,
          endpoint: 'http://localhost:3000/api/search',
          parserHint: 'cloudsaver-api',
          enabled: true,
        ),
      );
      final cloudSaverResults = await repository.searchOnline(
        '黑客帝国',
        provider: const SearchProviderConfig(
          id: 'provider-cloud',
          name: 'CloudSaver',
          kind: SearchProviderKind.cloudSaver,
          endpoint: 'https://so.252035.xyz',
          parserHint: 'pansou-api',
          enabled: true,
        ),
      );

      expect(panSouResults.items.single.title, 'PanSou 结果');
      expect(cloudSaverResults.items.single.title, 'CloudSaver 结果');
      expect(panSouRequests, 1);
      expect(cloudSaverRequests, 1);
    });

    test('searchOnline keeps deduplicated results from provider output',
        () async {
      final repository = AppSearchRepository(
        PanSouApiClient(
          MockClient((request) async {
            return http.Response(
              '''
              {
                "code": 0,
                "data": {
                  "merged_by_type": {
                    "quark": [
                      {"url":"https://pan.quark.cn/s/valid","note":"有效资源","password":""},
                      {"url":"https://pan.quark.cn/s/valid?pwd=1234","note":"重复资源","password":"1234"}
                    ]
                  }
                }
              }
              ''',
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        ),
        CloudSaverApiClient(
          MockClient((request) async => http.Response('{}', 200)),
        ),
        const _FakeMediaRepository(items: []),
      );

      final results = await repository.searchOnline(
        '测试资源',
        provider: const SearchProviderConfig(
          id: 'pansou-api',
          name: 'PanSou',
          kind: SearchProviderKind.panSou,
          endpoint: 'https://so.252035.xyz',
          enabled: true,
        ),
      );

      expect(results.items, hasLength(1));
      expect(results.items.single.title, '有效资源');
      expect(results.filteredCount, 1);
      expect(results.rawCount, 2);
    });

    test('searchOnline filters by cloud type and blocked keywords', () async {
      final repository = AppSearchRepository(
        PanSouApiClient(
          MockClient((request) async {
            return http.Response(
              '''
              {
                "code": 0,
                "data": {
                  "merged_by_type": {
                    "quark": [
                      {"url":"https://pan.quark.cn/s/good","note":"正式版","password":""},
                      {"url":"https://pan.quark.cn/s/badword","note":"枪版资源","password":""}
                    ],
                    "baidu": [
                      {"url":"https://pan.baidu.com/s/other","note":"百度资源","password":""}
                    ]
                  }
                }
              }
              ''',
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        ),
        CloudSaverApiClient(
          MockClient((request) async => http.Response('{}', 200)),
        ),
        const _FakeMediaRepository(items: []),
      );

      final results = await repository.searchOnline(
        '测试资源',
        provider: const SearchProviderConfig(
          id: 'pansou-api',
          name: 'PanSou',
          kind: SearchProviderKind.panSou,
          endpoint: 'https://so.252035.xyz',
          enabled: true,
          allowedCloudTypes: ['quark'],
          blockedKeywords: ['枪版'],
        ),
      );

      expect(results.items, hasLength(1));
      expect(results.items.single.resourceUrl, 'https://pan.quark.cn/s/good');
      expect(results.filteredCount, 2);
      expect(results.rawCount, 3);
    });

    test('searchOnline filters cloud type by resource url', () async {
      final repository = AppSearchRepository(
        PanSouApiClient(
          MockClient((request) async {
            return http.Response(
              '''
              {
                "code": 0,
                "data": {
                  "merged_by_type": {
                    "quark": [
                      {"url":"https://pan.quark.cn/s/quark-item","note":"夸克资源","password":""}
                    ],
                    "baidu": [
                      {"url":"https://pan.baidu.com/s/baidu-item","note":"百度资源","password":""}
                    ]
                  }
                }
              }
              ''',
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        ),
        CloudSaverApiClient(
          MockClient((request) async => http.Response('{}', 200)),
        ),
        const _FakeMediaRepository(items: []),
      );

      final results = await repository.searchOnline(
        '测试资源',
        provider: const SearchProviderConfig(
          id: 'pansou-api',
          name: 'PanSou',
          kind: SearchProviderKind.panSou,
          endpoint: 'https://so.252035.xyz',
          enabled: true,
          allowedCloudTypes: ['baidu'],
        ),
      );

      expect(results.items, hasLength(1));
      expect(results.items.single.resourceUrl,
          'https://pan.baidu.com/s/baidu-item');
      expect(results.filteredCount, 1);
    });

    test('searchOnline keeps 115 results for schemeless 115 url', () async {
      final repository = AppSearchRepository(
        PanSouApiClient(
          MockClient((request) async {
            return http.Response(
              '''
              {
                "code": 0,
                "data": {
                  "merged_by_type": {
                    "115": [
                      {"url":"115.com/s/share115","note":"115资源","password":""}
                    ],
                    "baidu": [
                      {"url":"https://pan.baidu.com/s/baidu-item","note":"百度资源","password":""}
                    ]
                  }
                }
              }
              ''',
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        ),
        CloudSaverApiClient(
          MockClient((request) async => http.Response('{}', 200)),
        ),
        const _FakeMediaRepository(items: []),
      );

      final results = await repository.searchOnline(
        '测试资源',
        provider: const SearchProviderConfig(
          id: 'pansou-api',
          name: 'PanSou',
          kind: SearchProviderKind.panSou,
          endpoint: 'https://so.252035.xyz',
          enabled: true,
          allowedCloudTypes: ['115'],
        ),
      );

      expect(results.items, hasLength(1));
      expect(results.items.single.resourceUrl, '115.com/s/share115');
      expect(results.filteredCount, 1);
    });

    test('searchOnline keeps 115 results for anxia url', () async {
      final repository = AppSearchRepository(
        PanSouApiClient(
          MockClient((request) async {
            return http.Response(
              '''
              {
                "code": 0,
                "data": {
                  "merged_by_type": {
                    "115": [
                      {"url":"https://anxia.com/s/share115","note":"115资源","password":""}
                    ],
                    "quark": [
                      {"url":"https://pan.quark.cn/s/quark-item","note":"夸克资源","password":""}
                    ]
                  }
                }
              }
              ''',
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        ),
        CloudSaverApiClient(
          MockClient((request) async => http.Response('{}', 200)),
        ),
        const _FakeMediaRepository(items: []),
      );

      final results = await repository.searchOnline(
        '测试资源',
        provider: const SearchProviderConfig(
          id: 'pansou-api',
          name: 'PanSou',
          kind: SearchProviderKind.panSou,
          endpoint: 'https://so.252035.xyz',
          enabled: true,
          allowedCloudTypes: ['115'],
        ),
      );

      expect(results.items, hasLength(1));
      expect(results.items.single.resourceUrl, 'https://anxia.com/s/share115');
      expect(results.filteredCount, 1);
    });

    test('searchOnline strong match keeps titles containing query characters',
        () async {
      final repository = AppSearchRepository(
        PanSouApiClient(
          MockClient((request) async {
            return http.Response(
              '''
              {
                "code": 0,
                "data": {
                  "merged_by_type": {
                    "quark": [
                      {"url":"https://pan.quark.cn/s/full-match","note":"英雄本色 4K修复版","password":""},
                      {"url":"https://pan.quark.cn/s/partial-match","note":"英雄 4K 本色","password":""},
                      {"url":"https://pan.quark.cn/s/reverse-match","note":"本色英雄","password":""}
                    ]
                  }
                }
              }
              ''',
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        ),
        CloudSaverApiClient(
          MockClient((request) async => http.Response('{}', 200)),
        ),
        const _FakeMediaRepository(items: []),
      );

      final results = await repository.searchOnline(
        '英雄本色',
        provider: const SearchProviderConfig(
          id: 'pansou-api',
          name: 'PanSou',
          kind: SearchProviderKind.panSou,
          endpoint: 'https://so.252035.xyz',
          enabled: true,
          strongMatchEnabled: true,
        ),
      );

      expect(results.items, hasLength(3));
      expect(
        results.items.map((item) => item.title),
        containsAll(['英雄本色 4K修复版', '英雄 4K 本色', '本色英雄']),
      );
      expect(results.filteredCount, 0);
      expect(results.rawCount, 3);
    });

    test('searchOnline filters titles longer than configured max length',
        () async {
      final repository = AppSearchRepository(
        PanSouApiClient(
          MockClient((request) async {
            return http.Response(
              '''
              {
                "code": 0,
                "data": {
                  "merged_by_type": {
                    "quark": [
                      {"url":"https://pan.quark.cn/s/short-title","note":"英雄本色","password":""},
                      {"url":"https://pan.quark.cn/s/long-title","note":"英雄本色导演剪辑版超清收藏全集国语粤语双音轨杜比视界蓝光原盘高码率版本","password":""}
                    ]
                  }
                }
              }
              ''',
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        ),
        CloudSaverApiClient(
          MockClient((request) async => http.Response('{}', 200)),
        ),
        const _FakeMediaRepository(items: []),
      );

      final results = await repository.searchOnline(
        '英雄本色',
        provider: const SearchProviderConfig(
          id: 'pansou-api',
          name: 'PanSou',
          kind: SearchProviderKind.panSou,
          endpoint: 'https://so.252035.xyz',
          enabled: true,
          maxTitleLength: 10,
        ),
      );

      expect(results.items, hasLength(1));
      expect(results.items.single.title, '英雄本色');
      expect(results.filteredCount, 1);
      expect(results.rawCount, 2);
    });

    test(
        'searchOnline filters CloudSaver result when url does not expose cloud type',
        () async {
      final repository = AppSearchRepository(
        PanSouApiClient(
          MockClient((request) async => http.Response('{}', 200)),
        ),
        CloudSaverApiClient(
          MockClient((request) async {
            return http.Response(
              '''
              {
                "success": true,
                "code": 0,
                "data": [
                  {
                    "id": "channel-1",
                    "list": [
                      {
                        "title": "测试资源",
                        "content": "提取码: 1234",
                        "cloudLinks": ["【https://redirect.example.com/quark-share】"],
                        "cloudType": "夸克网盘",
                        "channel": "资源频道"
                      }
                    ]
                  }
                ]
              }
              ''',
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        ),
        const _FakeMediaRepository(items: []),
      );

      final results = await repository.searchOnline(
        '测试资源',
        provider: const SearchProviderConfig(
          id: 'cloudsaver-main',
          name: 'CloudSaver',
          kind: SearchProviderKind.cloudSaver,
          endpoint: 'http://localhost:3000',
          enabled: true,
          allowedCloudTypes: ['quark'],
        ),
      );

      expect(results.items, isEmpty);
      expect(results.filteredCount, 1);
    });
  });
}

class _FakeMediaRepository implements MediaRepository {
  const _FakeMediaRepository({required this.items});

  final List<MediaItem> items;

  @override
  Future<List<MediaItem>> loadLibraryMatchItems({
    required MediaSourceConfig source,
    String doubanId = '',
    String imdbId = '',
    String tmdbId = '',
    String tvdbId = '',
    String wikidataId = '',
    Iterable<String> titles = const <String>[],
    int year = 0,
    int limit = 2000,
  }) async {
    return items
        .where((item) => item.sourceKind == source.kind)
        .where((item) => item.sourceId == source.id)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<List<MediaCollection>> fetchCollections({
    MediaSourceKind? kind,
    String? sourceId,
  }) async {
    return const [];
  }

  @override
  Future<List<MediaItem>> fetchLibrary({
    MediaSourceKind? kind,
    String? sourceId,
    String? sectionId,
    int limit = 200,
  }) async {
    return items
        .where((item) => kind == null || item.sourceKind == kind)
        .where((item) => sourceId == null || item.sourceId == sourceId)
        .where((item) =>
            sectionId == null ||
            sectionId.isEmpty ||
            item.sectionId == sectionId)
        .take(limit)
        .toList();
  }

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({
    MediaSourceKind? kind,
    int limit = 10,
  }) async {
    return fetchLibrary(kind: kind, limit: limit);
  }

  @override
  Future<void> cancelActiveWebDavRefreshes({
    bool includeForceFull = false,
  }) async {}

  @override
  Future<void> refreshSource({
    required String sourceId,
    bool forceFullRescan = false,
  }) async {}

  @override
  Future<List<MediaItem>> fetchChildren({
    required String sourceId,
    required String parentId,
    String sectionId = '',
    String sectionName = '',
    int limit = 200,
  }) async {
    return const [];
  }

  @override
  Future<MediaItem?> findById(String id) async {
    return null;
  }

  @override
  Future<void> deleteResource({
    required String sourceId,
    required String resourcePath,
    String sectionId = '',
  }) async {}

  @override
  Future<List<MediaSourceConfig>> fetchSources() async {
    return const [];
  }

  @override
  Future<MediaItem?> matchTitle(String title) async {
    return null;
  }
}
