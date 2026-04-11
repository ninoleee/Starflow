import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/library/application/media_refresh_coordinator.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/nas_media_index_store.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/presentation/library_page.dart';
import 'package:starflow/features/metadata/data/imdb_rating_client.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MediaRefreshCoordinator', () {
    test(
        'rebuilding a Quark source refreshes cached library providers with latest items',
        () async {
      SharedPreferences.setMockInitialValues(const {});
      final sharedPreferences = await SharedPreferences.getInstance();
      const source = MediaSourceConfig(
        id: 'quark-main',
        name: 'Quark Drive',
        kind: MediaSourceKind.quark,
        endpoint: 'root-folder',
        libraryPath: '/影视',
        enabled: true,
      );
      final quarkClient = _MutableQuarkSaveClient(
        entriesByParentFid: {
          'root-folder': [
            QuarkFileEntry(
              fid: 'old-file',
              name: 'Old.Movie.2024.mkv',
              path: '/影视/Old.Movie.2024.mkv',
              isDirectory: false,
              updatedAt: DateTime(2026, 4, 10, 20),
              category: 'video',
              extension: 'mkv',
            ),
          ],
        },
      );
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            SeedData.defaultSettings.copyWith(
              mediaSources: const [source],
              searchProviders: const [],
              homeModules: const [],
              networkStorage: const NetworkStorageConfig(
                quarkCookie: 'kps=test; sign=test;',
              ),
            ),
          ),
          embyApiClientProvider.overrideWithValue(
            EmbyApiClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          webDavNasClientProvider.overrideWithValue(
            WebDavNasClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          nasMediaIndexStoreProvider.overrideWithValue(
            SembastNasMediaIndexStore(
              databaseOpener: () => databaseFactoryMemory.openDatabase(
                'media-refresh-coordinator-test',
              ),
            ),
          ),
          wmdbMetadataClientProvider.overrideWithValue(
            WmdbMetadataClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          tmdbMetadataClientProvider.overrideWithValue(
            TmdbMetadataClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          imdbRatingClientProvider.overrideWithValue(
            ImdbRatingClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          quarkSaveClientProvider.overrideWithValue(quarkClient),
          localStorageCacheRepositoryProvider.overrideWithValue(
            LocalStorageCacheRepository(
              sharedPreferences: sharedPreferences,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final initialItems = await _waitForLibraryItems(
        container,
        (items) => items.any((item) => item.playbackItemId == 'old-file'),
      );
      expect(initialItems, hasLength(1));
      expect(initialItems.single.playbackItemId, 'old-file');

      quarkClient.entriesByParentFid['root-folder'] = [
        QuarkFileEntry(
          fid: 'new-file',
          name: 'New.Movie.2025.mkv',
          path: '/影视/New.Movie.2025.mkv',
          isDirectory: false,
          updatedAt: DateTime(2026, 4, 10, 21),
          category: 'video',
          extension: 'mkv',
        ),
      ];

      await container
          .read(mediaRefreshCoordinatorProvider)
          .rebuildSelectedSources(
        sourceIds: [source.id],
      );

      final updatedItems = await _waitForLibraryItems(
        container,
        (items) => items.any((item) => item.playbackItemId == 'new-file'),
      );
      expect(updatedItems, hasLength(1));
      expect(updatedItems.single.playbackItemId, 'new-file');
    });
  });
}

Future<List<MediaItem>> _waitForLibraryItems(
  ProviderContainer container,
  bool Function(List<MediaItem> items) predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final completer = Completer<List<MediaItem>>();
  late final ProviderSubscription<AsyncValue<List<MediaItem>>> subscription;
  subscription = container.listen<AsyncValue<List<MediaItem>>>(
    libraryItemsProvider(LibraryFilter.quark),
    (_, next) {
      next.when(
        data: (items) {
          if (!completer.isCompleted && predicate(items)) {
            completer.complete(items);
          }
        },
        loading: () {},
        error: (error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
      );
    },
    fireImmediately: true,
  );
  try {
    return await completer.future.timeout(timeout);
  } finally {
    subscription.close();
  }
}

class _MutableQuarkSaveClient extends QuarkSaveClient {
  _MutableQuarkSaveClient({
    required this.entriesByParentFid,
  }) : super(MockClient((request) async => http.Response('', 200)));

  final Map<String, List<QuarkFileEntry>> entriesByParentFid;

  @override
  Future<List<QuarkFileEntry>> listEntries({
    required String cookie,
    String parentFid = '0',
  }) async {
    return entriesByParentFid[parentFid] ?? const <QuarkFileEntry>[];
  }

  @override
  Future<List<QuarkDirectoryEntry>> listDirectories({
    required String cookie,
    String parentFid = '0',
  }) async {
    final entries = await listEntries(
      cookie: cookie,
      parentFid: parentFid,
    );
    return entries
        .where((item) => item.isDirectory)
        .map(QuarkDirectoryEntry.fromFileEntry)
        .whereType<QuarkDirectoryEntry>()
        .toList(growable: false);
  }
}
