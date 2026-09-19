import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/details/application/detail_library_match_coordinator.dart';
import 'package:starflow/features/details/application/detail_library_match_service.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/data/media_repository.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/domain/media_models.dart';

const _target = MediaDetailTarget(
  title: 'Movie',
  posterUrl: '',
  overview: '',
  itemType: 'movie',
  year: 2026,
  tmdbId: '123',
  imdbId: 'tt123',
  doubanId: '456',
  tvdbId: '789',
  wikidataId: 'Q123',
);

void main() {
  late _Repository repository;
  late _Indexer indexer;
  late DetailLibraryMatchCoordinator coordinator;

  setUp(() {
    repository = _Repository();
    indexer = _Indexer();
    coordinator = DetailLibraryMatchCoordinator(
      mediaRepository: repository,
      nasMediaIndexer: indexer,
    );
  });

  Future<List<DetailLibraryMatchCandidate>> find(
    List<MediaSourceConfig> sources, {
    MediaDetailTarget seed = _target,
    DetailLibraryMatchTaskController? controller,
    bool skipPreferred = false,
    void Function(List<DetailLibraryMatchCandidate>)? onProgress,
  }) =>
      coordinator.findCandidates(
        allowedSources: sources,
        controller: controller ?? DetailLibraryMatchTaskController(),
        pageSeedTarget: seed,
        target: _target,
        query: 'Display query',
        sourceQuery: 'Source query',
        skipPreferredSourceSearch: skipPreferred,
        onProgress: onProgress,
      );

  test('preferred source finishes before two fallback reads start', () async {
    final progress = <List<DetailLibraryMatchCandidate>>[];
    final result = find(
      [_source('a'), _source('preferred'), _source('b'), _source('c')],
      seed: _target.copyWith(sourceId: 'preferred'),
      onProgress: progress.add,
    );
    await _flush();
    expect(repository.started, ['preferred']);
    repository.complete('preferred', [_item('preferred')]);
    await _flush();
    expect(progress.single.single.item.sourceId, 'preferred');
    expect(repository.started, ['preferred', 'a', 'b']);
    repository.complete('b', [_item('b')]);
    await _flush();
    expect(repository.started, ['preferred', 'a', 'b', 'c']);
    expect(progress.last, hasLength(2));
    expect(progress.first, hasLength(1));
    repository.complete('a', [_item('a')]);
    repository.complete('c', [_item('c')]);
    expect(await result, hasLength(4));
  });

  test('cached entry skips preferred source without searching it as fallback',
      () async {
    final result = find(
      [_source('preferred'), _source('fallback')],
      seed: _target.copyWith(sourceId: 'preferred'),
      skipPreferred: true,
    );
    await _flush();
    expect(repository.started, ['fallback']);
    repository.complete('fallback', []);
    expect(await result, isEmpty);
  });

  test('cancelled reads do not publish progress or start queued sources',
      () async {
    final controller = DetailLibraryMatchTaskController();
    final progress = <List<DetailLibraryMatchCandidate>>[];
    final result = find(
      [_source('a'), _source('b'), _source('queued')],
      controller: controller,
      onProgress: progress.add,
    );
    final expectation = expectLater(
      result,
      throwsA(isA<DetailLibraryMatchCancelledException>()),
    );
    await _flush();
    expect(repository.started, ['a', 'b']);
    controller.cancel();
    repository.complete('a', [_item('a')]);
    repository.complete('b', [_item('b')]);
    await expectation;
    expect(repository.started, ['a', 'b']);
    expect(progress, isEmpty);
  });

  test('cancellation from preferred progress prevents fallback phase',
      () async {
    final controller = DetailLibraryMatchTaskController();
    final result = find(
      [_source('preferred'), _source('fallback')],
      seed: _target.copyWith(sourceId: 'preferred'),
      controller: controller,
      onProgress: (_) => controller.cancel(),
    );
    final expectation = expectLater(
      result,
      throwsA(isA<DetailLibraryMatchCancelledException>()),
    );
    await _flush();
    repository.complete('preferred', [_item('preferred')]);
    await expectation;
    expect(repository.started, ['preferred']);
  });

  test('pre-cancelled empty search still reports cancellation', () async {
    final controller = DetailLibraryMatchTaskController()..cancel();
    await expectLater(
      find([], controller: controller),
      throwsA(isA<DetailLibraryMatchCancelledException>()),
    );
    expect(repository.started, isEmpty);
  });

  test('source failure is isolated and releases a slot for queued work',
      () async {
    final result = find([_source('a'), _source('b'), _source('c')]);
    await _flush();
    repository.pending['a']!.completeError(StateError('source unavailable'));
    await _flush();
    expect(repository.started, ['a', 'b', 'c']);
    repository.complete('b', [_item('b')]);
    repository.complete('c', []);
    expect((await result).single.item.sourceId, 'b');
  });

  test('keeps source-kind order and routes NAS only to cached index', () async {
    final result = find([
      _source('quark', MediaSourceKind.quark),
      _source('nas', MediaSourceKind.nas),
      _source('emby'),
    ]);
    await _flush();
    expect(repository.started, ['emby']);
    expect(indexer.started, ['nas']);
    expect(indexer.ids, ['456', 'tt123', '123', '789', 'Q123']);
    expect(repository.ids, indexer.ids);
    expect(repository.titles, ['Movie', 'Source query']);
    expect(repository.year, 2026);
    expect(repository.limits, [2000]);
    indexer.pending.complete([]);
    await _flush();
    expect(repository.started, ['emby', 'quark']);
    expect(repository.limits, [2000, 2000]);
    repository.complete('emby', []);
    repository.complete('quark', []);
    expect(await result, isEmpty);
  });

  test('deduplicates variants by identity and retains the higher score',
      () async {
    final result = find(
      [_source('a'), _source('b'), _source('c')],
      seed: _target.copyWith(sourceId: 'source', sectionId: 'preferred'),
    );
    await _flush();
    repository.complete('a', [_item('source')]);
    repository.complete('b', [_item('source', sectionId: 'preferred')]);
    await _flush();
    repository.complete('c', [_item('source', variant: 'second-version')]);
    final matches = await result;
    expect(matches, hasLength(2));
    expect(matches.first.item.sectionId, 'preferred');
    expect(matches.first.score, 1e9 + 100000);
    expect(matches.last.item.preferredMediaSourceId, 'second-version');
  });

  test('sorts and limits every progress snapshot and final result to 32',
      () async {
    final progress = <List<DetailLibraryMatchCandidate>>[];
    final result = find(
      [_source('a'), _source('b')],
      seed: _target.copyWith(sectionName: 'priority'),
      onProgress: progress.add,
    );
    await _flush();
    repository.complete('a', [
      for (var i = 0; i < 40; i++) _item('a', id: '$i'),
    ]);
    await _flush();
    repository.complete('b', [
      _item('b', sectionName: 'priority'),
    ]);
    final matches = await result;
    expect(matches, hasLength(32));
    expect(matches.first.item.sourceId, 'b');
    expect(matches.first.score, 1e9 + 50000);
    expect(progress, hasLength(2));
    expect(progress.every((snapshot) => snapshot.length == 32), isTrue);
    expect(progress.first.first.item.sourceId, 'a');
  });

  test('preferred lookup uses id before kind and normalized source name', () {
    final sources = [_source('a'), _source('b', MediaSourceKind.nas)];
    expect(
      DetailLibraryMatchCoordinator.resolvePreferredSources(
        pageSeedTarget: _target.copyWith(
          sourceId: 'a',
          sourceKind: MediaSourceKind.nas,
          sourceName: 'b',
        ),
        allowedSources: sources,
      ).single.id,
      'a',
    );
    expect(
      DetailLibraryMatchCoordinator.resolvePreferredSources(
        pageSeedTarget: _target.copyWith(
          sourceKind: MediaSourceKind.nas,
          sourceName: ' B ',
        ),
        allowedSources: sources,
      ).single.id,
      'b',
    );
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

MediaSourceConfig _source(String id,
        [MediaSourceKind kind = MediaSourceKind.emby]) =>
    MediaSourceConfig(
      id: id,
      name: id,
      kind: kind,
      endpoint: 'https://example.com',
      enabled: true,
    );

MediaItem _item(
  String source, {
  String id = 'movie',
  String sectionId = '',
  String sectionName = '',
  String variant = '',
}) =>
    MediaItem(
      id: id,
      title: 'Movie',
      overview: '',
      posterUrl: '',
      year: 2026,
      durationLabel: '',
      genres: const [],
      itemType: 'movie',
      sourceId: source,
      sourceName: source,
      sourceKind: MediaSourceKind.emby,
      streamUrl: 'https://example.com/$id.mkv',
      tmdbId: '123',
      sectionId: sectionId,
      sectionName: sectionName,
      preferredMediaSourceId: variant,
      addedAt: DateTime.utc(2026),
    );

class _Repository implements MediaRepository {
  final started = <String>[];
  final pending = <String, Completer<List<MediaItem>>>{};
  final limits = <int>[];
  List<String> ids = [];
  List<String> titles = [];
  int year = 0;

  Future<List<MediaItem>> _start(String sourceId, int limit) {
    started.add(sourceId);
    limits.add(limit);
    return (pending[sourceId] = Completer<List<MediaItem>>()).future;
  }

  void complete(String sourceId, List<MediaItem> items) =>
      pending[sourceId]!.complete(items);

  @override
  Future<List<MediaItem>> loadLibraryMatchItems({
    required MediaSourceConfig source,
    String doubanId = '',
    String imdbId = '',
    String tmdbId = '',
    String tvdbId = '',
    String wikidataId = '',
    Iterable<String> titles = const [],
    int year = 0,
    int limit = 2000,
  }) {
    ids = [doubanId, imdbId, tmdbId, tvdbId, wikidataId];
    this.titles = titles.toList();
    this.year = year;
    return _start(source.id, limit);
  }

  @override
  Future<List<MediaItem>> fetchLibrary({
    MediaSourceKind? kind,
    String? sourceId,
    String? sectionId,
    int limit = 200,
  }) {
    expect(kind, MediaSourceKind.quark);
    return _start(sourceId!, limit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Indexer implements NasMediaIndexer {
  final started = <String>[];
  final pending = Completer<List<MediaItem>>();
  List<String> ids = [];

  @override
  Future<List<MediaItem>> loadCachedLibraryMatchItems(
    MediaSourceConfig source, {
    String doubanId = '',
    String imdbId = '',
    String tmdbId = '',
    String tvdbId = '',
    String wikidataId = '',
  }) {
    started.add(source.id);
    ids = [doubanId, imdbId, tmdbId, tvdbId, wikidataId];
    return pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
