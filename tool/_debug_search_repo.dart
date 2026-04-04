import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/data/cloud_saver_api_client.dart';
import 'package:starflow/features/search/data/mock_search_repository.dart';
import 'package:starflow/features/search/data/pansou_api_client.dart';
import 'package:starflow/features/search/data/search_link_validator.dart';
import 'package:starflow/features/search/domain/search_models.dart';

class _FakeMediaRepository implements MediaRepository {
  const _FakeMediaRepository();

  @override
  Future<List<MediaCollection>> fetchCollections({
    MediaSourceKind? kind,
    String? sourceId,
  }) async => const [];

  @override
  Future<List<MediaItem>> fetchLibrary({
    MediaSourceKind? kind,
    String? sourceId,
    String? sectionId,
    int limit = 200,
  }) async => const [];

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({
    MediaSourceKind? kind,
    int limit = 10,
  }) async => const [];

  @override
  Future<List<MediaItem>> fetchChildren({
    required String sourceId,
    required String parentId,
    String sectionId = '',
    String sectionName = '',
    int limit = 200,
  }) async => const [];

  @override
  Future<MediaItem?> findById(String id) async => null;

  @override
  Future<List<MediaSourceConfig>> fetchSources() async => const [];

  @override
  Future<MediaItem?> matchTitle(String title) async => null;
}

Future<void> main() async {
  final repository = AppSearchRepository(
    PanSouApiClient(
      MockClient((request) async {
        return http.Response(
          '{"code":0,"data":{"merged_by_type":{"quark":[{"url":"https://pan.quark.cn/s/valid","note":"有效资源","password":""},{"url":"https://pan.quark.cn/s/invalid","note":"失效资源","password":""}]}}}',
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    ),
    CloudSaverApiClient(
      MockClient((request) async => http.Response('{}', 200)),
    ),
    SearchLinkValidator(
      MockClient((request) async {
        print('validator request => ${request.url}');
        if (request.url.toString().endsWith('/invalid')) {
          return http.Response('分享已失效', 200);
        }
        return http.Response('<html>资源仍可访问</html>', 200);
      }),
    ),
    const _FakeMediaRepository(),
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

  print('raw=${results.rawCount}, filtered=${results.filteredCount}, visible=${results.items.length}');
  for (final item in results.items) {
    print('${item.title} | ${item.resourceUrl} | cloud=${item.cloudType}');
  }
}
