import 'package:starflow/features/library/domain/media_models.dart';

class ScoredMediaItem {
  const ScoredMediaItem({required this.item, required this.score});

  final MediaItem item;
  final double score;
}

const _seasonSuffixPattern =
    r'(第\s*[0-9一二三四五六七八九十百零两]+\s*[季部篇集])|(season\s*\d+)|(s\d{1,2})|(part\s*\d+)';

/// 所有达到阈值的条目，按分数降序；同 [MediaItem.id] 只保留最高分。
List<ScoredMediaItem> listScoredMediaItemsMatchingTitles(
  List<MediaItem> library, {
  required Iterable<String> titles,
  int year = 0,
  int maxResults = 32,
}) {
  final normalizedTargets = _collectNormalizedTitleVariants(titles);
  if (normalizedTargets.isEmpty) {
    return const [];
  }

  final bestById = <String, ScoredMediaItem>{};
  for (final item in library) {
    final score = _scoreMediaItem(
      item,
      normalizedTargets: normalizedTargets,
      year: year,
    );
    if (score < 72) {
      continue;
    }
    final existing = bestById[item.id];
    if (existing == null || score > existing.score) {
      bestById[item.id] = ScoredMediaItem(item: item, score: score);
    }
  }

  final ranked = bestById.values.toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  if (ranked.length <= maxResults) {
    return ranked;
  }
  return ranked.take(maxResults).toList();
}

MediaItem? matchMediaItemByTitles(
  List<MediaItem> library, {
  required Iterable<String> titles,
  int year = 0,
}) {
  final list = listScoredMediaItemsMatchingTitles(
    library,
    titles: titles,
    year: year,
    maxResults: 1,
  );
  return list.isEmpty ? null : list.first.item;
}

MediaItem? matchMediaItemByExternalIds(
  List<MediaItem> library, {
  String imdbId = '',
  String tmdbId = '',
}) {
  final normalizedImdbId = imdbId.trim().toLowerCase();
  final normalizedTmdbId = tmdbId.trim().toLowerCase();
  if (normalizedImdbId.isEmpty && normalizedTmdbId.isEmpty) {
    return null;
  }

  for (final item in library) {
    if (normalizedImdbId.isNotEmpty &&
        item.imdbId.trim().toLowerCase() == normalizedImdbId) {
      return item;
    }
    if (normalizedTmdbId.isNotEmpty &&
        item.tmdbId.trim().toLowerCase() == normalizedTmdbId) {
      return item;
    }
  }
  return null;
}

double _scoreMediaItem(
  MediaItem item, {
  required Set<String> normalizedTargets,
  required int year,
}) {
  final aliases = _collectNormalizedTitleVariants(_mediaItemAliases(item));
  if (aliases.isEmpty) {
    return double.negativeInfinity;
  }

  var best = double.negativeInfinity;
  for (final alias in aliases) {
    for (final target in normalizedTargets) {
      final score =
          _scoreAlias(alias: alias, target: target, year: year, item: item);
      if (score > best) {
        best = score;
      }
    }
  }
  return best;
}

double _scoreAlias({
  required String alias,
  required String target,
  required int year,
  required MediaItem item,
}) {
  if (alias.isEmpty || target.isEmpty) {
    return double.negativeInfinity;
  }

  var score = double.negativeInfinity;
  if (alias == target) {
    score = 100;
  } else if (alias.length >= 4 &&
      target.length >= 4 &&
      (alias.contains(target) || target.contains(alias))) {
    score = 76;
  } else if (alias.length >= 5 &&
      target.length >= 5 &&
      (alias.startsWith(target) || target.startsWith(alias))) {
    score = 70;
  }

  if (score.isInfinite) {
    return score;
  }

  if (year > 0 && item.year > 0) {
    final delta = (item.year - year).abs();
    if (delta == 0) {
      score += 18;
    } else if (delta == 1) {
      score += 8;
    } else if (delta <= 2) {
      score += 3;
    } else {
      score -= 14;
    }
  }

  return score;
}

Iterable<String> _mediaItemAliases(MediaItem item) sync* {
  yield item.title;
  yield item.originalTitle;
  yield item.sortTitle;
}

Set<String> _collectNormalizedTitleVariants(Iterable<String> titles) {
  final result = <String>{};
  for (final title in titles) {
    for (final variant in _expandTitleVariants(title)) {
      final normalized = _normalizeTitle(variant);
      if (normalized.isNotEmpty) {
        result.add(normalized);
      }
    }
  }
  return result;
}

Iterable<String> _expandTitleVariants(String raw) sync* {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return;
  }

  yield trimmed;

  final withoutBrackets = trimmed
      .replaceAll(RegExp(r'\[[^\]]*\]|\([^\)]*\)|\{[^\}]*\}'), ' ')
      .replaceAll(RegExp(r'【[^】]*】|（[^）]*）|《|》'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (withoutBrackets.isNotEmpty && withoutBrackets != trimmed) {
    yield withoutBrackets;
  }

  final withoutSeason = withoutBrackets
      .replaceAll(RegExp(_seasonSuffixPattern, caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (withoutSeason.isNotEmpty && withoutSeason != withoutBrackets) {
    yield withoutSeason;
  }

  for (final separator in const [':', '：', '-', '—', '|', '｜', '/', '／']) {
    if (!withoutSeason.contains(separator)) {
      continue;
    }
    final prefix = withoutSeason.split(separator).first.trim();
    if (prefix.isNotEmpty) {
      yield prefix;
    }
  }
}

String _normalizeTitle(String value) {
  return value
      .toLowerCase()
      .replaceAll(
        RegExp(
          r'\b(2160p|1080p|720p|480p|bluray|blu-ray|bdrip|brrip|webrip|web-dl|webdl|hdrip|dvdrip|remux|x264|x265|h264|h265|hevc|aac|dts|atmos|hdr|uhd|proper|repack|extended|limited|internal|multi|dubbed|subs?)\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'\bS\d{1,2}E\d{1,2}\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '');
}
