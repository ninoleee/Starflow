import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/details/application/detail_page_actions.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

void main() {
  const entry = MediaDetailTarget(
    title: 'Series',
    posterUrl: '',
    overview: '',
    itemType: 'series',
    sourceId: 'fntv-main',
    sourceKind: MediaSourceKind.fntv,
    sourceName: 'FNTV',
    itemId: 'current-series-guid',
    sectionId: 'fntv-section',
  );
  final nas = entry.copyWith(
    sourceId: 'nas-main',
    sourceKind: MediaSourceKind.nas,
    sourceName: 'NAS',
    itemId: 'webdav-series|show',
    sectionId: 'dav-section',
  );
  final otherNas = nas.copyWith(itemId: 'webdav-series|other');

  test('FNTV series entry beats cached choices missing its source', () {
    final plan = DetailCachedStateRestorer().buildPlan(
      pageSeedTarget: entry,
      cachedState: CachedDetailState(
        target: otherNas,
        libraryMatchChoices: [nas, otherNas],
        selectedLibraryMatchIndex: 1,
      ),
    );
    expect(plan.manualOverrideTarget?.sourceId, entry.sourceId);
    expect(plan.manualOverrideTarget?.itemId, entry.itemId);
    expect(plan.manualOverrideTarget?.sectionId, entry.sectionId);
    expect(plan.manualOverrideTarget?.playbackTarget, isNull);
    expect(plan.libraryMatchChoices, [entry, nas, otherNas]);
    expect(plan.selectedLibraryMatchIndex, 0);
  });

  test('FNTV entry also beats a single cached NAS choice', () {
    final plan = DetailCachedStateRestorer().buildPlan(
      pageSeedTarget: entry,
      cachedState: CachedDetailState(target: nas, libraryMatchChoices: [nas]),
    );
    expect(plan.manualOverrideTarget?.sourceId, entry.sourceId);
    expect(plan.libraryMatchChoices, [entry, nas]);
  });

  test('partial resource matches cannot replace the FNTV entry with NAS', () {
    final result = prioritizeDetailLibraryMatchChoices(
      pageSeedTarget: entry,
      choices: [nas],
      currentTarget: nas,
      includePreferredEntryChoice: true,
    );
    expect(result.choices[result.selectedIndex], entry);
    expect(result.matchedPreferredSource, isTrue);
  });

  test('existing FNTV candidate is retained without duplicating the entry', () {
    final enriched = entry.copyWith(overview: 'Cached overview');
    final result = prioritizeDetailLibraryMatchChoices(
      pageSeedTarget: entry,
      choices: [nas, enriched],
      includePreferredEntryChoice: true,
    );
    expect(result.choices, [enriched, nas]);
    expect(result.selectedIndex, 0);
  });

  test('source-free discovery entry preserves the cached selection', () {
    const discovery = MediaDetailTarget(
      title: 'Series',
      posterUrl: '',
      overview: '',
      itemType: 'series',
    );
    final result = prioritizeDetailLibraryMatchChoices(
      pageSeedTarget: discovery,
      choices: [entry, nas],
      fallbackSelectedIndex: 1,
      includePreferredEntryChoice: true,
    );
    expect(result.choices[result.selectedIndex], nas);
    expect(result.choices, hasLength(2));
  });

  test('series without a concrete item cannot become an entry candidate', () {
    expect(
      resolvePreferredEntryLibraryChoice(
        pageSeedTarget: entry.copyWith(itemId: ''),
      ),
      isNull,
    );
  });
}
