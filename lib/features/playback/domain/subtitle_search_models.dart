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
    this.applyMode = SubtitleSearchApplyMode.downloadAndApply,
    this.standalone = false,
  });

  final String query;
  final String title;
  final SubtitleSearchApplyMode applyMode;
  final bool standalone;

  Map<String, String> toQueryParameters() {
    return {
      'q': query,
      if (title.trim().isNotEmpty) 'title': title.trim(),
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
}
