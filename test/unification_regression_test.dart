import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/details/domain/cached_artwork.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/application/library_cached_items.dart';
import 'package:starflow/features/library/data/nfo_metadata.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_source_identity.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_memory_policy.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/search/application/cloud_save_postprocessing.dart';
import 'package:starflow/features/search/domain/cloud_save_feedback.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const _target = PlaybackTarget(
    title: 'Film',
    sourceId: 'nas',
    sourceName: 'NAS',
    sourceKind: MediaSourceKind.nas,
    streamUrl: '',
    actualAddress: 'https://nas.test/A_B.mkv',
    seriesId: 'series');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('URL and authentication stay atomic for every artwork role', () {
    const live = MediaDetailTarget(
        title: 'Film',
        overview: '',
        posterUrl: 'https://nas.test/a',
        posterHeaders: {'Authorization': 'private'},
        backdropHeaders: {'Cookie': 'private'},
        logoHeaders: {'Cookie': 'private'},
        bannerHeaders: {'Cookie': 'private'},
        extraBackdropHeaders: {'Cookie': 'private'});
    const cached = MediaDetailTarget(
        title: 'Film',
        overview: '',
        posterUrl: 'https://public.test/a',
        backdropUrl: 'https://public.test/b',
        logoUrl: 'https://public.test/l',
        bannerUrl: 'https://public.test/c',
        extraBackdropUrls: ['https://public.test/e']);
    for (final preserve in [true, false]) {
      final merged = overlayCachedArtwork(live, cached,
          preserveLiveSecondaryArtwork: preserve);
      expect([
        merged.posterHeaders,
        merged.backdropHeaders,
        merged.logoHeaders,
        merged.bannerHeaders,
        merged.extraBackdropHeaders
      ], everyElement(isEmpty));
    }
    final item = MediaItem(
        id: 'film',
        title: 'Film',
        overview: '',
        posterUrl: live.posterUrl,
        posterHeaders: live.posterHeaders,
        year: 2026,
        durationLabel: '',
        genres: const [],
        sourceId: 'nas',
        sourceName: 'NAS',
        sourceKind: MediaSourceKind.nas,
        streamUrl: '',
        addedAt: DateTime.utc(2026));
    expect(
        mergeLibraryItemWithCachedDetails(item: item, cachedTarget: cached)
            .posterHeaders,
        isEmpty);
  });
  test('serialized writes, clear, failure recovery and old-key verification',
      () async {
    final store = _Store();
    final repository = PlaybackMemoryRepository(preferences: store);
    final progress = repository.saveProgress(
        target: _target,
        position: const Duration(seconds: 20),
        duration: const Duration(minutes: 2));
    await Future.wait([
      progress,
      repository.saveSkipPreference(SeriesSkipPreference(
          seriesKey: 'series|nas|series', updatedAt: DateTime.utc(2026)))
    ]);
    expect((await repository.loadSnapshot()).items, hasLength(1));
    expect((await repository.loadSnapshot()).skipPreferences, hasLength(1));
    store.failWrite = true;
    await expectLater(
        repository.saveProgress(
            target: _target,
            position: const Duration(seconds: 30),
            duration: const Duration(minutes: 2)),
        throwsStateError);
    expect(
        (await repository.loadEntryForTarget(_target))!.position.inSeconds, 20);
    await repository.clearAll();
    expect((await repository.loadSnapshot()).items, isEmpty);
    store.failWrite = false;
    await repository.saveSkipPreference(
        SeriesSkipPreference(seriesKey: 'new', updatedAt: DateTime.utc(2026)));
    repository.invalidateSnapshotCache();
    expect((await repository.loadSnapshot()).items, isEmpty);
    final legacy = PlaybackProgressEntry(
        key: 'path|nas|lossy', target: _target, updatedAt: DateTime.utc(2026));
    final snapshot = PlaybackMemorySnapshot(items: {legacy.key: legacy});
    expect(repository.entryForTargetFromSnapshot(snapshot, _target), isNotNull);
    final forgedKey = PlaybackMemorySnapshot(items: {
      buildPlaybackItemKey(_target): legacy.copyWith(
          target: _target.copyWith(actualAddress: 'https://nas.test/AB.mkv')),
    });
    expect(repository.entryForTargetFromSnapshot(forgedKey, _target), isNull);
    expect(
        repository.entryForTargetFromSnapshot(snapshot,
            _target.copyWith(actualAddress: 'https://nas.test/AB.mkv')),
        isNull);
  });
  test('invalidated in-flight read cannot reinstall an old snapshot', () async {
    final store = _Store();
    final repository = PlaybackMemoryRepository(preferences: store);
    store.pendingRead = Completer<String?>();
    final read = repository.loadSnapshot();
    await Future<void>.delayed(Duration.zero);
    repository.invalidateSnapshotCache();
    final old = store.pendingRead!;
    store.pendingRead = null;
    old.complete(jsonEncode(PlaybackMemorySnapshot(items: {
      'old': PlaybackProgressEntry(
          key: 'old', target: _target, updatedAt: DateTime.utc(2026))
    }).toJson()));
    expect((await read).items, isEmpty);
  });
  test(
      'resource identity preserves punctuation, case, encoded separators and origin',
      () {
    final values = [
      'https://nas.test/A_B.mkv',
      'https://nas.test/AB.mkv',
      'https://nas.test/a_b.mkv',
      'https://nas.test/A%2FB.mkv',
      'https://nas.test/A/B.mkv',
      'https://other.test/A_B.mkv',
      'https://nas.test/video?id=1',
      'https://nas.test/video?id=2',
    ];
    expect(
        values
            .map(
                (v) => buildPlaybackItemKey(_target.copyWith(actualAddress: v)))
            .toSet(),
        hasLength(values.length));
    expect(
        buildPlaybackItemKey(
            _target.copyWith(actualAddress: '${values.first}?token=old')),
        buildPlaybackItemKey(
            _target.copyWith(actualAddress: '${values.first}?token=new')));
  });
  test('full origin alignment and both provider reference lists', () {
    const source = MediaSourceConfig(
        id: 'nas',
        name: 'NAS',
        kind: MediaSourceKind.nas,
        endpoint: 'https://nas.test:8443/dav/',
        enabled: true);
    const old = NetworkStorageWebDavDirectory(
        sourceId: 'nas', directoryId: 'http://nas.test:8080/dav/Movies/');
    const missing = NetworkStorageWebDavDirectory(
        sourceId: 'gone', directoryId: 'https://gone/dav/');
    expect(alignMediaSourceLocationToCurrentRoot(old.directoryId, source),
        'https://nas.test:8443/dav/Movies/');
    final result = reconcileSettingsMediaSourceReferences(
        SeedData.defaultSettings.copyWith(
            mediaSources: [source],
            networkStorage: const NetworkStorageConfig(
                syncDeleteQuarkWebDavDirectories: [old, missing],
                syncDelete115WebDavDirectories: [old, missing])));
    for (final entries in [
      result.networkStorage.syncDeleteQuarkWebDavDirectories,
      result.networkStorage.syncDelete115WebDavDirectories
    ]) {
      expect(entries, hasLength(1));
      expect(entries.single.directoryId, 'https://nas.test:8443/dav/Movies/');
    }
  });
  test('shared NFO fallback, transport artwork and merge rules', () {
    const xml =
        '<episodedetails><title>Episode</title><outline>Outline</outline><aired>2026-09-20</aired><durationinseconds>5400</durationinseconds><season>1</season><episode>2</episode><poster>poster.jpg</poster><fanart><thumb>https://public.test/1.jpg</thumb><thumb>https://public.test/2.jpg</thumb></fanart><uniqueid type="imdb">tt123</uniqueid><fileinfo><container>mkv</container><streamdetails><video><codec>hevc</codec><width>1920</width></video><audio><codec>aac</codec></audio></streamdetails></fileinfo></episodedetails>';
    final cloud = parseNfoMetadata(xml)!;
    final nas = parseNfoMetadata(xml,
        resolveArtwork: (v) =>
            Uri.parse('https://nas.test/film.nfo').resolve(v).toString())!;
    expect(cloud.overview, 'Outline');
    expect(cloud.durationLabel, '90分钟');
    expect(cloud.year, 2026);
    expect(cloud.thumbUrl, isEmpty);
    expect(nas.thumbUrl, 'https://nas.test/poster.jpg');
    expect(cloud.extraBackdropUrls, hasLength(2));
    expect(cloud.container, 'mkv');
    expect(cloud.videoCodec, 'hevc');
    expect(cloud.audioCodec, 'aac');
    expect(cloud.width, 1920);
    expect(cloud.imdbId, 'tt123');
    expect(cloud.itemType, 'episode');
    expect(cloud.episodeNumber, 2);
    expect(
        mergeNfoMetadata(
                primary:
                    parseNfoMetadata('<movie><title>Primary</title></movie>'),
                secondary: cloud)!
            .overview,
        'Outline');
    expect(parseNfoMetadata('<broken'), isNull);
  });
  test('post-save failure does not become a transfer failure', () async {
    final result = await triggerSavedCloudStrm(
        drive: CloudSaveDrive.quark,
        trigger: () async => throw StateError('offline'));
    expect(result.result, isNull);
    expect(result.failure, isNotEmpty);
    var refreshed = false;
    await refreshSavedCloudMedia(
        drive: CloudSaveDrive.quark,
        refresh: () async {
          refreshed = true;
        });
    expect(refreshed, isTrue);
  });
  test('Dart shared playback memory contract', () {
    final fixture = jsonDecode(
        File('test/fixtures/playback_memory_contract.json')
            .readAsStringSync()) as Map;
    for (final c in fixture['cases'] as List) {
      final entry = PlaybackProgressEntry(
          key: 'test',
          target: _target,
          updatedAt: DateTime.utc(2026),
          position: Duration(milliseconds: c['positionMs'] as int),
          duration: Duration(milliseconds: c['durationMs'] as int),
          progress: (c['progress'] as num).toDouble(),
          completed: c['completed'] as bool);
      expect(
          entry.canResume ? entry.position.inMilliseconds : 0, c['resumeMs']);
      expect(
          playbackMemoryCompleted(
              positionMs: entry.position.inMilliseconds,
              durationMs: entry.duration.inMilliseconds,
              progress: entry.progress),
          c['isCompleted']);
    }
    expect(
        (fixture['timestamps'] as List)
            .map((s) => DateTime.parse(s as String).millisecondsSinceEpoch)
            .toSet(),
        hasLength(1));
    expect(PlaybackMemoryRepository.recentEntryLimit, 20);
  });
}

class _Store implements PreferencesStore {
  String? raw;
  bool failWrite = false;
  Completer<String?>? pendingRead;
  @override
  Future<String?> getString(String key) async =>
      pendingRead == null ? raw : await pendingRead!.future;
  @override
  Future<void> setString(String key, String value) async {
    if (failWrite) throw StateError('write failed');
    raw = value;
  }

  @override
  Future<void> remove(String key) async {
    raw = null;
  }

  @override
  Future<List<String>?> getStringList(String key) async => null;
  @override
  Future<void> setStringList(String key, List<String> value) async {}
}
