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

      expect(embyResults, hasLength(1));
      expect(embyResults.first.title, '黑客帝国');
      expect(embyResults.first.detailTarget, isNotNull);

      expect(
          allResults.map((item) => item.title), containsAll(['黑客帝国', '黑客军团']));
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

      expect(results, isEmpty);
    });
  });
}

class _FakeMediaRepository implements MediaRepository {
  const _FakeMediaRepository({required this.items});

  final List<MediaItem> items;

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
  Future<List<MediaSourceConfig>> fetchSources() async {
    return const [];
  }

  @override
  Future<MediaItem?> matchTitle(String title) async {
    return null;
  }
}
