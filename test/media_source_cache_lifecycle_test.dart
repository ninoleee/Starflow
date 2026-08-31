import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/features/library/data/nas_media_index_models.dart';
import 'package:starflow/features/library/data/nas_media_index_store.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_source_identity.dart';
import 'package:starflow/features/settings/application/media_source_cache_lifecycle.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('clears an index whose source root changed under the same id', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'media-source-cache-lifecycle-root-change.db',
    );
    addTearDown(database.close);
    final store = SembastNasMediaIndexStore(
      databaseOpener: () async => database,
    );
    const previous = MediaSourceConfig(
      id: 'nas-main',
      name: 'NAS',
      kind: MediaSourceKind.nas,
      endpoint: 'https://old.example.com/movies/',
      enabled: true,
    );
    const current = MediaSourceConfig(
      id: 'nas-main',
      name: 'NAS',
      kind: MediaSourceKind.nas,
      endpoint: 'https://new.example.com/dav/strm/',
      enabled: true,
    );
    await store.replaceSourceRecords(
      sourceId: previous.id,
      records: const [],
      state: NasMediaIndexSourceState(
        sourceId: previous.id,
        lastIndexedAt: DateTime.utc(2026, 8, 31),
        recordCount: 0,
        scopeKey: 'root|https://old.example.com/movies/|structure:true',
        sourceIdentity: mediaSourceResourceIdentity(previous),
      ),
    );
    final invalidated = <String>[];
    final lifecycle = DefaultMediaSourceCacheLifecycle(
      indexStore: store,
      webDavNasClient: WebDavNasClient(
        MockClient((request) async => http.Response('', 200)),
      ),
      localStorageCacheRepository: LocalStorageCacheRepository(
        sharedPreferences: await SharedPreferences.getInstance(),
      ),
      invalidateSource: invalidated.add,
      invalidateAll: () {},
      notifyIndexChanged: () {},
    );

    await lifecycle.reconcileSources(const [current]);

    expect(await store.loadSourceState(current.id), isNull);
    expect(invalidated, ['nas-main']);
  });

  test('keeps an index when the persisted source identity still matches',
      () async {
    final database = await databaseFactoryMemory.openDatabase(
      'media-source-cache-lifecycle-match.db',
    );
    addTearDown(database.close);
    final store = SembastNasMediaIndexStore(
      databaseOpener: () async => database,
    );
    const source = MediaSourceConfig(
      id: 'nas-main',
      name: 'NAS',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/',
      enabled: true,
    );
    await store.replaceSourceRecords(
      sourceId: source.id,
      records: const [],
      state: NasMediaIndexSourceState(
        sourceId: source.id,
        lastIndexedAt: DateTime.utc(2026, 8, 31),
        recordCount: 0,
        scopeKey: 'root|https://nas.example.com/dav/|structure:true',
        sourceIdentity: mediaSourceResourceIdentity(source),
      ),
    );
    final invalidated = <String>[];
    final lifecycle = DefaultMediaSourceCacheLifecycle(
      indexStore: store,
      webDavNasClient: WebDavNasClient(
        MockClient((request) async => http.Response('', 200)),
      ),
      localStorageCacheRepository: LocalStorageCacheRepository(
        sharedPreferences: await SharedPreferences.getInstance(),
      ),
      invalidateSource: invalidated.add,
      invalidateAll: () {},
      notifyIndexChanged: () {},
    );

    await lifecycle.reconcileSources(const [source]);

    expect(await store.loadSourceState(source.id), isNotNull);
    expect(invalidated, isEmpty);
  });
}
