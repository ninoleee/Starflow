import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/network/bounded_http_request.dart';
import 'package:starflow/core/scheduling/async_work_pool.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/storage/bounded_memory_map.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/data/media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_engine_router.dart';
import 'package:starflow/features/playback/application/playback_startup_coordinator.dart';
import 'package:starflow/features/playback/application/playback_target_resolver.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('body deadline aborts transport after headers arrive', () async {
    final body = StreamController<List<int>>();
    final client = _StreamingClient(body.stream);
    await expectLater(
        sendBoundedRequest(client, 'GET', Uri.parse('https://test.invalid'),
            timeout: const Duration(milliseconds: 10), maxBytes: 100),
        throwsA(isA<TimeoutException>()));
    expect(client.aborted, isTrue);
    await body.close();
  });

  test('chunked bodies enforce actual bytes and abort', () async {
    final client = _StreamingClient(Stream.fromIterable([
      [1, 2],
      [3, 4]
    ]));
    await expectLater(
        sendBoundedRequest(client, 'GET', Uri.parse('https://test.invalid'),
            timeout: const Duration(seconds: 1), maxBytes: 3),
        throwsA(isA<http.ClientException>()));
    expect(client.aborted, isTrue);
  });

  test('work pool holds slots through completion and releases errors',
      () async {
    final pool = AsyncWorkPool(2);
    final gate = Completer<void>();
    var active = 0;
    var peak = 0;
    final jobs = List.generate(
        8,
        (index) => pool.run(() async {
              active++;
              if (active > peak) peak = active;
              await gate.future;
              active--;
              if (index == 0) throw StateError('expected');
            }).catchError((Object _) {}));
    await Future<void>.delayed(Duration.zero);
    expect(active, 2);
    gate.complete();
    await Future.wait(jobs);
    expect(peak, 2);
    expect(active, 0);
  });

  test('bounded cache refreshes recency and retains cached nulls', () {
    final cache = BoundedMemoryMap<String, int?>(2);
    cache['a'] = null;
    cache['b'] = 2;
    expect(cache['a'], isNull);
    cache['c'] = 3;
    expect(cache.containsKey('a'), isTrue);
    expect(cache.containsKey('b'), isFalse);
  });

  test('lowering pool capacity drains active work before admitting more',
      () async {
    final pool = AsyncWorkPool(2);
    final first = Completer<void>();
    final second = Completer<void>();
    final one = pool.run(() => first.future);
    final two = pool.run(() => second.future);
    var thirdStarted = false;
    final three = pool.run(() async {
      thirdStarted = true;
    });
    pool.capacity = 1;
    first.complete();
    await one;
    expect(thirdStarted, isFalse);
    second.complete();
    await Future.wait([two, three]);
    expect(thirdStarted, isTrue);
  });

  test('detail updates across event turns share one merge window', () async {
    final preferences = _MemoryPreferences();
    final repository = LocalStorageCacheRepository(preferences: preferences);
    addTearDown(repository.dispose);
    final first = repository.saveDetailTarget(
        seedTarget: _detail(0), resolvedTarget: _detail(0));
    await Future<void>.delayed(Duration.zero);
    final second = repository.saveDetailTarget(
        seedTarget: _detail(1), resolvedTarget: _detail(1));
    await Future.wait([first, second]);
    expect(preferences.writes, 1);
  });

  test('detail clear stays after accepted pending writes', () async {
    final preferences = _MemoryPreferences();
    final repository = LocalStorageCacheRepository(preferences: preferences);
    addTearDown(repository.dispose);
    final save = repository.saveDetailTarget(
        seedTarget: _detail(0), resolvedTarget: _detail(0));
    final clear = repository.clearDetailCache();
    await Future.wait([save, clear]);
    expect(await repository.loadDetailTarget(_detail(0)), isNull);
  });

  test('dispose flushes accepted detail saves', () async {
    final preferences = _MemoryPreferences();
    final repository = LocalStorageCacheRepository(preferences: preferences);
    final save = repository.saveDetailTarget(
        seedTarget: _detail(0), resolvedTarget: _detail(0));
    repository.dispose();
    await save;
    expect(preferences.writes, 1);
  });

  test('concurrent cold history reads share one load', () async {
    final preferences = _MemoryPreferences();
    final repository = PlaybackMemoryRepository(preferences: preferences);
    await Future.wait(List.generate(12, (_) => repository.loadSnapshot()));
    expect(preferences.reads, 1);
    repository.invalidateSnapshotCache();
    await repository.loadSnapshot();
    expect(preferences.reads, 2);
  });

  test('rating updates write only changed shards', () async {
    final preferences = _MemoryPreferences();
    final repository = LocalStorageCacheRepository(preferences: preferences);
    addTearDown(repository.dispose);
    await repository.saveEmbyLibrarySnapshot(
        sourceId: 'audit',
        refreshedAt: DateTime.utc(2026, 9, 20),
        itemsBySection: {
          for (var i = 0; i < 2; i++)
            'section-$i': [
              MediaItem.fromJson({
                'id': 'movie-$i',
                'title': 'Audit $i',
                'sourceId': 'audit',
                'sourceKind': 'emby',
                'sectionId': 'section-$i',
                'addedAt': '2026-09-20T00:00:00.000Z',
              })
            ],
        });
    preferences.writes = 0;
    await repository.updateMediaItemRatingCount(
        sourceId: 'audit', itemId: 'movie-0', ratingCount: 100);
    expect(preferences.writes, 2);
  });

  test('resolved playback does not join background refresh cleanup', () async {
    final cancellation = Completer<void>();
    final media = _BlockedCancellationRepository(cancellation.future);
    final container = ProviderContainer(overrides: [
      mediaRepositoryProvider.overrideWithValue(media),
      playbackMemoryRepositoryProvider.overrideWithValue(
          PlaybackMemoryRepository(preferences: _MemoryPreferences())),
      appSettingsProvider.overrideWithValue(AppSettings.fromJson(const {})),
    ]);
    addTearDown(container.dispose);
    final coordinator = PlaybackStartupCoordinator(
        read: container.read,
        targetResolver: PlaybackTargetResolver(read: container.read),
        engineRouter: const PlaybackEngineRouter());
    await coordinator
        .start(
            initialTarget: const PlaybackTarget(
                title: 'Audit',
                sourceId: 'audit',
                sourceName: 'Audit',
                sourceKind: MediaSourceKind.emby,
                streamUrl: 'https://test.invalid/movie.mp4'),
            isTelevision: true,
            isWeb: false,
            targetAlreadyResolved: true)
        .timeout(const Duration(seconds: 1));
    expect(cancellation.isCompleted, isFalse);
    cancellation.complete();
  });
}

