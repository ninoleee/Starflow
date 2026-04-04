import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/media_detail_page.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  group('enrichedDetailTargetProvider', () {
    test('matches Emby resource after opening detail page', () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
            }),
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
                  genres: const ['剧情'],
                  sourceId: 'emby-main',
                  sourceName: 'Home Emby',
                  sourceKind: MediaSourceKind.emby,
                  streamUrl: '',
                  playbackItemId: 'emby-1',
                  addedAt: DateTime(2026, 4, 4),
                ),
              ],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      const target = MediaDetailTarget(
        title: '美丽人生',
        posterUrl: '',
        overview: '',
        year: 1997,
        ratingLabels: ['豆瓣 9.6'],
        availabilityLabel: '无',
        searchQuery: '美丽人生',
        sourceName: '豆瓣',
      );

      final resolved = await container.read(
        enrichedDetailTargetProvider(target).future,
      );

      expect(resolved.sourceId, 'emby-main');
      expect(resolved.itemId, 'emby-1');
      expect(resolved.playbackTarget, isNotNull);
      expect(resolved.availabilityLabel, contains('Home Emby'));
      expect(resolved.ratingLabels, contains('豆瓣 9.6'));
    });

    test('stops at preferred WMDB metadata match', () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'wmdbMetadataMatchEnabled': true,
              'tmdbMetadataMatchEnabled': true,
              'tmdbReadAccessToken': 'tmdb-token',
              'metadataMatchPriority': 'wmdb',
            }),
          ),
          mediaRepositoryProvider.overrideWithValue(
            const _FakeMediaRepository(library: []),
          ),
          wmdbMetadataClientProvider.overrideWithValue(
            WmdbMetadataClient(
              MockClient((request) async {
                expect(request.url.path, '/movie/api');
                return http.Response(
                  jsonEncode({
                    'data': [
                      {
                        'poster': 'https://img.wmdb.tv/movie/poster/sample.jpg',
                        'name': '美丽人生',
                        'genre': '剧情',
                        'description': '圭多用幽默守护家人。',
                        'lang': 'Cn',
                      },
                    ],
                    'actor': [
                      {
                        'data': [
                          {'name': '罗伯托·贝尼尼', 'lang': 'Cn'},
                        ],
                      },
                    ],
                    'director': [
                      {
                        'data': [
                          {'name': '罗伯托·贝尼尼', 'lang': 'Cn'},
                        ],
                      },
                    ],
                    'originalName': '美丽人生',
                    'imdbId': 'tt0118799',
                    'year': '1997',
                    'duration': 6960,
                    'doubanId': '1292063',
                    'doubanRating': '9.6',
                  }),
                  200,
                );
              }),
            ),
          ),
          tmdbMetadataClientProvider.overrideWithValue(
            TmdbMetadataClient(
              MockClient((request) async {
                throw TestFailure('WMDB 命中后不应该继续请求 TMDB：${request.url}');
              }),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      const target = MediaDetailTarget(
        title: '美丽人生',
        posterUrl: '',
        overview: '',
        year: 1997,
        availabilityLabel: '无',
        searchQuery: '美丽人生',
        sourceName: '豆瓣',
        doubanId: '1292063',
      );

      final resolved = await container.read(
        enrichedDetailTargetProvider(target).future,
      );

      expect(
        resolved.posterUrl,
        'https://img.wmdb.tv/movie/poster/sample.jpg',
      );
      expect(resolved.directors, ['罗伯托·贝尼尼']);
      expect(resolved.actors, ['罗伯托·贝尼尼']);
      expect(resolved.ratingLabels, ['豆瓣 9.6']);
      expect(resolved.imdbId, 'tt0118799');
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
    return library.take(limit).toList();
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
