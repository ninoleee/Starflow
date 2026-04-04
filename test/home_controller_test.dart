import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/discovery/data/mock_discovery_repository.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  group('homeSectionsProvider Douban poster fallback', () {
    test('uses matched library poster without pre-binding the resource',
        () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings(
              mediaSources: const [],
              searchProviders: const [],
              doubanAccount: const DoubanAccountConfig(
                enabled: true,
                userId: 'demo-user',
                sessionCookie: '',
              ),
              homeModules: [
                HomeModuleConfig.doubanInterest(DoubanInterestStatus.mark),
              ],
            ),
          ),
          mediaRepositoryProvider.overrideWithValue(
            _FakeMediaRepository(
              library: [
                MediaItem(
                  id: 'emby-1',
                  title: '美丽人生',
                  overview: '来自 Emby 的条目',
                  posterUrl: 'https://emby.example.com/poster.jpg',
                  year: 1997,
                  durationLabel: '116分钟',
                  genres: ['剧情'],
                  sourceId: 'emby-main',
                  sourceName: 'Home Emby',
                  sourceKind: MediaSourceKind.emby,
                  streamUrl: '',
                  addedAt: DateTime(2026, 4, 4),
                ),
              ],
            ),
          ),
          discoveryRepositoryProvider.overrideWithValue(
            _FakeDiscoveryRepository(
              entries: const [
                DoubanEntry(
                  id: '1292063',
                  title: '美丽人生',
                  year: 1997,
                  posterUrl: '',
                  note: '圭多用幽默守护家人。',
                  ratingLabel: '豆瓣 9.6',
                ),
              ],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final sections = await container.read(homeSectionsProvider.future);
      expect(sections, hasLength(1));
      expect(
        sections.first.items.first.posterUrl,
        'https://emby.example.com/poster.jpg',
      );
      expect(sections.first.items.first.detailTarget.sourceId, isEmpty);
      expect(sections.first.items.first.detailTarget.itemId, isEmpty);
      expect(
        sections.first.items.first.detailTarget.posterUrl,
        'https://emby.example.com/poster.jpg',
      );
      expect(
        sections.first.items.first.detailTarget.ratingLabels,
        ['豆瓣 9.6'],
      );
    });

    test('uses TMDB poster fallback when enabled and no match exists',
        () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings(
              mediaSources: const [],
              searchProviders: const [],
              doubanAccount: const DoubanAccountConfig(
                enabled: true,
                userId: 'demo-user',
                sessionCookie: '',
              ),
              homeModules: [
                HomeModuleConfig.doubanInterest(DoubanInterestStatus.mark),
              ],
              tmdbMetadataMatchEnabled: true,
              tmdbReadAccessToken: 'tmdb-token',
            ),
          ),
          mediaRepositoryProvider.overrideWithValue(
            _FakeMediaRepository(library: const []),
          ),
          discoveryRepositoryProvider.overrideWithValue(
            _FakeDiscoveryRepository(
              entries: const [
                DoubanEntry(
                  id: '1295644',
                  title: '这个杀手不太冷',
                  year: 1994,
                  posterUrl: '',
                  note: '孤独杀手与少女之间的故事。',
                ),
              ],
            ),
          ),
          tmdbMetadataClientProvider.overrideWithValue(
            TmdbMetadataClient(
              MockClient((request) async {
                if (request.url.path == '/3/search/multi') {
                  return http.Response(
                    jsonEncode({
                      'results': [
                        {
                          'id': 101,
                          'media_type': 'movie',
                          'title': 'Léon: The Professional',
                          'original_title': 'Léon',
                          'release_date': '1994-09-14',
                          'poster_path': '/search.jpg',
                          'popularity': 99.0,
                        },
                      ],
                    }),
                    200,
                  );
                }

                if (request.url.path == '/3/movie/101') {
                  return http.Response.bytes(
                    utf8.encode(
                      jsonEncode({
                        'title': '这个杀手不太冷',
                        'overview': '孤独杀手与少女之间的故事。',
                        'release_date': '1994-09-14',
                        'poster_path': '/leon.jpg',
                        'runtime': 110,
                        'genres': const [],
                        'credits': {
                          'cast': const [],
                          'crew': const [],
                        },
                        'external_ids': {'imdb_id': 'tt0110413'},
                      }),
                    ),
                    200,
                    headers: const {
                      'content-type': 'application/json; charset=utf-8',
                    },
                  );
                }

                throw UnsupportedError('Unexpected request: ${request.url}');
              }),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final sections = await container.read(homeSectionsProvider.future);
      expect(sections, hasLength(1));
      expect(
        sections.first.items.first.posterUrl,
        'https://image.tmdb.org/t/p/w500/leon.jpg',
      );
      expect(
        sections.first.items.first.detailTarget.posterUrl,
        'https://image.tmdb.org/t/p/w500/leon.jpg',
      );
    });
  });
}

class _FakeMediaRepository implements MediaRepository {
  const _FakeMediaRepository({required this.library});

  final List<MediaItem> library;

  @override
  Future<List<MediaCollection>> fetchCollections({
    MediaSourceKind? kind,
    String? sourceId,
  }) async {
    return const [];
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
  Future<List<MediaItem>> fetchLibrary({
    MediaSourceKind? kind,
    String? sourceId,
    String? sectionId,
    int limit = 200,
  }) async {
    return library;
  }

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({
    MediaSourceKind? kind,
    int limit = 10,
  }) async {
    return const [];
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

class _FakeDiscoveryRepository implements DiscoveryRepository {
  const _FakeDiscoveryRepository({required this.entries});

  final List<DoubanEntry> entries;

  @override
  Future<List<DoubanCarouselEntry>> fetchCarouselItems() async {
    return const [];
  }

  @override
  Future<List<DoubanEntry>> fetchEntries(HomeModuleConfig module) async {
    return entries;
  }
}
