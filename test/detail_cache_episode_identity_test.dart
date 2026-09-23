import 'package:starflow/features/details/application/detail_page_actions.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('reimported FNTV series never restores the deleted series GUID',
      () async {
    final repository = await _repository();
    const old = MediaDetailTarget(
      title: '半泽直树',
      posterUrl: '',
      overview: '',
      sourceId: 'fntv',
      sourceKind: MediaSourceKind.fntv,
      itemId: 'deleted-guid',
      itemType: 'series',
      tmdbId: 'same-show',
    );
    final fresh = old.copyWith(itemId: 'new-guid');
    await repository.saveDetailTarget(
      seedTarget: old,
      resolvedTarget: old,
      libraryMatchChoices: [old],
    );
    expect(await repository.loadDetailTarget(fresh), isNull);
    expect(
        await repository.loadDetailState(fresh, allowStructuralMismatch: true),
        isNull);
    await repository.saveDetailTarget(
      seedTarget: fresh,
      resolvedTarget: fresh,
      libraryMatchChoices: [fresh],
    );
    final reloaded = await _repository();
    expect((await reloaded.loadDetailTarget(fresh))?.itemId, 'new-guid');
    expect((await reloaded.loadDetailTarget(old))?.itemId, 'deleted-guid');
  });

  test('directory entry preference beats a sibling on the same NAS', () {
    final first =
        _target(itemType: 'series').copyWith(itemId: 'webdav-series|first');
    final second = first.copyWith(itemId: 'webdav-series|first(1)');
    final choices = [second, first];
    expect(
        prioritizeDetailLibraryMatchChoices(
                pageSeedTarget: first, choices: choices)
            .selectedIndex,
        1);
    expect(
        prioritizeDetailLibraryMatchChoices(
                pageSeedTarget: second,
                choices: choices,
                fallbackSelectedIndex: 1)
            .selectedIndex,
        0);
  });

  test(
      'same-title directory series retain independent detail and resource choices',
      () async {
    final repository = await _repository();
    final first = _target(itemType: 'series')
        .copyWith(itemId: 'webdav-series|structure:first', title: '不良执念清除师');
    final second = first.copyWith(itemId: 'webdav-series|structure:first(1)');
    for (final target in [first, second]) {
      await repository.saveDetailTarget(
          seedTarget: target,
          resolvedTarget: target,
          libraryMatchChoices: [target]);
    }
    final reloaded = await _repository();
    for (final target in [first, second]) {
      final state =
          await reloaded.loadDetailState(target, allowStructuralMismatch: true);
      expect(state?.target.itemId, target.itemId);
      expect(state?.libraryMatchChoices.single.itemId, target.itemId);
    }
  });

  test('aliases pointing to a sibling directory cannot restore its target',
      () async {
    final repository = await _repository();
    final first = _target(itemType: 'series')
        .copyWith(itemId: 'webdav-series|structure:first');
    final second = first.copyWith(itemId: 'webdav-series|structure:first(1)');
    // The first directory cannot inherit the second directory's target.
    await repository.saveDetailTarget(
        seedTarget: first,
        resolvedTarget: second,
        libraryMatchChoices: [second]);
    expect(
        await repository.loadDetailState(first, allowStructuralMismatch: true),
        isNull);
    await repository.saveDetailTarget(seedTarget: first, resolvedTarget: first);
    expect((await repository.loadDetailTarget(first))?.itemId, first.itemId);
    expect((await repository.loadDetailTarget(second))?.itemId, second.itemId);
  });

  test('lookup keys distinguish seasons and episodes sharing series metadata',
      () {
    final targets = [
      _target(season: 1, episode: 16),
      _target(season: 2, episode: 2),
      _target(season: 3, episode: 3),
      _target(season: 1, episode: 2),
      _target(season: 0, episode: 2),
      _target(season: 1),
      _target(season: 2),
    ];
    final keys = targets
        .map((target) =>
            LocalStorageCacheRepository.buildLookupKeys(target).toSet())
        .toList();
    for (var left = 0; left < keys.length; left++) {
      for (var right = left + 1; right < keys.length; right++) {
        expect(keys[left].intersection(keys[right]), isEmpty);
      }
    }
  });

  test('saving a different episode cannot overwrite cached playback choices',
      () async {
    final repository = await _repository();
    final first = _target(season: 1, episode: 16);
    final second = _target(season: 2, episode: 2);
    final third = _target(season: 3, episode: 3);
    for (final target in [first, second, third]) {
      await repository.saveDetailTarget(
        seedTarget: target,
        resolvedTarget: target,
        libraryMatchChoices: [target],
      );
    }

    final reloaded = await _repository();
    for (final target in [first, second, third]) {
      final state = await reloaded.loadDetailState(
        target,
        allowStructuralMismatch: true,
      );
      expect(state?.target.itemId, target.itemId);
      expect(state?.target.playbackTarget?.itemId, target.itemId);
      expect(state?.libraryMatchChoices.single.itemId, target.itemId);
    }
    expect(
      await reloaded.loadDetailState(_target(season: 2, episode: 16)),
      isNull,
    );
  });

  test('season detail records cannot replace another season or an episode',
      () async {
    final repository = await _repository();
    final targets = [
      _target(season: 1),
      _target(season: 2),
      _target(season: 1, episode: 16),
    ];
    for (final target in targets) {
      await repository.saveDetailTarget(
          seedTarget: target, resolvedTarget: target);
    }
    for (final target in targets) {
      expect(
          (await repository.loadDetailTarget(target))?.itemId, target.itemId);
    }
  });

  test('same episode still restores an explicitly selected file variant',
      () async {
    final repository = await _repository();
    final seed = _target(season: 2, episode: 2);
    final variant = _target(season: 2, episode: 2, variant: 'alternate');
    await repository.saveDetailTarget(
      seedTarget: seed,
      resolvedTarget: variant,
      libraryMatchChoices: [seed, variant],
      selectedLibraryMatchIndex: 1,
    );
    final state = await repository.loadDetailState(seed);
    expect(state?.target.itemId, variant.itemId);
    expect(state?.selectedLibraryMatchIndex, 1);
    expect(state?.libraryMatchChoices, hasLength(2));
  });

  test('unnumbered episodes only expose their concrete resource lookup key',
      () async {
    final repository = await _repository();
    final first = _target(itemType: 'episode', variant: 'first');
    final second = _target(itemType: 'episode', variant: 'second');
    expect(LocalStorageCacheRepository.buildLookupKeys(first), [
      'library|nas-main|${first.itemId}',
    ]);
    await repository.saveDetailTarget(seedTarget: first, resolvedTarget: first);
    expect(await repository.loadDetailTarget(first), isNotNull);
    expect(await repository.loadDetailTarget(second), isNull);
  });

  test('uses playback episode numbers when detail numbers are absent', () {
    final first = _target(season: 1, episode: 16);
    final second = _target(season: 2, episode: 2);
    MediaDetailTarget withoutDetailNumbers(MediaDetailTarget target) {
      return MediaDetailTarget.fromJson({
        ...target.toJson(),
        'seasonNumber': null,
        'episodeNumber': null,
      });
    }

    expect(
      LocalStorageCacheRepository.buildLookupKeys(withoutDetailNumbers(first)),
      LocalStorageCacheRepository.buildLookupKeys(first),
    );
    expect(
      LocalStorageCacheRepository.buildLookupKeys(withoutDetailNumbers(second))
          .toSet()
          .intersection(
              LocalStorageCacheRepository.buildLookupKeys(first).toSet()),
      isEmpty,
    );
  });
}

