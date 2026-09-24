import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/data/external_media_structure.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';

void main() {
  test('priority is explicit and confidence is independent of provenance', () {
    final ordered = [
      StructureEvidence.unknown,
      StructureEvidence.inferred,
      StructureEvidence.directory,
      StructureEvidence.filename,
      StructureEvidence.sidecar,
      StructureEvidence.manual
    ];
    for (var index = 1; index < ordered.length; index++) {
      expect(ordered[index].priority, greaterThan(ordered[index - 1].priority));
    }
    expect(StructureEvidence.unknown.confidence, StructureConfidence.unknown);
    expect(StructureEvidence.inferred.confidence, StructureConfidence.inferred);
    expect(StructureEvidence.filename.confidence, StructureConfidence.explicit);
  });

  test('NFO keeps both numbered observations and survives incremental reuse',
      () {
    final named = _structure(2, StructureEvidence.filename);
    final enriched = named.withSidecarNumbers(season: 1, episode: 5);
    expect(enriched.episodeNumber, 5);
    expect(enriched.conflicts.single.field, StructureField.episodeNumber);
    expect(enriched.conflicts.single.selectedValue, '5');
    expect(enriched.conflicts.single.rejectedValue, '2');
    expect(enriched.conflicts.single.rejectedEvidence.source,
        StructureEvidence.filename);
    var reused = enriched;
    for (var i = 0; i < 10; i++) {
      reused = named.preservingStrongerNumbers(reused);
    }
    expect(reused.episodeNumber, 5);
    expect(reused.conflicts, enriched.conflicts);
    final restored = ExternalMediaStructure.fromJson(
        jsonDecode(jsonEncode(reused.toJson())) as Map<String, dynamic>);
    expect(restored, reused);
    expect(restored.hashCode, reused.hashCode);
  });

  test(
      'manual numbers win over sidecar without losing the rejected observation',
      () {
    final manual = _structure(7, StructureEvidence.manual);
    final merged = manual.withSidecarNumbers(episode: 5);
    expect(merged.episodeNumber, 7);
    expect(merged.episodeEvidence, StructureEvidence.manual);
    expect(merged.conflicts.single.selectedValue, '7');
    expect(merged.conflicts.single.rejectedValue, '5');
  });

  test('new equal-priority evidence wins and old JSON stays readable', () {
    final old = ExternalMediaStructure.fromJson({
      'rootPath': '/movies/Show',
      'rootTitle': 'Show',
      'itemType': 'episode',
      'episodeNumber': 2,
      'episodeEvidence': 'sidecar',
    });
    expect(old.evidenceFor(StructureField.rootPath),
        StructureFieldEvidence.unknown);
    expect(old.evidenceFor(StructureField.episodeNumber).ruleId,
        StructureRule.legacy);
    final merged = old.withSidecarNumbers(episode: 5);
    expect(merged.episodeNumber, 5);
    expect(
        merged.conflicts.where((c) => c.field == StructureField.episodeNumber),
        hasLength(1));
    final restored = ExternalMediaStructure.fromJson(old.toJson());
    expect(restored, old);
  });

  test('unknown future fields and sources degrade without inventing evidence',
      () {
    final restored = ExternalMediaStructure.fromJson({
      'fieldEvidence': {
        'futureField': {'source': 'manual', 'ruleId': 'future'},
        'role': {'source': 'futureSource', 'ruleId': 'future.rule'},
      },
      'conflicts': [
        {'field': 'futureField'}
      ],
    });
    expect(restored.fieldEvidence, hasLength(1));
    expect(restored.evidenceFor(StructureField.role).confidence,
        StructureConfidence.unknown);
    expect(restored.conflicts, isEmpty);
  });

  test(
      'diagnostic history is bounded and evidence-only changes affect equality',
      () {
    final named = _structure(2, StructureEvidence.filename);
    var value = named;
    for (var episode = 3; episode < 60; episode++) {
      value = value.withSidecarNumbers(episode: episode);
    }
    expect(value.conflicts.length, lessThanOrEqualTo(32));
    expect(value.conflicts.last.selectedValue, '59');
    expect(named, isNot(_structure(2, StructureEvidence.directory)));
  });

  test('file and directory numbering have distinct evidence', () {
    final items = _scan([
      _pending('/movies/Example Series/Season 2/Example.S02E03.mkv'),
      _pending('/movies/Example Series/Season 2/E04.mkv'),
    ]);
    final explicit = items[0].metadataSeed.structure!;
    final inherited = items[1].metadataSeed.structure!;
    expect(explicit.seasonEvidence, StructureEvidence.filename);
    expect(explicit.evidenceFor(StructureField.episodeNumber).ruleId,
        StructureRule.filenameNumber);
    expect(inherited.seasonEvidence, StructureEvidence.directory);
    expect(inherited.evidenceFor(StructureField.seasonNumber).ruleId,
        StructureRule.directoryNumber);
    expect(inherited.episodeEvidence, StructureEvidence.filename);
    expect(explicit.evidenceFor(StructureField.rootPath).ruleId,
        StructureRule.ownedDirectory);
    expect(explicit.rootPath, '/movies/Example Series');
    expect(explicit.evidenceFor(StructureField.role).ruleId,
        StructureRule.resolvedType);
  });

  test('unnumbered ordering and sibling seasons are identified at assignment',
      () {
    final items = _scan([
      for (final folder in ['Alpha', 'Beta'])
        for (final name in ['First', 'Second'])
          _pending('/movies/Example Series/$folder/$name.mkv'),
    ]);
    for (final item in items) {
      final structure = item.metadataSeed.structure!;
      expect(structure.evidenceFor(StructureField.seasonNumber).ruleId,
          StructureRule.siblingSeason);
      expect(structure.evidenceFor(StructureField.episodeNumber).ruleId,
          StructureRule.orderedEpisode);
      expect(
          structure.episodeEvidence.confidence, StructureConfidence.inferred);
    }
  });

  test('episode directory does not make its default season explicit', () {
    final structure = _scan([
      _pending('/movies/罗永浩的十字路口/004 五条人之仁科/五条人之仁科.mp4'),
    ]).single.metadataSeed.structure!;
    expect(structure.episodeNumber, 4);
    expect(structure.episodeEvidence, StructureEvidence.directory);
    expect(structure.seasonNumber, 1);
    expect(structure.seasonEvidence, StructureEvidence.inferred);
    expect(structure.evidenceFor(StructureField.seasonNumber).ruleId,
        StructureRule.defaultSeason);
  });

  test('grouped leading numbers and title suffixes are not fabricated ordinals',
      () {
    final grouped = _scan([
      _pending('/movies/Example Series/1.First.mkv'),
      _pending('/movies/Example Series/5.Second.mkv'),
    ]);
    expect(grouped.map((i) => i.metadataSeed.episodeNumber), [1, 5]);
    expect(
        grouped.map((i) => i.metadataSeed.structure!
            .evidenceFor(StructureField.episodeNumber)
            .ruleId),
        everyElement(StructureRule.groupedLeadingNumber));
    final suffixed = _scan([
      _pending('/movies/Example Series/Season 1/Example Series01.mkv'),
      _pending('/movies/Example Series/Season 1/Example Series02.mkv'),
    ]);
    expect(
        suffixed.map((i) => i.metadataSeed.structure!
            .evidenceFor(StructureField.episodeNumber)
            .ruleId),
        everyElement(StructureRule.titleSuffixNumber));
  });

  test('sidecar filename conflict is captured during initial scan', () {
    final original = _pending('/movies/Show/Show.S01E02.mkv');
    final resolved = _scan([
      original.copyWith(
          metadataSeed: original.metadataSeed.copyWith(
        itemType: 'episode',
        seasonNumber: 1,
        episodeNumber: 5,
        hasSidecarMatch: true,
      ))
    ]).single.metadataSeed.structure!;
    expect(resolved.episodeNumber, 5);
    expect(resolved.episodeEvidence, StructureEvidence.sidecar);
    expect(resolved.conflicts.single.rejectedValue, '2');
    expect(resolved.conflicts.single.selectedValue, '5');
  });

  test('movie versions and extras carry their actual classification rules', () {
    final resolved = _scan([
      _pending('/movies/Film/1080p.mkv'),
      _pending('/movies/Film/4k.mkv'),
      _pending('/movies/Film/花絮/E01.mkv'),
    ]);
    expect(
        resolved.first.metadataSeed.structure!
            .evidenceFor(StructureField.itemType)
            .ruleId,
        StructureRule.movieVersions);
    final extra = resolved.last.metadataSeed.structure!;
    expect(extra.role, ExternalResourceRole.extra);
    expect(extra.evidenceFor(StructureField.role).ruleId,
        StructureRule.extraKeyword);
    expect(extra.evidenceFor(StructureField.itemType).ruleId,
        StructureRule.inheritedType);
  });
}

