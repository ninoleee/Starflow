import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:starflow/features/library/data/nas_media_index_models.dart';
import 'package:starflow/features/library/data/nas_media_index_store.dart';
import 'package:starflow/features/library/domain/media_models.dart';

void main() {
  test('loads only the requested NAS section at the database layer', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'nas-section-scope-test.db',
    );
    addTearDown(database.close);
    final store = SembastNasMediaIndexStore(
      databaseOpener: () async => database,
    );
    final indexedAt = DateTime.utc(2026, 8, 24);
    final moviesRecord = _record(
      id: 'movie-1',
      sectionId: 'movies',
      indexedAt: indexedAt,
    );
    final showsRecord = _record(
      id: 'show-1',
      sectionId: 'shows',
      indexedAt: indexedAt,
    );

    await store.replaceSourceRecords(
      sourceId: 'nas-main',
      records: <NasMediaIndexRecord>[moviesRecord, showsRecord],
      state: NasMediaIndexSourceState(
        sourceId: 'nas-main',
        lastIndexedAt: indexedAt,
        recordCount: 2,
        scopeKey: 'scope',
      ),
    );

    final scoped = await store.loadSourceRecords(
      'nas-main',
      sectionId: 'movies',
    );
    final full = await store.loadSourceRecords('nas-main');

    expect(scoped.map((record) => record.resourceId), <String>['movie-1']);
    expect(full.map((record) => record.resourceId),
        containsAll(<String>['movie-1', 'show-1']));
  });
}

NasMediaIndexRecord _record({
  required String id,
  required String sectionId,
  required DateTime indexedAt,
}) {
  return NasMediaIndexRecord(
    id: NasMediaIndexRecord.buildRecordId(
      sourceId: 'nas-main',
      resourceId: id,
    ),
    sourceId: 'nas-main',
    sectionId: sectionId,
    sectionName: sectionId,
    resourceId: id,
    resourcePath: '/$sectionId/$id.mkv',
    fingerprint: id,
    fileSizeBytes: 1024,
    modifiedAt: indexedAt,
    indexedAt: indexedAt,
    scrapedAt: indexedAt,
    recognizedTitle: id,
    searchQuery: id,
    originalFileName: '$id.mkv',
    parentTitle: '',
    recognizedYear: 2026,
    recognizedItemType: 'movie',
    preferSeries: false,
    sidecarStatus: NasMetadataFetchStatus.never,
    wmdbStatus: NasMetadataFetchStatus.never,
    tmdbStatus: NasMetadataFetchStatus.never,
    imdbStatus: NasMetadataFetchStatus.never,
    item: MediaItem(
      id: id,
      title: id,
      overview: '',
      posterUrl: '',
      year: 2026,
      durationLabel: '',
      genres: const <String>[],
      itemType: 'movie',
      sectionId: sectionId,
      sectionName: sectionId,
      sourceId: 'nas-main',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
      streamUrl: 'https://nas.example/$sectionId/$id.mkv',
      addedAt: indexedAt,
    ),
  );
}
