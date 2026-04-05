import 'package:starflow/core/utils/webdav_trace.dart';

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

  static NasMediaRecognition recognize(String actualAddress) {
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
    final parentTitle = parentLooksLikeSeasonFolder
        ? cleanedGrandParentTitle
        : cleanedParentTitle;

    String title = cleanedFileTitle;
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
      if (parentTitle.trim().isNotEmpty) {
        title = parentTitle.trim();
      }
    } else if (parentLooksLikeSeasonFolder && parentTitle.trim().isNotEmpty) {
      title = parentTitle.trim();
      itemType = 'episode';
      preferSeries = true;
      seasonNumber = parentSeason ?? grandParentSeason;
    } else if (_looksLikeSeriesFolder(parentRaw) &&
        cleanedParentTitle.trim().isNotEmpty) {
      preferSeries = true;
    }

    if (title.trim().isEmpty) {
      title = parentTitle.trim().isNotEmpty
          ? parentTitle.trim()
          : _cleanTitle(fileBaseName);
    }
    if (title.trim().isEmpty) {
      title = fileBaseName.trim();
    }

    final result = NasMediaRecognition(
      title: title.trim(),
      searchQuery: title.trim(),
      originalFileName: fileName.trim(),
      parentTitle: parentTitle.trim(),
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
      r'第(\d{1,3})[集话]',
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
    return !_looksLikeReleaseToken(input) && normalized.length >= 2;
  }

  static String _cleanTitle(
    String input, {
    bool removeEpisodeTokens = false,
    bool removeYear = false,
  }) {
    var value = input.trim();
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
        r'x264|x265|h264|h265|hevc|avc|aac|ac3|eac3|dts|truehd|atmos|'
        r'proper|repack|complete|multi|nf|amzn|dsnp|max|hmax|'
        r'中字|双语|国粤|简繁|内封|外挂|中英字幕'
        r')\b',
        caseSensitive: false,
      ),
      ' ',
    );
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
      r'^(s\d{1,2}|season ?\d{1,2}|2160p|1080p|720p|4k|hdr|web ?dl|webrip|bluray|remux|x264|x265|h264|h265|hevc|aac|ac3|eac3|dts|truehd|atmos)$',
    ).hasMatch(normalized);
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