ExternalMediaStructure _structure(int episode, StructureEvidence source) =>
    ExternalMediaStructure(
        rootPath: '/movies/Show',
        rootTitle: 'Show',
        itemType: 'episode',
        role: ExternalResourceRole.episode,
        seasonNumber: 1,
        episodeNumber: episode,
        seasonEvidence: StructureEvidence.filename,
        episodeEvidence: source,
        fieldEvidence: {
          StructureField.episodeNumber:
              StructureFieldEvidence(source, StructureRule.filenameNumber),
        });

List<ExternalScanPendingItem> _scan(List<ExternalScanPendingItem> items) =>
    applyExternalDirectoryStructureInference(items,
        source: const MediaSourceConfig(
          id: 'evidence',
          name: 'NAS',
          kind: MediaSourceKind.nas,
          endpoint: 'https://nas.example.com/movies/',
          enabled: true,
          webDavStructureInferenceEnabled: true,
        ));

ExternalScanPendingItem _pending(String path) {
  final segments = path.split('/').where((part) => part.isNotEmpty).toList();
  return ExternalScanPendingItem(
    resourceId: path,
    fileName: segments.last,
    actualAddress: path,
    sectionId: '/movies',
    sectionName: 'movies',
    streamUrl: '',
    streamHeaders: const {},
    addedAt: DateTime.utc(2026, 9, 24),
    modifiedAt: DateTime.utc(2026, 9, 24),
    fileSizeBytes: 1,
    relativeDirectories: segments.sublist(1, segments.length - 1),
    metadataSeed: WebDavMetadataSeed(
        title: segments.last,
        overview: '',
        posterUrl: '',
        posterHeaders: const {},
        backdropUrl: '',
        backdropHeaders: const {},
        logoUrl: '',
        logoHeaders: const {},
        bannerUrl: '',
        bannerHeaders: const {},
        extraBackdropUrls: const [],
        extraBackdropHeaders: const {},
        year: 0,
        durationLabel: '',
        genres: const [],
        directors: const [],
        actors: const [],
        itemType: '',
        seasonNumber: null,
        episodeNumber: null,
        imdbId: '',
        tmdbId: '',
        container: '',
        videoCodec: '',
        audioCodec: '',
        width: null,
        height: null,
        bitrate: null,
        hasSidecarMatch: false),
  );
}
