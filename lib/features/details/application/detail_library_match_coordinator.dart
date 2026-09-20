import 'package:starflow/core/logging/app_logger.dart';
import 'dart:math' as math;

import 'package:starflow/features/details/application/detail_library_match_service.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/data/media_repository.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';

/// Coordinates source reads without owning page state, focus, or persistence.
class DetailLibraryMatchCoordinator {
  const DetailLibraryMatchCoordinator({
    required this.mediaRepository,
    required this.nasMediaIndexer,
    this.matchService = const DetailLibraryMatchService(),
  });

  final MediaRepository mediaRepository;
  final NasMediaIndexer nasMediaIndexer;
  final DetailLibraryMatchService matchService;

  static const maxMatches = 32;
  static const sourceItemLimit = 2000;
  static const maxConcurrentTasks = 2;

  static List<MediaSourceConfig> resolvePreferredSources({
    required MediaDetailTarget pageSeedTarget,
    required List<MediaSourceConfig> allowedSources,
  }) {
    final preferredSourceId = pageSeedTarget.sourceId.trim();
    if (preferredSourceId.isNotEmpty) {
      return allowedSources
          .where((source) => source.id == preferredSourceId)
          .toList(growable: false);
    }

    final preferredKind = pageSeedTarget.sourceKind;
    final preferredSourceName = pageSeedTarget.sourceName.trim().toLowerCase();
    if (preferredKind == null && preferredSourceName.isEmpty) {
      return const <MediaSourceConfig>[];
    }
    return allowedSources.where((source) {
      if (preferredKind != null && source.kind != preferredKind) return false;
      return preferredSourceName.isEmpty ||
          source.name.trim().toLowerCase() == preferredSourceName;
    }).toList(growable: false);
  }

