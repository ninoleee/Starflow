import 'package:starflow/core/utils/webdav_trace.dart';
import 'package:starflow/features/library/data/season_folder_label_parser.dart';
import 'package:starflow/features/library/domain/media_naming.dart';

bool looksLikeReleaseTokenLabel(String input) {
  return NasMediaRecognizer.matchesReleaseTokenLabel(input);
}

String compactNasWrapperDescriptorLabel(String input) {
  return NasMediaRecognizer.compactWrapperDescriptorLabel(input);
}

bool looksLikeWrapperFolderLabel(String input) {
  return NasMediaRecognizer.matchesWrapperFolderLabel(input);
}

class NasMediaRecognition {
  const NasMediaRecognition({
    required this.title,
    required this.searchQuery,
    required this.originalFileName,
    required this.parentTitle,
    required this.year,
    required this.itemType,
    required this.preferSeries,
    this.imdbId = '',
    this.seasonNumber,
    this.episodeNumber,
    this.episodePart = '',
  });

  final String title;
  final String searchQuery;
  final String originalFileName;
  final String parentTitle;
  final int year;
  final String itemType;
  final bool preferSeries;
  final String imdbId;
  final int? seasonNumber;
  final int? episodeNumber;
  final String episodePart;
}

class NasMediaRecognizer {
  const NasMediaRecognizer._();

  // Episode/issue markers for variety-style naming.
  static const List<String> _episodeUnitKeywords = ['集', '话', '期'];
  static const List<String> _episodePartUpperKeywords = [
    '上半场',
    '上半',
    '上篇',
    '上集',
    '上部',
    '上',
    'part 1',
    'part 01',
  ];
  static const List<String> _episodePartMiddleKeywords = [
    '中篇',
    '中集',
    '中部',
    '中',
    'part 3',
    'part 03',
  ];
  static const List<String> _episodePartLowerKeywords = [
    '下半场',
    '下半',
    '下篇',
    '下集',
    '下部',
    '下',
    'part 2',
    'part 02',
  ];

  static const List<String> _cleanTitleOnlyDescriptorKeywords =
      MediaNaming.cleanTitleOnlyDescriptorKeywords;

  // Reusable combined descriptor groups for different matcher contexts.
  static const List<String> _sharedDescriptorKeywords =
      MediaNaming.sharedDescriptorKeywords;
  static const List<String> _wrapperOnlyDescriptorKeywords =
      MediaNaming.wrapperOnlyDescriptorKeywords;

  // Technical/release tokens that usually indicate wrappers rather than title.
  static const List<String> _sharedTechnicalTokenPatterns =
      MediaNaming.sharedTechnicalTokenPatterns;
  static const List<String> _releaseOnlyTokenPatterns = [
    r's\d{1,2}',
    r'season ?\d{1,2}',
  ];
  static const List<String> _wrapperOnlyTokenPatterns = [r'web'];

  static const Set<String> _genericLibraryFolders = {
    'movie',
    'movies',
    'film',
    'films',
    'cinema',
    'video',
    'videos',
    'tv',
    'show',
    'shows',
    'series',
    'anime',
    'animation',
    '纪录片',
    '电影',
    '影片',
    '剧集',
    '电视剧',
    '综艺',
    '动画',
    '动漫',
  };

