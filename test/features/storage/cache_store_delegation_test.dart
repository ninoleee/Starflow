import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/storage/application/local_storage_cache_revision.dart';
import 'package:starflow/features/storage/data/detail_cache_store.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';
import 'package:starflow/features/storage/data/media_server_cache_store.dart';

const _detailKey = 'starflow.local_storage.detail_cache.v1';
const _manifestKey = 'starflow.local_storage.emby_library_cache.manifest.v2';
const _target = MediaDetailTarget(
  title: 'Cached movie',
  posterUrl: '',
  overview: 'Cached overview',
  sourceId: 'detail-source',
  itemId: 'movie',
  sourceKind: MediaSourceKind.emby,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('independent stores round trip through the compatibility facade',
      () async {
    final preferences = _Preferences();
    final details = DetailCacheStore(preferences: preferences);
    final servers = MediaServerCacheStore(preferences: preferences);
    addTearDown(details.dispose);
    addTearDown(servers.dispose);
    await details.saveDetailTarget(
        seedTarget: _target, resolvedTarget: _target);
    await servers.saveEmbyLibrarySnapshot(
      sourceId: 'server-source',
      refreshedAt: DateTime.utc(2026, 9, 20),
    );

    final repository = LocalStorageCacheRepository(preferences: preferences);
    addTearDown(repository.dispose);
    expect(await repository.loadCachedMediaSourceIds(),
        {'server-source', 'detail-source'});
    expect((await repository.loadDetailTarget(_target))?.overview,
        _target.overview);
    expect(
        (await repository.loadEmbyLibrarySnapshot('server-source')).refreshedAt,
        DateTime.utc(2026, 9, 20));
    expect(preferences.values.keys, containsAll([_detailKey, _manifestKey]));

    await repository.clearCache(LocalStorageCacheType.embyLibraryCache);
    expect(await repository.loadCachedMediaSourceIds(), {'detail-source'});
    expect(await repository.loadDetailTarget(_target), isNotNull);
    await repository.clearCache(LocalStorageCacheType.detailData);
    expect(await repository.loadCachedMediaSourceIds(), isEmpty);
  });

  test('detail and media-server mutation queues progress independently',
      () async {
    final preferences = _Preferences()..blockedWriteKey = _detailKey;
    final repository = LocalStorageCacheRepository(preferences: preferences);
    addTearDown(repository.dispose);
    final detailSave = repository.saveDetailTarget(
      seedTarget: _target,
      resolvedTarget: _target,
    );
    await preferences.writeStarted.future;
    try {
      await repository
          .saveEmbyLibrarySnapshot(
            sourceId: 'server-source',
            refreshedAt: DateTime.utc(2026, 9, 20),
          )
          .timeout(const Duration(seconds: 2));
      expect(preferences.values, contains(_manifestKey));
      expect(preferences.values, isNot(contains(_detailKey)));
    } finally {
      preferences.writeRelease.complete();
      await detailSave;
    }
  });

  test('facade preserves overridden state reads and clear dispatch', () async {
    final repository = _OverriddenRepository();
    addTearDown(repository.dispose);
    expect(repository.peekDetailTarget(_target), same(_target));
    expect(await repository.loadDetailTarget(_target), same(_target));
    expect(await repository.loadDetailMetadataRefreshStatus(_target),
        DetailMetadataRefreshStatus.succeeded);
    await repository.clearCache(LocalStorageCacheType.detailData);
    await repository.clearCache(LocalStorageCacheType.embyLibraryCache);
    expect(repository.cleared, ['details', 'servers']);
  });

  test('facade forwards lookup scope and coalesces detail reads', () async {
    final preferences = _Preferences();
    final repository = LocalStorageCacheRepository(preferences: preferences);
    addTearDown(repository.dispose);
    await Future.wait([
      repository.primeDetailPayload(),
      repository.loadDetailState(_target),
      repository.loadDetailTargetsBatch([_target]),
    ]);
    expect(preferences.readCounts[_detailKey], 1);
    expect(LocalStorageCacheRepository.buildLookupKeys(_target),
        DetailCacheStore.buildLookupKeys(_target));
    final scope = LocalStorageCacheRepository.buildScopeForTargets([_target]);
    expect(scope.sourceIds, {'detail-source'});
    expect(scope.lookupKeys, DetailCacheStore.buildLookupKeys(_target).toSet());
  });

  for (final delay in [Duration.zero, const Duration(milliseconds: 20)]) {
    test('dispose flushes accepted saves without late notifications: $delay',
        () async {
      final preferences = _Preferences();
      final events = <LocalStorageDetailCacheChangeEvent>[];
      final repository = LocalStorageCacheRepository(
        preferences: preferences,
        notifyDetailCacheChanged: events.add,
        detailCacheChangeNotificationDelay: delay,
      );
      final save = repository.saveDetailTarget(
        seedTarget: _target,
        resolvedTarget: _target,
      );
      repository.dispose();
      repository.dispose();
      await save;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(events, isEmpty);
      expect(repository.peekDetailTarget(_target), isNull);
      final reloaded = LocalStorageCacheRepository(preferences: preferences);
      addTearDown(reloaded.dispose);
      expect(await reloaded.loadDetailTarget(_target), isNotNull);
    });
  }

  test('dispose cancels a pending notification timer', () async {
    final events = <LocalStorageDetailCacheChangeEvent>[];
    final repository = LocalStorageCacheRepository(
      preferences: _Preferences(),
      notifyDetailCacheChanged: events.add,
      detailCacheChangeNotificationDelay: const Duration(milliseconds: 20),
    );
    await repository.saveDetailTarget(
        seedTarget: _target, resolvedTarget: _target);
    repository.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(events, isEmpty);
  });

  test('late detail load cannot repopulate a disposed store', () async {
    final preferences = _Preferences();
    final initial = DetailCacheStore(preferences: preferences);
    await initial.saveDetailTarget(
        seedTarget: _target, resolvedTarget: _target);
    initial.dispose();
    preferences.blockedReadKey = _detailKey;
    final details = DetailCacheStore(preferences: preferences);
    final load = details.loadDetailTarget(_target);
    await preferences.readStarted.future;
    details.dispose();
    preferences.readRelease.complete();
    expect(await load, isNotNull);
    expect(details.peekDetailTarget(_target), isNull);
  });

  test('late manifest load cannot repopulate a disposed media-server store',
      () async {
    final preferences = _Preferences();
    final initial = MediaServerCacheStore(preferences: preferences);
    await initial.saveEmbyLibrarySnapshot(
      sourceId: 'server-source',
      refreshedAt: DateTime.utc(2026, 9, 20),
    );
    initial.dispose();
    preferences.blockedReadKey = _manifestKey;
    final servers = MediaServerCacheStore(preferences: preferences);
    final load = servers.loadCachedMediaSourceIds();
    await preferences.readStarted.future;
    servers.dispose();
    preferences.values.remove(_manifestKey);
    preferences.readRelease.complete();
    expect(await load, {'server-source'});
    preferences.blockedReadKey = null;
    expect(await servers.loadCachedMediaSourceIds(), isEmpty);
  });

  test('detail clear wins over an older in-flight payload read', () async {
    final preferences = _Preferences();
    final initial = DetailCacheStore(preferences: preferences);
    await initial.saveDetailTarget(
        seedTarget: _target, resolvedTarget: _target);
    initial.dispose();
    preferences.blockedReadKey = _detailKey;
    final repository = LocalStorageCacheRepository(preferences: preferences);
    addTearDown(repository.dispose);
    final load = repository.loadDetailTarget(_target);
    await preferences.readStarted.future;
    await repository.clearDetailCache();
    preferences.readRelease.complete();
    await load;
    expect(repository.peekDetailTarget(_target), isNull);
    expect(await repository.loadDetailTarget(_target), isNull);
  });

  test('provider disposal flushes saves without notifying a dead container',
      () async {
    final container = ProviderContainer();
    final repository = container.read(localStorageCacheRepositoryProvider);
    final save = repository.saveDetailTarget(
      seedTarget: _target,
      resolvedTarget: _target,
    );
    container.dispose();
    await save;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final reloaded = LocalStorageCacheRepository();
    addTearDown(reloaded.dispose);
    expect(await reloaded.loadDetailTarget(_target), isNotNull);
  });

  test('both mutation queues recover after a failed write', () async {
    final preferences = _Preferences()..failNextWrite = true;
    final repository = LocalStorageCacheRepository(preferences: preferences);
    addTearDown(repository.dispose);
    await expectLater(
      repository.saveDetailTarget(seedTarget: _target, resolvedTarget: _target),
      throwsStateError,
    );
    await repository.saveDetailTarget(
        seedTarget: _target, resolvedTarget: _target);
    preferences.failNextWrite = true;
    Future<void> saveServer() => repository.saveEmbyLibrarySnapshot(
          sourceId: 'server-source',
          refreshedAt: DateTime.utc(2026, 9, 20),
        );
    await expectLater(saveServer(), throwsStateError);
    await saveServer();
    expect(await repository.loadCachedMediaSourceIds(),
        {'detail-source', 'server-source'});
  });

  test('merged detail saves stay ahead of a subsequent clear', () async {
    final preferences = _Preferences();
    final repository = LocalStorageCacheRepository(preferences: preferences);
    addTearDown(repository.dispose);
    final other = _target.copyWith(title: 'Other movie', itemId: 'other');
    final first = repository.saveDetailTarget(
      seedTarget: _target,
      resolvedTarget: _target,
    );
    final second = repository.saveDetailTarget(
      seedTarget: other,
      resolvedTarget: other,
    );
    final clear = repository.clearDetailCache();
    await Future.wait([first, second, clear]);
    expect(preferences.writeCounts[_detailKey], 1);
    expect(preferences.values, isNot(contains(_detailKey)));
    expect(await repository.loadDetailTargetsBatch([_target, other]),
        [null, null]);
  });

  test('in-memory detail batches do not persist or touch media-server state',
      () async {
    final preferences = _Preferences();
    final events = <LocalStorageDetailCacheChangeEvent>[];
    final repository = LocalStorageCacheRepository(
      preferences: preferences,
      notifyDetailCacheChanged: events.add,
    );
    addTearDown(repository.dispose);
    await repository.saveDetailTargetsBatchInMemory([
      const DetailTargetCacheSaveRequest(
        seedTarget: _target,
        resolvedTarget: _target,
        metadataRefreshStatus: DetailMetadataRefreshStatus.failed,
      ),
    ]);
    expect(repository.peekDetailTarget(_target), same(_target));
    expect(await repository.loadDetailMetadataRefreshStatus(_target),
        DetailMetadataRefreshStatus.failed);
    expect(events, hasLength(1));
    expect(preferences.values, isEmpty);
    expect(preferences.readCounts.keys, [_detailKey]);
    final reloaded = LocalStorageCacheRepository(preferences: preferences);
    addTearDown(reloaded.dispose);
    expect(await reloaded.loadDetailTarget(_target), isNull);
  });

  test('serialized media-server writes invalidate scoped and summary caches',
      () async {
    final preferences = _Preferences();
    final repository = LocalStorageCacheRepository(preferences: preferences);
    addTearDown(repository.dispose);
    Future<void> save(String section) => repository.saveEmbyLibrarySnapshot(
          sourceId: 'server-source',
          refreshedAt: DateTime.utc(2026, 9, 20),
          itemsBySection: {
            section: [_item(section)]
          },
        );
    await save('old');
    await repository.loadEmbyLibrarySnapshot('server-source', sectionId: 'old');
    await repository.loadEmbyLibrarySnapshot('server-source',
        preferSourceSummary: true);
    await Future.wait([save('intermediate'), save('new')]);
    expect(
        (await repository.loadEmbyLibrarySnapshot('server-source'))
            .itemsBySection
            .keys,
        ['new']);
    expect(
        (await repository.loadEmbyLibrarySnapshot('server-source',
                sectionId: 'old'))
            .hasData,
        isFalse);
    expect(
        (await repository.loadEmbyLibrarySnapshot('server-source',
                preferSourceSummary: true))
            .itemsBySection
            .keys,
        ['new']);
    final reloaded = LocalStorageCacheRepository(preferences: preferences);
    addTearDown(reloaded.dispose);
    expect(
        (await reloaded.loadEmbyLibrarySnapshot('server-source'))
            .itemsBySection
            .keys,
        ['new']);
    expect(preferences.values.keys, hasLength(5));
    expect(preferences.values,
        contains('starflow.local_storage.emby_library_cache.shards.v2'));
    final saveAgain = save('last');
    final clear = repository.clearAllEmbyLibrarySnapshots();
    await Future.wait([saveAgain, clear]);
    expect(preferences.values, isEmpty);
    expect((await repository.loadEmbyLibrarySnapshot('server-source')).hasData,
        isFalse);
  });
}

