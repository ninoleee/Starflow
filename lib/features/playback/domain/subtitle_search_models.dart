import 'package:path/path.dart' as p;
import 'package:starflow/features/playback/domain/playback_models.dart';

enum SubtitleSearchApplyMode {
  downloadAndApply,
  downloadOnly;

  static SubtitleSearchApplyMode fromName(String raw) {
    return switch (raw.trim()) {
      'downloadOnly' => SubtitleSearchApplyMode.downloadOnly,
      _ => SubtitleSearchApplyMode.downloadAndApply,
    };
  }
}

class SubtitleSearchRequest {
  const SubtitleSearchRequest({
    required this.query,
    this.title = '',
    this.originalTitle = '',
    this.initialInput = '',
    this.year,
    this.imdbId = '',
    this.tmdbId = '',
    this.seasonNumber,
    this.episodeNumber,
    this.filePath = '',
    this.applyMode = SubtitleSearchApplyMode.downloadAndApply,
    this.standalone = false,
  });

  final String query;
  final String title;
  final String originalTitle;
  final String initialInput;
  final int? year;
  final String imdbId;
  final String tmdbId;
  final int? seasonNumber;
  final int? episodeNumber;
  final String filePath;
  final SubtitleSearchApplyMode applyMode;
  final bool standalone;

  Map<String, String> toQueryParameters() {
    return {
      'q': query,
      if (title.trim().isNotEmpty) 'title': title.trim(),
      if (originalTitle.trim().isNotEmpty)
        'originalTitle': originalTitle.trim(),
      if (initialInput.trim().isNotEmpty) 'input': initialInput.trim(),
      if ((year ?? 0) > 0) 'year': '${year!}',
      if (imdbId.trim().isNotEmpty) 'imdbId': imdbId.trim(),
      if (tmdbId.trim().isNotEmpty) 'tmdbId': tmdbId.trim(),
      if (seasonNumber != null) 'season': '$seasonNumber',
      if (episodeNumber != null) 'episode': '$episodeNumber',
      if (filePath.trim().isNotEmpty) 'path': filePath.trim(),
      'mode': applyMode.name,
      if (standalone) 'standalone': '1',
    };
  }

  factory SubtitleSearchRequest.fromQueryParameters(
    Map<String, String> queryParameters,
  ) {
    return SubtitleSearchRequest(
      query: queryParameters['q']?.trim() ?? '',
      title: queryParameters['title']?.trim() ?? '',
      originalTitle: queryParameters['originalTitle']?.trim() ?? '',
      initialInput: queryParameters['input']?.trim() ?? '',
      year: int.tryParse(queryParameters['year']?.trim() ?? ''),
      imdbId: queryParameters['imdbId']?.trim() ?? '',
      tmdbId: queryParameters['tmdbId']?.trim() ?? '',
      seasonNumber: int.tryParse(queryParameters['season']?.trim() ?? ''),
      episodeNumber: int.tryParse(queryParameters['episode']?.trim() ?? ''),
      filePath: queryParameters['path']?.trim() ?? '',
      applyMode: SubtitleSearchApplyMode.fromName(
        queryParameters['mode'] ?? '',
      ),
      standalone: queryParameters['standalone'] == '1',
    );
  }

  String toLocation() {
    return Uri(
      path: '/subtitle-search',
      queryParameters: toQueryParameters(),
    ).toString();
  }
}

enum OnlineSubtitleSource {
  assrt,
  opensubtitles,
  subdl;
}

extension OnlineSubtitleSourceX on OnlineSubtitleSource {
  String get label {
    return switch (this) {
      OnlineSubtitleSource.assrt => 'ASSRT',
      OnlineSubtitleSource.opensubtitles => 'OpenSubtitles',
      OnlineSubtitleSource.subdl => 'SubDL',
    };
  }

