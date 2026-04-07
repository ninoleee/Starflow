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
    this.initialInput = '',
    this.applyMode = SubtitleSearchApplyMode.downloadAndApply,
    this.standalone = false,
  });

  final String query;
  final String title;
  final String initialInput;
  final SubtitleSearchApplyMode applyMode;
  final bool standalone;

  Map<String, String> toQueryParameters() {
    return {
      'q': query,
      if (title.trim().isNotEmpty) 'title': title.trim(),
      if (initialInput.trim().isNotEmpty) 'input': initialInput.trim(),
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
      initialInput: queryParameters['input']?.trim() ?? '',
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
  subhd,
  yify;
}

extension OnlineSubtitleSourceX on OnlineSubtitleSource {
  String get label {
    return switch (this) {
      OnlineSubtitleSource.assrt => 'ASSRT',
      OnlineSubtitleSource.subhd => 'SubHD',
      OnlineSubtitleSource.yify => 'YIFY',
    };
  }

  String get description {
    return switch (this) {
      OnlineSubtitleSource.assrt => '国内常用字幕站，适合电影和剧集常规搜索。',
      OnlineSubtitleSource.subhd => '国内常用字幕社区，当前支持应用内搜索结果浏览。',
      OnlineSubtitleSource.yify => '海外电影字幕站，支持电影搜索与 ZIP 字幕下载。',
    };
  }

  static OnlineSubtitleSource fromName(String raw) {
    return switch (raw.trim()) {
      'assrt' => OnlineSubtitleSource.assrt,
      'subhd' => OnlineSubtitleSource.subhd,
      'yify' => OnlineSubtitleSource.yify,
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