MediaItem _item(String section) => MediaItem(
      id: section,
      title: section,
      overview: '',
      posterUrl: '',
      year: 2026,
      durationLabel: '',
      genres: const [],
      sectionId: section,
      sourceId: 'server-source',
      sourceName: 'Server',
      sourceKind: MediaSourceKind.emby,
      streamUrl: '',
      addedAt: DateTime.utc(2026, 9, 20),
    );

class _OverriddenRepository extends LocalStorageCacheRepository {
  final cleared = <String>[];

  @override
  CachedDetailState? peekDetailState(MediaDetailTarget seedTarget,
          {bool allowStructuralMismatch = false}) =>
      const CachedDetailState(target: _target);

  @override
  Future<CachedDetailState?> loadDetailState(MediaDetailTarget seedTarget,
          {bool allowStructuralMismatch = false}) async =>
      const CachedDetailState(
        target: _target,
        metadataRefreshStatus: DetailMetadataRefreshStatus.succeeded,
      );

  @override
  Future<void> clearDetailCache() async => cleared.add('details');

  @override
  Future<void> clearAllEmbyLibrarySnapshots() async => cleared.add('servers');
}

class _Preferences implements PreferencesStore {
  final values = <String, String>{};
  final readCounts = <String, int>{};
  final writeCounts = <String, int>{};
  String? blockedReadKey;
  String? blockedWriteKey;
  bool failNextWrite = false;
  final readStarted = Completer<void>();
  final readRelease = Completer<void>();
  final writeStarted = Completer<void>();
  final writeRelease = Completer<void>();

  @override
  Future<String?> getString(String key) async {
    readCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
    final value = values[key];
    if (key == blockedReadKey) {
      if (!readStarted.isCompleted) readStarted.complete();
      await readRelease.future;
    }
    return value;
  }

  @override
  Future<void> setString(String key, String value) async {
    writeCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('test write failure');
    }
    if (key == blockedWriteKey) {
      if (!writeStarted.isCompleted) writeStarted.complete();
      await writeRelease.future;
    }
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<List<String>?> getStringList(String key) async => null;

  @override
  Future<void> setStringList(String key, List<String> value) async =>
      throw UnsupportedError('String lists are not used by cache stores');
}