  String get description {
    return switch (this) {
      OnlineSubtitleSource.assrt => 'ASSRT 官方 API 字幕源，需要在设置页填写 Token。',
      OnlineSubtitleSource.opensubtitles => 'OpenSubtitles.com 官方 API 字幕源。',
      OnlineSubtitleSource.subdl => 'SubDL 官方 API 字幕源。',
    };
  }

  static OnlineSubtitleSource fromName(String raw) {
    return switch (raw.trim()) {
      'assrt' => OnlineSubtitleSource.assrt,
      'opensubtitles' => OnlineSubtitleSource.opensubtitles,
      'subdl' => OnlineSubtitleSource.subdl,
      _ => OnlineSubtitleSource.assrt,
    };
  }
}

enum SubtitlePackageKind {
  subtitleFile,
  zipArchive,
  rarArchive,
  unsupported;

  String get label => switch (this) {
        SubtitlePackageKind.subtitleFile => '字幕文件',
        SubtitlePackageKind.zipArchive => 'ZIP',
        SubtitlePackageKind.rarArchive => 'RAR',
        SubtitlePackageKind.unsupported => '未知',
      };
}

class SubtitleSearchResult {
  const SubtitleSearchResult({
    required this.id,
    required this.source,
    required this.providerLabel,
    required this.title,
    required this.version,
    required this.formatLabel,
    required this.languageLabel,
    required this.sourceLabel,
    required this.publishDateLabel,
    required this.downloadCount,
    required this.ratingLabel,
    required this.downloadUrl,
    required this.detailUrl,
    required this.packageName,
    required this.packageKind,
    this.seasonNumber,
    this.episodeNumber,
  });

  final String id;
  final OnlineSubtitleSource source;
  final String providerLabel;
  final String title;
  final String version;
  final String formatLabel;
  final String languageLabel;
  final String sourceLabel;
  final String publishDateLabel;
  final int downloadCount;
  final String ratingLabel;
  final String downloadUrl;
  final String detailUrl;
  final String packageName;
  final SubtitlePackageKind packageKind;
  final int? seasonNumber;
  final int? episodeNumber;

  bool get canDownload =>
      downloadUrl.trim().isNotEmpty &&
      packageKind != SubtitlePackageKind.unsupported;

  bool get canAutoLoad =>
      packageKind == SubtitlePackageKind.subtitleFile ||
      packageKind == SubtitlePackageKind.zipArchive;

  String get summaryLine {
    final parts = <String>[
      if (languageLabel.trim().isNotEmpty) languageLabel.trim(),
      if (formatLabel.trim().isNotEmpty) formatLabel.trim(),
      if (sourceLabel.trim().isNotEmpty) sourceLabel.trim(),
      if (ratingLabel.trim().isNotEmpty) ratingLabel.trim(),
      if (downloadCount > 0) '下载 $downloadCount',
      packageKind.label,
    ];
    return parts.join(' · ');
  }

  String get detailLine {
    final parts = <String>[
      if (version.trim().isNotEmpty) version.trim(),
      if (publishDateLabel.trim().isNotEmpty) publishDateLabel.trim(),
    ];
    return parts.join(' · ');
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'source': source.name,
      'providerLabel': providerLabel,
      'title': title,
      'version': version,
      'formatLabel': formatLabel,
      'languageLabel': languageLabel,
      'sourceLabel': sourceLabel,
      'publishDateLabel': publishDateLabel,
      'downloadCount': downloadCount,
      'ratingLabel': ratingLabel,
      'downloadUrl': downloadUrl,
      'detailUrl': detailUrl,
      'packageName': packageName,
      'packageKind': packageKind.name,
      'seasonNumber': seasonNumber,
      'episodeNumber': episodeNumber,
    };
  }

  factory SubtitleSearchResult.fromJson(Map<String, dynamic> json) {
    return SubtitleSearchResult(
      id: json['id'] as String? ?? '',
      source: OnlineSubtitleSourceX.fromName(json['source'] as String? ?? ''),
      providerLabel: json['providerLabel'] as String? ?? '',
      title: json['title'] as String? ?? '',
      version: json['version'] as String? ?? '',
      formatLabel: json['formatLabel'] as String? ?? '',
      languageLabel: json['languageLabel'] as String? ?? '',
      sourceLabel: json['sourceLabel'] as String? ?? '',
      publishDateLabel: json['publishDateLabel'] as String? ?? '',
      downloadCount: (json['downloadCount'] as num?)?.toInt() ?? 0,
      ratingLabel: json['ratingLabel'] as String? ?? '',
      downloadUrl: json['downloadUrl'] as String? ?? '',
      detailUrl: json['detailUrl'] as String? ?? '',
      packageName: json['packageName'] as String? ?? '',
      packageKind: switch (json['packageKind'] as String? ?? '') {
        'subtitleFile' => SubtitlePackageKind.subtitleFile,
        'zipArchive' => SubtitlePackageKind.zipArchive,
        'rarArchive' => SubtitlePackageKind.rarArchive,
        _ => SubtitlePackageKind.unsupported,
      },
      seasonNumber: (json['seasonNumber'] as num?)?.toInt(),
      episodeNumber: (json['episodeNumber'] as num?)?.toInt(),
    );
  }
}

