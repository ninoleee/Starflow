import 'package:starflow/core/utils/webdav_trace.dart';
import 'package:starflow/features/library/data/season_folder_label_parser.dart';

String stripEmbeddedExternalIdTags(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return trimmed.replaceAll(
    RegExp(
      r'\{\s*(?:tmdb(?:id)?|tmbid|tvdb(?:id)?|imdb(?:id)?|douban(?:id)?)\s*[-:=]?\s*[\w.-]+\s*\}',
      caseSensitive: false,
    ),
    ' ',
  );
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
}

class NasMediaRecognizer {
  const NasMediaRecognizer._();

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

  static final RegExp _wrapperDescriptorPattern = RegExp(
    r'^(?:'
    r'分段版|特效中字|特效字幕|字幕版|中字|中文字幕|中英字幕|双语字幕|双语|简繁字幕|内封中字|外挂字幕|'
    r'国语版|粤语版|国粤版|国粤双语|国语|粤语|原声|'
    r'会员版|纯享版|导演剪辑版|导演版|加长版|未删减版|完整版|删减版|重剪版|重制版|珍藏版|纪念版|'
    r'特典|花絮|幕后|加更|彩蛋|番外|特别篇|剧场版|'
    r'杜比视界|杜比全景声|高码率|原画|蓝光原盘|原盘|'
    r'remux|bluray|bdrip|brrip|webrip|webdl|web|'
    r'2160p|1080p|720p|480p|4k|8k|uhd|hdr10\+|hdr10|hdr|dovi|dv|dolbyvision|'
    r'x264|x265|h264|h265|hevc|avc|aac|ac3|eac3|ddp(?:51|71)?|dts|truehd|atmos|'
    r'10bit|8bit|nf|amzn|dsnp|max|hmax|complete|proper|repack|multi'
    r')+$',
    caseSensitive: false,
  );

  static NasMediaRecognition recognize(
    String actualAddress, {
    List<String> seriesTitleFilterKeywords = const [],
  }) {
    final normalizedSeriesTitleFilterKeywords = seriesTitleFilterKeywords
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
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

    final episodeMatch = _matchEpisode(fileBaseName);
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
    final parentLooksLikeWrapperFolder = _looksLikeWrapperFolder(parentRaw);
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

    if (episodeMatch != null) {
      itemType = 'episode';
      preferSeries = true;
      seasonNumber =
          episodeMatch.seasonNumber ?? parentSeason ?? grandParentSeason;
      episodeNumber = episodeMatch.episodeNumber;
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
        'imdbId': result.imdbId,
      },
    );
    return result;
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

  static _EpisodeMatch? _matchEpisode(String input) {
    final normalized = input.trim();
    for (final pattern in const [
      r'(?:^|[ ._\-])s(\d{1,2})[ ._\-]*e(\d{1,3})(?:$|[ ._\-])',
      r'(?:^|[ ._\-])season[ ._\-]?(\d{1,2})[ ._\-]*(?:episode|ep)[ ._\-]?(\d{1,3})(?:$|[ ._\-])',
      r'(?<!\d)e(\d{1,3})(?!\d)',
      r'(?:^|[ ._\-])ep(?:isode)?[ ._\-]?(\d{1,3})(?:$|[ ._\-])',
      r'第(\d{1,4})[集话期]',
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
    return null;
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
    return !_looksLikeReleaseToken(input) &&
        !_looksLikeWrapperFolder(input) &&
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
          .replaceAll(RegExp(r'第\d{1,3}[集话]'), ' ');
    }
    if (removeYear) {
      value = value.replaceAll(RegExp(r'(?<!\d)(19\d{2}|20\d{2})(?!\d)'), ' ');
    }

    value = value.replaceAll(
      RegExp(
        r'\b('
        r'2160p|1080p|720p|480p|4k|8k|uhd|hdr10\+|hdr|dovi|dv|dolby[ ._\-]?vision|'
        r'web[ ._\-]?dl|webrip|web[ ._\-]?rip|blu[ ._\-]?ray|bdrip|brrip|remux|'
        r'x264|x265|h264|h265|hevc|avc|aac|ac3|eac3|ddp|dts|truehd|atmos|10bit|8bit|'
        r'proper|repack|complete|multi|nf|amzn|dsnp|max|hmax|'
        r'中字|双语|国粤|简繁|内封|外挂|中英字幕'
        r')\b',
        caseSensitive: false,
      ),
      ' ',
    );
    for (final token in const [
      '分段版',
      '特效中字',
      '特效字幕',
      '会员版',
      '纯享版',
      '导演剪辑版',
      '导演版',
      '加长版',
      '未删减版',
      '完整版',
      '删减版',
      '花絮',
      '幕后',
      '加更',
      '彩蛋',
      '番外',
      '特别篇',
      '剧场版',
      '高码率',
      '原画',
    ]) {
      value = value.replaceAll(token, ' ');
    }
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    value = value.replaceAll(RegExp(r'^[\-\._\s]+|[\-\._\s]+$'), '').trim();
    if (_looksLikeReleaseToken(value)) {
      return '';
    }
    return value;
  }

  static bool _looksLikeReleaseToken(String input) {
    final normalized = input.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    return RegExp(
      r'^(s\d{1,2}|season ?\d{1,2}|2160p|1080p|720p|480p|4k|8k|uhd|hdr10\+?|hdr|dovi|dv|web ?dl|webrip|bluray|remux|x264|x265|h264|h265|hevc|avc|aac|ac3|eac3|ddp(?: ?(?:5[ .]?1|7[ .]?1))?|dts|truehd|atmos|10bit|8bit|nf|amzn|dsnp|max|hmax|中字|中文字幕|中英字幕|双语|简繁|内封|外挂|特效中字|特效字幕|分段版|会员版|纯享版|导演剪辑版|导演版|加长版|未删减版|完整版|删减版|花絮|幕后|加更|彩蛋|番外|特别篇|剧场版|高码率|原画)$',
    ).hasMatch(normalized);
  }

  static bool _looksLikeWrapperFolder(String input) {
    final compact = _compactDescriptor(input);
    if (compact.isEmpty) {
      return false;
    }
    if (_looksLikeSeasonFolder(input)) {
      return false;
    }
    return _wrapperDescriptorPattern.hasMatch(compact);
  }

  static String _compactDescriptor(String input) {
    return stripEmbeddedExternalIdTags(input).trim().toLowerCase().replaceAll(
          RegExp(r'[【】\[\]\(\)（）{}<>《》"“”‘’·_.\-\s+&/\\|,:;]+'),
          '',
        );
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
          _looksLikeWrapperFolder(rawSegment)) {
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
      _compactDescriptor(rawValue),
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
          _looksLikeReleaseToken(normalizedToken) ||
          _looksLikeWrapperFolder(token)) {
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
  });

  final int? seasonNumber;
  final int? episodeNumber;
}
