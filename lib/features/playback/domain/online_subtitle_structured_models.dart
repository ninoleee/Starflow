import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

enum StructuredSubtitleQueryKind {
  hash,
  imdbId,
  tmdbId,
  episode,
  titleYear,
  titleOnly,
}

enum SubtitleValidationStatus {
  pending,
  validated,
  skipped,
  failed,
}

class OnlineSubtitleSearchRequest {
  const OnlineSubtitleSearchRequest({
    this.query = '',
    this.title = '',
    this.originalTitle = '',
    this.year,
    this.imdbId = '',
    this.tmdbId = '',
    this.seasonNumber,
    this.episodeNumber,
    this.filePath = '',
    this.fileSizeBytes,
    this.fileHash = '',
    this.languages = const [],
    this.preferHearingImpaired = false,
    this.preferForced = false,
    this.context = const {},
  });

  final String query;
  final String title;
  final String originalTitle;
  final int? year;
  final String imdbId;
  final String tmdbId;
  final int? seasonNumber;
  final int? episodeNumber;
  final String filePath;
  final int? fileSizeBytes;
  final String fileHash;
  final List<String> languages;
  final bool preferHearingImpaired;
  final bool preferForced;
  final Map<String, String> context;

  bool get isEpisode => seasonNumber != null && episodeNumber != null;
  String get normalizedTitle => title.trim();
  String get normalizedOriginalTitle => originalTitle.trim();
  String get normalizedQuery => query.trim();
  String get normalizedImdbId => imdbId.trim();
  String get normalizedTmdbId => tmdbId.trim();
  String get normalizedFileHash => fileHash.trim();
  String get normalizedFilePath => filePath.trim();

  List<String> get normalizedLanguages => languages
      .map((item) => item.trim().toLowerCase())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);

  bool get hasStructuredIdentity =>
      normalizedFileHash.isNotEmpty ||
      normalizedImdbId.isNotEmpty ||
      normalizedTmdbId.isNotEmpty ||
      normalizedTitle.isNotEmpty ||
      normalizedOriginalTitle.isNotEmpty ||
      normalizedQuery.isNotEmpty;

  List<StructuredSubtitleQuery> buildQueryPlan() {
    final plan = <StructuredSubtitleQuery>[];

    if (normalizedFileHash.isNotEmpty) {
      plan.add(
        StructuredSubtitleQuery(
          kind: StructuredSubtitleQueryKind.hash,
          query: normalizedFileHash,
          metadata: {
            if (fileSizeBytes != null) 'file_size': '${fileSizeBytes!}',
            if (normalizedFilePath.isNotEmpty)
              'file_name': p.basename(normalizedFilePath),
          },
        ),
      );
    }

    if (normalizedImdbId.isNotEmpty) {
      plan.add(
        StructuredSubtitleQuery(
          kind: StructuredSubtitleQueryKind.imdbId,
          query: normalizedImdbId,
        ),
      );
    }

    if (normalizedTmdbId.isNotEmpty) {
      plan.add(
        StructuredSubtitleQuery(
          kind: StructuredSubtitleQueryKind.tmdbId,
          query: normalizedTmdbId,
        ),
      );
    }

    if (isEpisode) {
      final episodeQuery = [
        if (normalizedTitle.isNotEmpty) normalizedTitle,
        'S${seasonNumber!.toString().padLeft(2, '0')}E${episodeNumber!.toString().padLeft(2, '0')}',
      ].join(' ');
      if (episodeQuery.trim().isNotEmpty) {
        plan.add(
          StructuredSubtitleQuery(
            kind: StructuredSubtitleQueryKind.episode,
            query: episodeQuery.trim(),
            metadata: {
              'season': '${seasonNumber!}',
              'episode': '${episodeNumber!}',
            },
          ),
        );
      }
    }

    final titleYearQuery = [
      if (normalizedTitle.isNotEmpty) normalizedTitle,
      if (!isEpisode && (year ?? 0) > 0) '${year!}',
    ].join(' ').trim();
    if (titleYearQuery.isNotEmpty) {
      plan.add(
        StructuredSubtitleQuery(
          kind: StructuredSubtitleQueryKind.titleYear,
          query: titleYearQuery,
        ),
      );
    }

    for (final candidate in {
      normalizedTitle,
      normalizedOriginalTitle,
      normalizedQuery,
    }) {
      if (candidate.isEmpty) {
        continue;
      }
      plan.add(
        StructuredSubtitleQuery(
          kind: StructuredSubtitleQueryKind.titleOnly,
          query: candidate,
        ),
      );
    }

    final unique = <String>{};
    return plan.where((item) {
      final key =
          '${item.kind.name}|${item.query}|${jsonEncode(item.metadata)}';
      return unique.add(key);
    }).toList(growable: false);
  }

  factory OnlineSubtitleSearchRequest.fromPlaybackTarget(
    PlaybackTarget target, {
    String query = '',
    String originalTitle = '',
    String imdbId = '',
    String tmdbId = '',
    String filePath = '',
    String fileHash = '',
    List<String> languages = const [],
    Map<String, String> context = const {},
  }) {
    final title = target.resolvedSeriesTitle.trim().isNotEmpty
        ? target.resolvedSeriesTitle.trim()
        : target.title.trim();
    return OnlineSubtitleSearchRequest(
      query: query.trim(),
      title: title,
      originalTitle: originalTitle,
      year: target.year > 0 ? target.year : null,
      imdbId: imdbId,
      tmdbId: tmdbId,
      seasonNumber: target.seasonNumber,
      episodeNumber: target.episodeNumber,
      filePath: filePath.isNotEmpty
          ? filePath
          : (target.actualAddress.trim().isNotEmpty
              ? target.actualAddress
              : target.streamUrl),
      fileSizeBytes: target.fileSizeBytes,
      fileHash: fileHash,
      languages: languages,
      context: {
        'item_id': target.itemId,
        'item_type': target.itemType,
        'source_id': target.sourceId,
        'source_kind': target.sourceKind.name,
        ...context,
      },
    );
  }
}