Future<LocalStorageCacheRepository> _repository() async {
  final repository = LocalStorageCacheRepository(
    sharedPreferences: await SharedPreferences.getInstance(),
  );
  addTearDown(repository.dispose);
  return repository;
}

MediaDetailTarget _target({
  int? season,
  int? episode,
  String? itemType,
  String variant = 'primary',
}) {
  final type = itemType ?? (episode == null ? 'season' : 'episode');
  final id = '$type-$season-$episode-$variant';
  return MediaDetailTarget(
    title: 'Local Perspective',
    searchQuery: 'Local Perspective',
    posterUrl: '',
    overview: '',
    itemId: id,
    sourceId: 'nas-main',
    sourceKind: MediaSourceKind.nas,
    itemType: type,
    seasonNumber: season,
    episodeNumber: episode,
    doubanId: 'shared-series',
    imdbId: 'tt1234567',
    tmdbId: 'shared-series',
    tvdbId: 'shared-series',
    wikidataId: 'Q12345',
    playbackTarget: type != 'episode'
        ? null
        : PlaybackTarget(
            title: 'Local Perspective',
            sourceId: 'nas-main',
            sourceName: 'NAS',
            sourceKind: MediaSourceKind.nas,
            itemId: id,
            itemType: type,
            seriesId: 'local-perspective',
            seriesTitle: 'Local Perspective',
            seasonNumber: season,
            episodeNumber: episode,
            streamUrl: 'https://media.example.com/$id.mp4',
          ),
  );
}