class SubtitleDownloadResult {
  const SubtitleDownloadResult({
    required this.cachedPath,
    required this.displayName,
    this.subtitleFilePath,
  });

  final String cachedPath;
  final String displayName;
  final String? subtitleFilePath;
}

class SubtitleSearchSelection {
  const SubtitleSearchSelection({
    required this.cachedPath,
    required this.displayName,
    this.subtitleFilePath,
  });

  final String cachedPath;
  final String displayName;
  final String? subtitleFilePath;

  bool get canApply => (subtitleFilePath ?? '').trim().isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'cachedPath': cachedPath,
      'displayName': displayName,
      'subtitleFilePath': subtitleFilePath,
    };
  }

  factory SubtitleSearchSelection.fromJson(Map<String, dynamic> json) {
    final subtitleFilePath = (json['subtitleFilePath'] as String?)?.trim();
    return SubtitleSearchSelection(
      cachedPath: json['cachedPath'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      subtitleFilePath: subtitleFilePath == null || subtitleFilePath.isEmpty
          ? null
          : subtitleFilePath,
    );
  }
}

class CachedSubtitleSearchOption {
  const CachedSubtitleSearchOption({
    required this.result,
    this.selection,
  });

  final SubtitleSearchResult result;
  final SubtitleSearchSelection? selection;

  CachedSubtitleSearchOption copyWith({
    SubtitleSearchResult? result,
    SubtitleSearchSelection? selection,
    bool clearSelection = false,
  }) {
    return CachedSubtitleSearchOption(
      result: result ?? this.result,
      selection: clearSelection ? null : (selection ?? this.selection),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'result': result.toJson(),
      'selection': selection?.toJson(),
    };
  }

  factory CachedSubtitleSearchOption.fromJson(Map<String, dynamic> json) {
    return CachedSubtitleSearchOption(
      result: SubtitleSearchResult.fromJson(
        Map<String, dynamic>.from((json['result'] as Map?) ?? const {}),
      ),
      selection: (json['selection'] as Map?) == null
          ? null
          : SubtitleSearchSelection.fromJson(
              Map<String, dynamic>.from(json['selection'] as Map),
            ),
    );
  }
}

String buildSubtitleSearchQuery(PlaybackTarget target) {
  final fileNameQuery = buildSubtitleSearchFileName(target);
  if (fileNameQuery.isNotEmpty) {
    return _appendSubtitleSearchEpisodeTokenIfMissing(fileNameQuery, target);
  }
  final baseTitle = target.seriesTitle.trim().isNotEmpty
      ? target.seriesTitle.trim()
      : target.title.trim();
  final parts = <String>[
    if (baseTitle.isNotEmpty) baseTitle,
    if (target.seasonNumber != null && target.episodeNumber != null)
      'S${target.seasonNumber!.toString().padLeft(2, '0')}E${target.episodeNumber!.toString().padLeft(2, '0')}',
    if (!target.isEpisode && target.year > 0) '${target.year}',
  ];
  return parts.join(' ').trim();
}