class StructuredSubtitleQuery {
  const StructuredSubtitleQuery({
    required this.kind,
    required this.query,
    this.metadata = const {},
  });

  final StructuredSubtitleQueryKind kind;
  final String query;
  final Map<String, String> metadata;
}

class ProviderSubtitleHit {
  const ProviderSubtitleHit({
    required this.id,
    required this.source,
    required this.providerLabel,
    required this.title,
    required this.downloadUrl,
    required this.packageName,
    required this.packageKind,
    this.detailUrl = '',
    this.version = '',
    this.formatLabel = '',
    this.languageLabel = '',
    this.sourceLabel = '',
    this.publishDateLabel = '',
    this.ratingLabel = '',
    this.downloadCount = 0,
    this.imdbId = '',
    this.tmdbId = '',
    this.seasonNumber,
    this.episodeNumber,
    this.releaseNames = const [],
    this.hearingImpaired = false,
    this.forced = false,
    this.raw = const {},
  });

  final String id;
  final OnlineSubtitleSource source;
  final String providerLabel;
  final String title;
  final String downloadUrl;
  final String packageName;
  final SubtitlePackageKind packageKind;
  final String detailUrl;
  final String version;
  final String formatLabel;
  final String languageLabel;
  final String sourceLabel;
  final String publishDateLabel;
  final String ratingLabel;
  final int downloadCount;
  final String imdbId;
  final String tmdbId;
  final int? seasonNumber;
  final int? episodeNumber;
  final List<String> releaseNames;
  final bool hearingImpaired;
  final bool forced;
  final Map<String, Object?> raw;

  bool get canDownload => downloadUrl.trim().isNotEmpty;

  ProviderSubtitleHit copyWith({
    String? downloadUrl,
    String? packageName,
    SubtitlePackageKind? packageKind,
    Map<String, Object?>? raw,
  }) {
    return ProviderSubtitleHit(
      id: id,
      source: source,
      providerLabel: providerLabel,
      title: title,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      packageName: packageName ?? this.packageName,
      packageKind: packageKind ?? this.packageKind,
      detailUrl: detailUrl,
      version: version,
      formatLabel: formatLabel,
      languageLabel: languageLabel,
      sourceLabel: sourceLabel,
      publishDateLabel: publishDateLabel,
      ratingLabel: ratingLabel,
      downloadCount: downloadCount,
      imdbId: imdbId,
      tmdbId: tmdbId,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      releaseNames: releaseNames,
      hearingImpaired: hearingImpaired,
      forced: forced,
      raw: raw ?? this.raw,
    );
  }

  SubtitleSearchResult toSearchResult() {
    return SubtitleSearchResult(
      id: id,
      source: source,
      providerLabel: providerLabel,
      title: title,
      version: version,
      formatLabel: formatLabel,
      languageLabel: languageLabel,
      sourceLabel: sourceLabel,
      publishDateLabel: publishDateLabel,
      downloadCount: downloadCount,
      ratingLabel: ratingLabel,
      downloadUrl: downloadUrl,
      detailUrl: detailUrl,
      packageName: packageName,
      packageKind: packageKind,
    );
  }
}

class ValidatedSubtitleCandidate {
  const ValidatedSubtitleCandidate({
    required this.hit,
    required this.status,
    this.cachedPath = '',
    this.subtitleFilePath,
    this.displayName = '',
    this.failureReason = '',
    this.detectedFiles = const [],
  });

  final ProviderSubtitleHit hit;
  final SubtitleValidationStatus status;
  final String cachedPath;
  final String? subtitleFilePath;
  final String displayName;
  final String failureReason;
  final List<String> detectedFiles;

  bool get canApply =>
      status == SubtitleValidationStatus.validated &&
      (subtitleFilePath ?? '').trim().isNotEmpty;

  SubtitleSearchResult toSearchResult() => hit.toSearchResult();

  SubtitleDownloadResult toDownloadResult() {
    return SubtitleDownloadResult(
      cachedPath: cachedPath,
      displayName: displayName,
      subtitleFilePath: subtitleFilePath,
    );
  }
}