MediaDetailTarget _detail(int id) => MediaDetailTarget(
    title: 'Audit $id',
    posterUrl: '',
    overview: '',
    sourceId: 'audit',
    sourceKind: MediaSourceKind.emby,
    itemId: 'movie-$id',
    itemType: 'movie');

class _StreamingClient extends http.BaseClient {
  _StreamingClient(this.body);
  final Stream<List<int>> body;
  bool aborted = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    (request as http.Abortable).abortTrigger!.then((_) => aborted = true);
    return http.StreamedResponse(body, 200, request: request);
  }
}

class _MemoryPreferences implements PreferencesStore {
  final values = <String, String>{};
  int reads = 0;
  int writes = 0;
  @override
  Future<String?> getString(String key) async {
    reads++;
    return values[key];
  }

  @override
  Future<void> setString(String key, String value) async {
    writes++;
    values[key] = value;
  }

  @override
  Future<List<String>?> getStringList(String key) async => null;
  @override
  Future<void> setStringList(String key, List<String> value) async {}
  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

class _BlockedCancellationRepository implements MediaRepository {
  _BlockedCancellationRepository(this.cancellation);
  final Future<void> cancellation;
  @override
  Future<void> cancelActiveWebDavRefreshes({bool includeForceFull = false}) =>
      cancellation;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}