String buildSubtitleSearchInitialInput(PlaybackTarget target) {
  final fileNameQuery = buildSubtitleSearchFileName(target);
  if (fileNameQuery.isNotEmpty) {
    return _appendSubtitleSearchEpisodeTokenIfMissing(fileNameQuery, target);
  }
  final seriesTitle = target.resolvedSeriesTitle.trim();
  if (seriesTitle.isNotEmpty) {
    return seriesTitle;
  }
  final title = target.title.trim();
  if (title.isNotEmpty) {
    return title;
  }
  return buildSubtitleSearchQuery(target);
}

String buildSubtitleSearchFileName(PlaybackTarget target) {
  final candidates = [
    cleanSubtitleSearchFileName(target.actualAddress),
    cleanSubtitleSearchFileName(target.streamUrl),
  ];
  for (final candidate in candidates) {
    if (candidate.isNotEmpty) {
      return candidate;
    }
  }
  return '';
}

String cleanSubtitleSearchFileName(String rawPath) {
  final normalized = rawPath.trim();
  if (normalized.isEmpty) {
    return '';
  }
  final uri = Uri.tryParse(normalized);
  final sourcePath =
      uri != null && uri.path.trim().isNotEmpty ? uri.path.trim() : normalized;
  var fileName = p.basename(sourcePath).trim();
  try {
    fileName = Uri.decodeComponent(fileName);
  } catch (_) {
    // Keep the original basename when the path is not valid URI encoding.
  }
  if (fileName.isEmpty) {
    return '';
  }
  fileName = _stripSubtitleSearchKnownExtensions(fileName);
  fileName = _stripSubtitleSearchFormatSuffix(fileName);
  return fileName
      .replaceAll(RegExp(r'[._]+'), ' ')
      .replaceAll(RegExp(r'[\[\]\(\)]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _appendSubtitleSearchEpisodeTokenIfMissing(
  String query,
  PlaybackTarget target,
) {
  final normalizedQuery = query.trim();
  final seasonNumber = target.seasonNumber;
  final episodeNumber = target.episodeNumber;
  if (normalizedQuery.isEmpty ||
      seasonNumber == null ||
      seasonNumber <= 0 ||
      episodeNumber == null ||
      episodeNumber <= 0 ||
      _containsSubtitleSearchEpisodeMarker(normalizedQuery)) {
    return normalizedQuery;
  }
  final episodeToken =
      'S${seasonNumber.toString().padLeft(2, '0')}E${episodeNumber.toString().padLeft(2, '0')}';
  return '$normalizedQuery $episodeToken'.trim();
}

bool _containsSubtitleSearchEpisodeMarker(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return false;
  }
  return RegExp(
    r'\bS\d{1,2}E\d{1,3}\b|\bE\d{1,3}\b|第\s*\d+\s*(季|集|期)\b',
    caseSensitive: false,
  ).hasMatch(normalized);
}

String _stripSubtitleSearchKnownExtensions(String fileName) {
  var current = fileName.trim();
  final pattern = RegExp(
    r'\.(?:\(|\[)?(?:strm|mkv|mp4|avi|mov|wmv|flv|webm|ts|m2ts|iso|rmvb|m4v|srt|ass|ssa|vtt|zip|rar)(?:\)|\])?$',
    caseSensitive: false,
  );
  while (true) {
    final next = current.replaceFirst(pattern, '').trim();
    if (next == current) {
      return current;
    }
    current = next;
  }
}

String _stripSubtitleSearchFormatSuffix(String fileName) {
  final stripped = fileName
      .replaceFirst(
        RegExp(
          r'(?:[ ._\-&]+(?:\d{3,4}p|web(?:[ ._-]?dl)?|webrip|bluray|blu[ ._-]?ray|bdrip|brrip|remux|hdrip|hdtv|uhd|hq|hdr10plus|hdr10|hdr|dv|dovi|dolby[ ._-]?vision|hevc|h265|x265|h264|x264|av1|10bit|8bit|aac(?:\d(?:\.\d)?)?|ac3(?:\d(?:\.\d)?)?|eac3(?:\d(?:\.\d)?)?|ddp?(?:\d(?:\.\d)?)?|truehd(?:\d(?:\.\d)?)?|atmos|dts(?:\d(?:\.\d)?)?|dts[ ._-]?hd|flac|proper|repack|extended|multi|dubbed|subbed|chs|cht|eng|简繁|简中|繁中|中字|内封|外挂))+[ ._\-&]*$',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
  return stripped.isNotEmpty ? stripped : fileName.trim();
}

int scoreSubtitleEpisodeMatch(
  String fileName, {
  int? seasonNumber,
  int? episodeNumber,
}) {
  if (seasonNumber == null ||
      seasonNumber <= 0 ||
      episodeNumber == null ||
      episodeNumber <= 0) {
    return 0;
  }

  var score = 0;
  if (_containsExactSeasonEpisodeMarker(
    fileName,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
  )) {
    score += 420;
  } else if (_containsAnySeasonEpisodeMarker(fileName)) {
    score -= 260;
  }

  if (_containsExactEpisodeOnlyMarker(fileName, episodeNumber)) {
    score += 160;
  } else if (_containsAnyEpisodeOnlyMarker(fileName)) {
    score -= 120;
  }

  if (_containsExactSeasonOnlyMarker(fileName, seasonNumber)) {
    score += 48;
  }
  return score;
}

bool _containsExactSeasonEpisodeMarker(
  String fileName, {
  required int seasonNumber,
  required int episodeNumber,
}) {
  final patterns = [
    RegExp(
      's0?$seasonNumber'
      'e0?$episodeNumber'
      r'\b',
      caseSensitive: false,
    ),
    RegExp(
      '\\b0?$seasonNumber'
      'x0?$episodeNumber'
      r'\b',
      caseSensitive: false,
    ),
    RegExp(
      '第\\s*0?$seasonNumber\\s*季\\s*第\\s*0?$episodeNumber\\s*[集话期]',
      caseSensitive: false,
    ),
  ];
  return patterns.any((pattern) => pattern.hasMatch(fileName));
}

bool _containsAnySeasonEpisodeMarker(String fileName) {
  return RegExp(r's\d{1,2}e\d{1,3}\b', caseSensitive: false)
          .hasMatch(fileName) ||
      RegExp(r'\b\d{1,2}x\d{1,3}\b', caseSensitive: false).hasMatch(fileName) ||
      RegExp(r'第\s*\d+\s*季\s*第\s*\d+\s*[集话期]', caseSensitive: false)
          .hasMatch(fileName);
}

bool _containsExactEpisodeOnlyMarker(String fileName, int episodeNumber) {
  return RegExp(
        r'\be0?' '$episodeNumber' r'\b',
        caseSensitive: false,
      ).hasMatch(fileName) ||
      RegExp(
        '第\\s*0?$episodeNumber\\s*[集话期]',
        caseSensitive: false,
      ).hasMatch(fileName);
}

bool _containsAnyEpisodeOnlyMarker(String fileName) {
  return RegExp(r'\be\d{1,3}\b', caseSensitive: false).hasMatch(fileName) ||
      RegExp(r'第\s*\d+\s*[集话期]', caseSensitive: false).hasMatch(fileName);
}

bool _containsExactSeasonOnlyMarker(String fileName, int seasonNumber) {
  return RegExp(
        r'\bs0?' '$seasonNumber' r'\b',
        caseSensitive: false,
      ).hasMatch(fileName) ||
      RegExp(
        '第\\s*0?$seasonNumber\\s*季',
        caseSensitive: false,
      ).hasMatch(fileName);
}