  static final RegExp _releaseTokenLabelPattern = RegExp(
    '^(?:${MediaNaming.buildAlternationPattern([
          ..._releaseOnlyTokenPatterns,
          ..._sharedTechnicalTokenPatterns,
          ...MediaNaming.escapePatternKeywords(_sharedDescriptorKeywords),
        ])})\$',
    caseSensitive: false,
  );
  static final RegExp _wrapperDescriptorPattern = RegExp(
    '^(?:${MediaNaming.buildAlternationPattern([
          ..._sharedTechnicalTokenPatterns,
          ..._wrapperOnlyTokenPatterns,
          ...MediaNaming.escapePatternKeywords(_sharedDescriptorKeywords),
          ...MediaNaming.escapePatternKeywords(_wrapperOnlyDescriptorKeywords),
        ])})+\$',
    caseSensitive: false,
  );
  static final RegExp _cleanTitleReleaseTokenPattern = RegExp(
    r'\b('
    '${MediaNaming.buildAlternationPattern([
          ..._sharedTechnicalTokenPatterns,
          ...MediaNaming.escapePatternKeywords([
            ..._sharedDescriptorKeywords,
            ..._cleanTitleOnlyDescriptorKeywords,
          ]),
        ])}'
    r')\b',
    caseSensitive: false,
  );

  static final Map<String, String> _episodePartTokenByKeyword = {
    for (final keyword in _episodePartUpperKeywords)
      _normalizeEpisodePartKeyword(keyword): 'upper',
    for (final keyword in _episodePartMiddleKeywords)
      _normalizeEpisodePartKeyword(keyword): 'middle',
    for (final keyword in _episodePartLowerKeywords)
      _normalizeEpisodePartKeyword(keyword): 'lower',
  };

  static final String _episodeUnitPattern =
      _episodeUnitKeywords.map(RegExp.escape).join();
  static final String _episodePartKeywordPattern =
      MediaNaming.buildAlternationPattern(
    MediaNaming.escapePatternKeywords([
      ..._episodePartUpperKeywords,
      ..._episodePartMiddleKeywords,
      ..._episodePartLowerKeywords,
    ]),
  );
  static final String _chineseEpisodePatternSource =
      '第\\s*0*(\\d{1,4})\\s*[$_episodeUnitPattern]';
  static final String _optionalEpisodePartPatternSource =
      '(?:\\s*[-_.]?\\s*[（(\\[【]?\\s*($_episodePartKeywordPattern)\\s*[）)\\]】]?)?';
  static final RegExp _chineseEpisodePattern = RegExp(
    '$_chineseEpisodePatternSource$_optionalEpisodePartPatternSource',
    caseSensitive: false,
  );
  static final RegExp _chineseEpisodePartPattern = RegExp(
    '第\\s*0*\\d{1,4}\\s*[$_episodeUnitPattern]$_optionalEpisodePartPatternSource',
    caseSensitive: false,
  );
  static final RegExp _stripChineseEpisodeTokenPattern = RegExp(
    '第\\s*\\d{1,3}\\s*[$_episodeUnitPattern]$_optionalEpisodePartPatternSource',
    caseSensitive: false,
  );

  static bool matchesReleaseTokenLabel(String input) {
    final normalized = input.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    return _releaseTokenLabelPattern.hasMatch(normalized);
  }

  static String compactWrapperDescriptorLabel(String input) {
    return MediaNaming.compactKeywordLabel(input);
  }

  static bool matchesWrapperFolderLabel(String input) {
    final compact = compactWrapperDescriptorLabel(input);
    if (compact.isEmpty) {
      return false;
    }
    if (looksLikeSeasonFolderLabel(input)) {
      return false;
    }
    return _wrapperDescriptorPattern.hasMatch(compact);
  }

  static NasMediaRecognition recognize(
    String actualAddress, {
    List<String> seriesTitleFilterKeywords = const [],
    List<String> specialEpisodeKeywords = const [],
  }) {
    final normalizedSeriesTitleFilterKeywords =
        MediaNaming.normalizeKeywords(seriesTitleFilterKeywords);
    final normalizedSpecialEpisodeKeywords =
        MediaNaming.normalizeKeywords(specialEpisodeKeywords);
    final normalizedPath = actualAddress
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final fileName =
        normalizedPath.isEmpty ? actualAddress.trim() : normalizedPath.last;
    final fileBaseName = _stripExtension(fileName);
    final parentRaw = normalizedPath.length >= 2
        ? normalizedPath[normalizedPath.length - 2]
        : '';
    final grandParentRaw = normalizedPath.length >= 3
        ? normalizedPath[normalizedPath.length - 3]
        : '';
    final imdbId = _resolveImdbId([fileBaseName, parentRaw, grandParentRaw]);

    final episodeMatch = _matchEpisode(
      fileBaseName,
      specialEpisodeKeywords: normalizedSpecialEpisodeKeywords,
    );
    final parentSeason = _matchSeason(parentRaw);
    final grandParentSeason = _matchSeason(grandParentRaw);
    final year = _findYear([fileBaseName, parentRaw, grandParentRaw]);

    final cleanedFileTitle = _cleanTitle(
      fileBaseName,
      removeEpisodeTokens: true,
      removeYear: year > 0,
    );
    final cleanedParentTitle = _cleanTitle(parentRaw);
    final cleanedGrandParentTitle = _cleanTitle(grandParentRaw);

    final parentLooksLikeSeasonFolder = _looksLikeSeasonFolder(parentRaw);
    final parentLooksLikeWrapperFolder =
        NasMediaRecognizer.matchesWrapperFolderLabel(parentRaw);
    final grandParentLooksLikeSeasonFolder =
        _looksLikeSeasonFolder(grandParentRaw);
    final inferredParentTitle = parentLooksLikeSeasonFolder
        ? cleanedGrandParentTitle
        : parentLooksLikeWrapperFolder
            ? (grandParentLooksLikeSeasonFolder ? '' : cleanedGrandParentTitle)
            : cleanedParentTitle;

    String title = cleanedFileTitle;
    var resolvedParentTitle = inferredParentTitle.trim();
    String itemType = '';
    var preferSeries = false;
    int? seasonNumber;
    int? episodeNumber;
    var episodePart = '';

    if (episodeMatch != null) {
      itemType = 'episode';
      preferSeries = true;
      seasonNumber =
          episodeMatch.seasonNumber ?? parentSeason ?? grandParentSeason;
      episodeNumber = episodeMatch.episodeNumber;
      episodePart = episodeMatch.episodePart;
      if (resolvedParentTitle.isNotEmpty) {
        title = resolvedParentTitle;
      }
    } else if (_looksLikeSeriesFolder(parentRaw)) {
      final leadingEpisodeNumber = _matchLeadingEpisodeCue(fileBaseName);
      if (leadingEpisodeNumber != null) {
        itemType = 'episode';
        preferSeries = true;
        seasonNumber = parentSeason ?? grandParentSeason;
        episodeNumber = leadingEpisodeNumber;
        if (cleanedParentTitle.trim().isNotEmpty) {
          title = cleanedParentTitle.trim();
        }
      } else {
        preferSeries = true;
      }
    } else if (parentLooksLikeSeasonFolder && resolvedParentTitle.isNotEmpty) {
      title = resolvedParentTitle;
      itemType = 'episode';
      preferSeries = true;
      seasonNumber = parentSeason ?? grandParentSeason;
    } else if (_looksLikeSeriesFolder(parentRaw) &&
        cleanedParentTitle.trim().isNotEmpty) {
      preferSeries = true;
    }

    if (title.trim().isEmpty) {
      title = resolvedParentTitle.isNotEmpty
          ? resolvedParentTitle
          : _cleanTitle(fileBaseName);
    }
    if (title.trim().isEmpty) {
      title = stripEmbeddedExternalIdTags(fileBaseName).trim();
    }
    if (title.trim().isEmpty) {
      title = fileBaseName.trim();
    }

    if (itemType == 'episode' &&
        normalizedSeriesTitleFilterKeywords.isNotEmpty) {
      final stoppedTitle = _resolveStoppedSeriesTitleFromFilteredDirectory(
        pathSegments: normalizedPath,
        fileBaseName: fileBaseName,
        seriesTitleFilterKeywords: normalizedSeriesTitleFilterKeywords,
      );
      if (stoppedTitle != null && stoppedTitle.trim().isNotEmpty) {
        title = stoppedTitle.trim();
        resolvedParentTitle = stoppedTitle.trim();
      }
    }

    final result = NasMediaRecognition(
      title: title.trim(),
      searchQuery: title.trim(),
      originalFileName: fileName.trim(),
      parentTitle: resolvedParentTitle,
      year: year,
      itemType: itemType,
      preferSeries: preferSeries,
      imdbId: imdbId,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      episodePart: episodePart,
    );
    webDavTrace(
      'recognize',
      fields: {
        'path': actualAddress,
        'title': result.title,
        'parentTitle': result.parentTitle,
        'itemType': result.itemType,
        'preferSeries': result.preferSeries,
        'season': result.seasonNumber,
        'episode': result.episodeNumber,
        'episodePart': result.episodePart,
        'imdbId': result.imdbId,
      },
    );
    return result;
  }

  static String resolveEpisodePartToken(
    String input, {
    List<String> specialEpisodeKeywords = const [],
  }) {
    final normalizedSpecialEpisodeKeywords =
        MediaNaming.normalizeKeywords(specialEpisodeKeywords);
    return _extractEpisodePartToken(
      input,
      specialEpisodeKeywords: normalizedSpecialEpisodeKeywords,
    );
  }

  static String _resolveImdbId(List<String> inputs) {
    var imdbId = '';
    for (final input in inputs) {
      if (imdbId.isEmpty) {
        imdbId = _matchImdbId(input);
      }
      if (imdbId.isNotEmpty) {
        break;
      }
    }
    return imdbId;
  }

  static String _matchImdbId(String input) {
    final match = RegExp(
      r'(tt\d{6,10})',
      caseSensitive: false,
    ).firstMatch(input);
    return match == null ? '' : match.group(1)!.toLowerCase();
  }

  static int _findYear(List<String> inputs) {
    for (final input in inputs) {
      for (final match
          in RegExp(r'(?<!\d)(19\d{2}|20\d{2})(?!\d)').allMatches(input)) {
        final year = int.tryParse(match.group(1)!);
        if (year != null && year >= 1900 && year <= 2099) {
          return year;
        }
      }
    }
    return 0;
  }

  static _EpisodeMatch? _matchEpisode(
    String input, {
    List<String> specialEpisodeKeywords = const [],
  }) {
    final normalized = input.trim();
    for (final pattern in const [
      r'(?:^|[ ._\-])s(\d{1,2})[ ._\-]*e(\d{1,3})(?:$|[ ._\-])',
      r'(?:^|[ ._\-])season[ ._\-]?(\d{1,2})[ ._\-]*(?:episode|ep)[ ._\-]?(\d{1,3})(?:$|[ ._\-])',
      r'(?<!\d)e(\d{1,3})(?!\d)',
      r'(?:^|[ ._\-])ep(?:isode)?[ ._\-]?(\d{1,3})(?:$|[ ._\-])',
    ]) {
      final match =
          RegExp(pattern, caseSensitive: false).firstMatch(normalized);
      if (match == null) {
        continue;
      }
      if (pattern.contains('s(') || pattern.contains('season')) {
        return _EpisodeMatch(
          seasonNumber: int.tryParse(match.group(1) ?? ''),
          episodeNumber: int.tryParse(match.group(2) ?? ''),
        );
      }
      return _EpisodeMatch(
        seasonNumber: null,
        episodeNumber: int.tryParse(match.group(1) ?? ''),
      );
    }
    final chineseMatch = _chineseEpisodePattern.firstMatch(normalized);
    if (chineseMatch == null) {
      return null;
    }
    return _EpisodeMatch(
      seasonNumber: null,
      episodeNumber: int.tryParse(chineseMatch.group(1) ?? ''),
      episodePart: _matchesAnySpecialEpisodeKeyword(
        normalized,
        specialEpisodeKeywords: specialEpisodeKeywords,
      )
          ? ''
          : _normalizeEpisodePartToken(chineseMatch.group(2) ?? ''),
    );
  }

  static String _extractEpisodePartToken(
    String input, {
    required List<String> specialEpisodeKeywords,
  }) {
    final normalized = stripEmbeddedExternalIdTags(input).trim();
    if (normalized.isEmpty ||
        _matchesAnySpecialEpisodeKeyword(
          normalized,
          specialEpisodeKeywords: specialEpisodeKeywords,
        )) {
      return '';
    }
    final match = _chineseEpisodePartPattern.firstMatch(normalized);
    return _normalizeEpisodePartToken(match?.group(1) ?? '');
  }

  static String _normalizeEpisodePartToken(String input) {
    final normalized = _normalizeEpisodePartKeyword(input);
    return _episodePartTokenByKeyword[normalized] ?? '';
  }

  static String _normalizeEpisodePartKeyword(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'[\s._\-]+'), '');
  }

  static bool _matchesAnySpecialEpisodeKeyword(
    String input, {
    required List<String> specialEpisodeKeywords,
  }) {
    return MediaNaming.matchesAnyKeyword(
      [input],
      keywords: specialEpisodeKeywords,
    );
  }

  static int? _matchLeadingEpisodeCue(String input) {
    final normalized = input.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final match = RegExp(
      r'^\s*0*(\d{1,3})(?:[ ._\-]+)(.+)$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (match == null) {
      return null;
    }

    final episodeNumber = int.tryParse(match.group(1) ?? '');
    if (episodeNumber == null || episodeNumber <= 0) {
      return null;
    }

    final remainder = (match.group(2) ?? '').trim();
    if (remainder.isEmpty) {
      return episodeNumber;
    }

    final cleanedRemainder = _cleanLeadingEpisodeRemainder(remainder);
    return cleanedRemainder.isEmpty ? episodeNumber : null;
  }

  static int? _matchSeason(String input) {
    final normalized = input.trim();
    for (final pattern in const [
      r'(?:^|[ ._\-])s(\d{1,2})(?:$|[ ._\-])',
      r'season[ ._\-]?(\d{1,2})',
      r'第(\d{1,2})季',
    ]) {
      final match =
          RegExp(pattern, caseSensitive: false).firstMatch(normalized);
      final season = int.tryParse(match?.group(1) ?? '');
      if (season != null && season > 0) {
        return season;
      }
    }
    return null;
  }

  static bool _looksLikeSeasonFolder(String input) {
    final normalized = input.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    return RegExp(r'(^|[ ._\-])(s\d{1,2}|season[ ._\-]?\d{1,2})([ ._\-]|$)',
                caseSensitive: false)
            .hasMatch(input) ||
        RegExp(r'第\d{1,2}季').hasMatch(input);
  }

  static bool _looksLikeSeriesFolder(String input) {
    final normalized = _cleanTitle(input);
    if (normalized.isEmpty) {
      return false;
    }
    if (_genericLibraryFolders.contains(normalized.toLowerCase())) {
      return false;
    }
    return !matchesReleaseTokenLabel(input) &&
        !matchesWrapperFolderLabel(input) &&
        normalized.length >= 2;
  }

  static String _cleanTitle(
    String input, {
    bool removeEpisodeTokens = false,
    bool removeYear = false,
  }) {
    var value = stripEmbeddedExternalIdTags(input).trim();
    if (value.isEmpty) {
      return '';
    }

    value = value.replaceAll(RegExp(r'[_\.]+'), ' ');
    value = value.replaceAll(RegExp(r'[【\[\(].*?[】\]\)]'), ' ');
    if (removeEpisodeTokens) {
      value = value
          .replaceAll(
              RegExp(r'\bs\d{1,2}[ ._\-]*e\d{1,3}\b', caseSensitive: false),
              ' ')
          .replaceAll(
            RegExp(
              r'\bseason[ ._\-]?\d{1,2}[ ._\-]*(episode|ep)[ ._\-]?\d{1,3}\b',
              caseSensitive: false,
            ),
            ' ',
          )
          .replaceAll(
            RegExp(r'\bep(?:isode)?[ ._\-]?\d{1,3}\b', caseSensitive: false),
            ' ',
          )
          .replaceAll(_stripChineseEpisodeTokenPattern, ' ');
    }
    if (removeYear) {
      value = value.replaceAll(RegExp(r'(?<!\d)(19\d{2}|20\d{2})(?!\d)'), ' ');
    }

    value = value.replaceAll(_cleanTitleReleaseTokenPattern, ' ');
    for (final token in [
      ..._sharedDescriptorKeywords,
      ..._cleanTitleOnlyDescriptorKeywords
    ]) {
      value = value.replaceAll(token, ' ');
    }
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    value = value.replaceAll(RegExp(r'^[\-\._\s]+|[\-\._\s]+$'), '').trim();
    if (matchesReleaseTokenLabel(value)) {
      return '';
    }
    return value;
  }

  static String? _resolveStoppedSeriesTitleFromFilteredDirectory({
    required List<String> pathSegments,
    required String fileBaseName,
    required List<String> seriesTitleFilterKeywords,
  }) {
    if (seriesTitleFilterKeywords.isEmpty || pathSegments.length < 2) {
      return null;
    }
    var lastInferredTitle = '';
    var hitFilteredDirectory = false;
    for (var index = pathSegments.length - 2; index >= 0; index--) {
      final rawSegment = pathSegments[index].trim();
      if (rawSegment.isEmpty) {
        continue;
      }
      final cleanedSegment = _cleanTitle(rawSegment);
      final parentMatchesFilter = index > 0 &&
          _matchesSeriesTitleFilter(
            pathSegments[index - 1],
            cleanedSegment: _cleanTitle(pathSegments[index - 1]),
            seriesTitleFilterKeywords: seriesTitleFilterKeywords,
          );
      if (_matchesSeriesTitleFilter(
        rawSegment,
        cleanedSegment: cleanedSegment,
        seriesTitleFilterKeywords: seriesTitleFilterKeywords,
      )) {
        hitFilteredDirectory = true;
        break;
      }
      if ((_looksLikeSeasonFolder(rawSegment) &&
              !_canUseSeasonDirectoryAsSeriesTitle(
                rawSegment,
                parentMatchesFilter: parentMatchesFilter,
              )) ||
          matchesWrapperFolderLabel(rawSegment)) {
        continue;
      }
      if (cleanedSegment.isEmpty) {
        continue;
      }
      if (lastInferredTitle.isEmpty) {
        lastInferredTitle = cleanedSegment;
      }
    }
    if (lastInferredTitle.isEmpty) {
      lastInferredTitle = _fallbackSeriesTitleFromFile(fileBaseName);
    }
    if (!hitFilteredDirectory || lastInferredTitle.trim().isEmpty) {
      return null;
    }
    return lastInferredTitle.trim();
  }

  static bool _canUseSeasonDirectoryAsSeriesTitle(
    String rawSegment, {
    required bool parentMatchesFilter,
  }) {
    if (!parentMatchesFilter || !_looksLikeSeasonFolder(rawSegment)) {
      return false;
    }
    return !looksLikeStrictSeasonFolderLabel(rawSegment);
  }

  static String _fallbackSeriesTitleFromFile(String fileBaseName) {
    final cleanedFileTitle = _cleanTitle(
      fileBaseName,
      removeEpisodeTokens: true,
    );
    if (cleanedFileTitle.isNotEmpty) {
      return cleanedFileTitle;
    }
    final cleanedTitle = _cleanTitle(fileBaseName);
    if (cleanedTitle.isNotEmpty) {
      return cleanedTitle;
    }
    final stripped = stripEmbeddedExternalIdTags(fileBaseName).trim();
    if (stripped.isNotEmpty) {
      return stripped;
    }
    return fileBaseName.trim();
  }

  static bool _matchesSeriesTitleFilter(
    String rawValue, {
    required String cleanedSegment,
    required List<String> seriesTitleFilterKeywords,
  }) {
    if (seriesTitleFilterKeywords.isEmpty) {
      return false;
    }
    final haystacks = <String>{
      rawValue.trim().toLowerCase(),
      cleanedSegment.trim().toLowerCase(),
      compactWrapperDescriptorLabel(rawValue),
    }..removeWhere((value) => value.isEmpty);
    return seriesTitleFilterKeywords.any(
      (keyword) => haystacks.any((value) => value.contains(keyword)),
    );
  }

  static String _cleanLeadingEpisodeRemainder(String input) {
    var value = stripEmbeddedExternalIdTags(input).trim();
    if (value.isEmpty) {
      return '';
    }

    value = value.replaceAll(RegExp(r'[【\[\(].*?[】\]\)]'), ' ');
    value = value.replaceAll(RegExp(r'[_\.]+'), ' ');
    value = value.replaceAll(RegExp(r'[&+/]+'), ' ');
    final tokens = value
        .split(RegExp(r'[\s\-_]+'))
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) {
      return '';
    }

    const allowedFileTokens = <String>{
      'mp4',
      'mkv',
      'avi',
      'mov',
      'ts',
      'm2ts',
    };

    for (final token in tokens) {
      final normalizedToken = token.toLowerCase();
      if (allowedFileTokens.contains(normalizedToken) ||
          matchesReleaseTokenLabel(normalizedToken) ||
          matchesWrapperFolderLabel(token)) {
        continue;
      }
      if (RegExp(r'^\d{3,4}p$', caseSensitive: false).hasMatch(token)) {
        continue;
      }
      return token;
    }
    return '';
  }

  static String _stripExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) {
      return fileName;
    }
    return fileName.substring(0, dotIndex);
  }
}

class _EpisodeMatch {
  const _EpisodeMatch({
    required this.seasonNumber,
    required this.episodeNumber,
    this.episodePart = '',
  });

  final int? seasonNumber;
  final int? episodeNumber;
  final String episodePart;
}