  Future<List<DetailLibraryMatchCandidate>> findCandidates({
    required List<MediaSourceConfig> allowedSources,
    required DetailLibraryMatchTaskController controller,
    required MediaDetailTarget pageSeedTarget,
    required MediaDetailTarget target,
    required String query,
    required String sourceQuery,
    required bool skipPreferredSourceSearch,
    MetadataMatchResult? metadataMatch,
    void Function(List<DetailLibraryMatchCandidate> matches)? onProgress,
  }) async {
    controller.throwIfCancelled();
    final titles = matchService.buildManualMatchTitles(
      target: target,
      query: query,
      metadataMatch: metadataMatch,
    );
    final sourceTitles = matchService.buildManualMatchTitles(
      target: target,
      query: sourceQuery,
      metadataMatch: metadataMatch,
    );
    final year = matchService.resolveManualMatchYear(target, metadataMatch);
    final doubanId =
        matchService.resolveManualMatchDoubanId(target, metadataMatch);
    final imdbId = matchService.resolveManualMatchImdbId(target, metadataMatch);
    final tmdbId = matchService.resolveManualMatchTmdbId(target, metadataMatch);
    final tvdbId = matchService.resolveManualMatchTvdbId(target);
    final wikidataId = matchService.resolveManualMatchWikidataId(target);
    final byId = <String, DetailLibraryMatchCandidate>{};

    List<DetailLibraryMatchCandidate> snapshot() {
      final sorted = byId.values.toList()
        ..sort((a, b) => b.score.compareTo(a.score));
      return sorted.length <= maxMatches
          ? sorted
          : sorted.take(maxMatches).toList(growable: false);
    }

    Future<List<DetailLibraryMatchCandidate>> loadSource(
      MediaSourceConfig source,
    ) async {
      controller.throwIfCancelled();
      try {
        final List<MediaItem> items;
        if (source.kind.isMediaServer) {
          items = await mediaRepository.loadLibraryMatchItems(
            source: source,
            titles: sourceTitles,
            year: year,
            doubanId: doubanId,
            imdbId: imdbId,
            tmdbId: tmdbId,
            tvdbId: tvdbId,
            wikidataId: wikidataId,
            limit: sourceItemLimit,
          );
        } else if (source.kind == MediaSourceKind.nas) {
          items = await nasMediaIndexer.loadCachedLibraryMatchItems(
            source,
            doubanId: doubanId,
            imdbId: imdbId,
            tmdbId: tmdbId,
            tvdbId: tvdbId,
            wikidataId: wikidataId,
          );
        } else {
          items = await mediaRepository.fetchLibrary(
            kind: MediaSourceKind.quark,
            sourceId: source.id,
            limit: sourceItemLimit,
          );
        }
        controller.throwIfCancelled();
        return matchService
            .buildManualMatchCandidates(
              target: target,
              items: items,
              titles: titles,
              year: year,
              metadataMatch: metadataMatch,
              maxResults: maxMatches,
            )
            .map(
              (candidate) => DetailLibraryMatchCandidate(
                item: candidate.item,
                matchReason: candidate.matchReason,
                score: candidate.score +
                    _preferredItemBoost(candidate.item, pageSeedTarget),
              ),
            )
            .toList(growable: false);
      } on DetailLibraryMatchCancelledException {
        rethrow;
      } catch (error, stackTrace) {
        final sourceLabel =
            source.kind.isMediaServer ? 'emby.library' : source.kind.name;
        appLogError(
            'detail-resource', 'resource.match.source.$sourceLabel.error',
            fields: {'sourceId': source.id, 'sourceName': source.name},
            error: error,
            stackTrace: stackTrace);
        return const <DetailLibraryMatchCandidate>[];
      }
    }

    Future<void> runSources(List<MediaSourceConfig> sources) async {
      // Keep the existing source-kind order within each priority phase.
      final ordered = <MediaSourceConfig>[
        ...sources.where((source) => source.kind.isMediaServer),
        ...sources.where((source) => source.kind == MediaSourceKind.nas),
        ...sources.where((source) => source.kind == MediaSourceKind.quark),
      ];
      var nextIndex = 0;
      Future<void> runWorker() async {
        while (true) {
          controller.throwIfCancelled();
          if (nextIndex >= ordered.length) return;
          final matches = await loadSource(ordered[nextIndex++]);
          controller.throwIfCancelled();
          if (matches.isEmpty) continue;
          for (final candidate in matches) {
            final key = matchService.libraryMatchCandidateKey(candidate.item);
            final existing = byId[key];
            if (existing == null || candidate.score > existing.score) {
              byId[key] = candidate;
            }
          }
          onProgress?.call(snapshot());
        }
      }

      await Future.wait(List.generate(
        math.min(maxConcurrentTasks, ordered.length),
        (_) => runWorker(),
      ));
    }

    final preferredSources = resolvePreferredSources(
      pageSeedTarget: pageSeedTarget,
      allowedSources: allowedSources,
    );
    final preferredKeys = preferredSources.map(_sourceKey).toSet();
    final fallbackSources = allowedSources
        .where((source) => !preferredKeys.contains(_sourceKey(source)))
        .toList(growable: false);
    if (!skipPreferredSourceSearch) {
      await runSources(preferredSources);
    }
    controller.throwIfCancelled();
    await runSources(fallbackSources);
    controller.throwIfCancelled();
    return snapshot();
  }

  static String _sourceKey(MediaSourceConfig source) =>
      '${source.kind.name}|${source.id}|${source.name.trim().toLowerCase()}';

  static int _preferredItemBoost(
    MediaItem item,
    MediaDetailTarget pageSeedTarget,
  ) {
    final preferredSourceId = pageSeedTarget.sourceId.trim();
    if (preferredSourceId.isNotEmpty &&
        item.sourceId.trim() != preferredSourceId) {
      return 0;
    }
    final preferredSectionId = pageSeedTarget.sectionId.trim();
    if (preferredSectionId.isNotEmpty &&
        item.sectionId.trim() == preferredSectionId) {
      return 100000;
    }
    final preferredSectionName =
        pageSeedTarget.sectionName.trim().toLowerCase();
    if (preferredSectionName.isEmpty) return 0;
    final sectionLabel =
        '${item.sectionName} ${item.actualAddress}'.trim().toLowerCase();
    if (item.sectionName.trim().toLowerCase() == preferredSectionName ||
        sectionLabel.contains(preferredSectionName)) {
      return 50000;
    }
    return 0;
  }
}
