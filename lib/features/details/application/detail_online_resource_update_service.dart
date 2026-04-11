import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_naming.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final detailOnlineResourceUpdateServiceProvider =
    Provider<DetailOnlineResourceUpdateService>(
  (ref) => const DetailOnlineResourceUpdateService(),
);

class DetailFavoriteSearchResourceMatch {
  const DetailFavoriteSearchResourceMatch({
    required this.result,
    required this.folderName,
    required this.score,
  });

  final SearchResult result;
  final String folderName;
  final int score;
}

class DetailOnlineResourceUpdateResult {
  const DetailOnlineResourceUpdateResult({
    required this.favoriteMatch,
    required this.targetFolderPath,
    required this.updatedEpisodeLabels,
    required this.onlineVideoCount,
    required this.localVideoCount,
    required this.localFolderExists,
  });

  final DetailFavoriteSearchResourceMatch favoriteMatch;
  final String targetFolderPath;
  final List<String> updatedEpisodeLabels;
  final int onlineVideoCount;
  final int localVideoCount;
  final bool localFolderExists;

  bool get hasUpdates => updatedEpisodeLabels.isNotEmpty;

  String buildDialogMessage() {
    final lines = <String>[
      if (favoriteMatch.result.providerName.trim().isNotEmpty)
        '来源：${favoriteMatch.result.providerName.trim()}',
      '夸克目录：$targetFolderPath',
      '在线视频：$onlineVideoCount',
      '本地视频：$localVideoCount',
    ];
    if (!hasUpdates) {
      lines.add(localFolderExists ? '没有更新。' : '夸克目录为空，没有可对比的已保存文件。');
      return lines.join('\n');
    }
    lines.add('发现更新 ${updatedEpisodeLabels.length} 条：');
    lines.addAll(updatedEpisodeLabels);
    return lines.join('\n');
  }
}

class DetailOnlineResourceUpdateService {
  const DetailOnlineResourceUpdateService();

  DetailFavoriteSearchResourceMatch? resolveFavoriteMatch({
    required MediaDetailTarget target,
    required Iterable<SearchResult> favorites,
  }) {
    if (!_supportsTarget(target)) {
      return null;
    }

    final folderName = _preferredFolderName(target);
    final folderNameKey = _normalizeTitle(folderName);
    final targetExternalIds = _collectTargetExternalIds(target);
    final targetKeys = _collectTargetKeys(target);
    if (folderNameKey.isNotEmpty) {
      targetKeys.add(folderNameKey);
    }
    if (targetExternalIds.isEmpty && targetKeys.isEmpty) {
      return null;
    }

    DetailFavoriteSearchResourceMatch? bestMatch;
    for (final favorite in favorites) {
      if (favorite.detailTarget != null) {
        continue;
      }
      if (detectSearchCloudTypeFromUrl(favorite.resourceUrl) !=
          SearchCloudType.quark) {
        continue;
      }
      final score = _scoreFavorite(
        targetExternalIds,
        targetKeys,
        folderNameKey,
        favorite,
      );
      if (score <= 0) {
        continue;
      }
      final current = DetailFavoriteSearchResourceMatch(
        result: favorite,
        folderName: _resolveFavoriteFolderName(
          favorite,
          fallback: folderName,
        ),
        score: score,
      );
      if (bestMatch == null || current.score > bestMatch.score) {
        bestMatch = current;
      }
    }
    return bestMatch;
  }

  Future<DetailOnlineResourceUpdateResult> checkForUpdates({
    required MediaDetailTarget target,
    required DetailFavoriteSearchResourceMatch favoriteMatch,
    required NetworkStorageConfig networkStorage,
    required QuarkSaveClient quarkSaveClient,
  }) async {
    final cookie = networkStorage.quarkCookie.trim();
    if (cookie.isEmpty) {
      throw const QuarkSaveException('请先在搜索设置里填写夸克 Cookie');
    }

    final sharePreview = await quarkSaveClient.previewShareLink(
      shareUrl: favoriteMatch.result.resourceUrl,
      cookie: cookie,
      toPdirPath: networkStorage.quarkSaveFolderPath,
      saveFolderName: favoriteMatch.folderName,
    );
    final localDirectory = await quarkSaveClient.resolveDirectoryByPath(
      cookie: cookie,
      path: sharePreview.targetFolderPath,
    );
    final localEntries = localDirectory == null
        ? const <QuarkFileEntry>[]
        : await quarkSaveClient.listEntriesRecursively(
            cookie: cookie,
            parentFid: localDirectory.fid,
          );
    final localRelativePathKeys = localEntries
        .where((entry) => entry.isVideo)
        .map(
          (entry) => _normalizePathKey(
            _relativePathFromRoot(
              rootPath: sharePreview.targetFolderPath,
              entryPath: entry.path,
            ),
          ),
        )
        .where((entry) => entry.isNotEmpty)
        .toSet();
    final updatedEpisodeLabels = sharePreview.videoEntries
        .where(
          (entry) => !localRelativePathKeys.contains(
            _normalizePathKey(entry.relativePath),
          ),
        )
        .map((entry) => _formatEpisodeLabel(entry.relativePath))
        .fold<List<String>>(<String>[], (list, label) {
      if (!list.contains(label)) {
        list.add(label);
      }
      return list;
    });

    return DetailOnlineResourceUpdateResult(
      favoriteMatch: favoriteMatch,
      targetFolderPath: sharePreview.targetFolderPath,
      updatedEpisodeLabels: updatedEpisodeLabels,
      onlineVideoCount: sharePreview.videoEntries.length,
      localVideoCount: localRelativePathKeys.length,
      localFolderExists: localDirectory != null,
    );
  }

  bool _supportsTarget(MediaDetailTarget target) {
    final itemType = target.itemType.trim().toLowerCase();
    return itemType == 'movie' ||
        itemType == 'series' ||
        itemType == 'season' ||
        itemType == 'episode';
  }

  Map<String, String> _collectTargetExternalIds(MediaDetailTarget target) {
    return _normalizedExternalIds(
      doubanId: target.doubanId,
      imdbId: target.imdbId,
      tmdbId: target.tmdbId,
      tvdbId: target.tvdbId,
      wikidataId: target.wikidataId,
    );
  }

  Set<String> _collectTargetKeys(MediaDetailTarget target) {
    final keys = <String>{};
    for (final candidate in [
      target.searchQuery,
      target.playbackTarget?.resolvedSeriesTitle ?? '',
      target.playbackTarget?.seriesTitle ?? '',
      if (target.itemType.trim().toLowerCase() != 'episode') target.title,
    ]) {
      for (final variant in _expandTitleVariants(candidate)) {
        final normalized = _normalizeTitle(variant);
        if (normalized.isNotEmpty) {
          keys.add(normalized);
        }
      }
    }
    return keys;
  }

  String _preferredFolderName(MediaDetailTarget target) {
    for (final candidate in [
      target.searchQuery,
      target.playbackTarget?.resolvedSeriesTitle ?? '',
      target.playbackTarget?.seriesTitle ?? '',
      target.title,
    ]) {
      final trimmed = candidate.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return '';
  }

  int _scoreFavorite(
    Map<String, String> targetExternalIds,
    Set<String> targetKeys,
    String folderNameKey,
    SearchResult favorite,
  ) {
    final externalIdScore = _scoreFavoriteExternalIds(
      targetExternalIds,
      favorite,
    );
    if (externalIdScore > 0) {
      return externalIdScore;
    }

    final favoriteFolderName = favorite.favoriteFolderName.trim();
    final favoriteFolderNameKey = _normalizeTitle(favoriteFolderName);
    if (favoriteFolderNameKey.isNotEmpty &&
        favoriteFolderNameKey == folderNameKey) {
      return 140;
    }

    var bestScore = 0;
    for (final candidate in [
      favorite.favoriteFolderName,
      favorite.title,
      favorite.originalSearchTitle,
    ]) {
      for (final variant in _expandTitleVariants(candidate)) {
        final normalized = _normalizeTitle(variant);
        if (normalized.isEmpty) {
          continue;
        }
        if (targetKeys.contains(normalized)) {
          bestScore = bestScore < 120 ? 120 : bestScore;
          continue;
        }
        for (final targetKey in targetKeys) {
          if (normalized.length >= 4 &&
              targetKey.length >= 4 &&
              (normalized.contains(targetKey) ||
                  targetKey.contains(normalized))) {
            bestScore = bestScore < 84 ? 84 : bestScore;
          }
        }
      }
    }
    return bestScore;
  }

  int _scoreFavoriteExternalIds(
    Map<String, String> targetExternalIds,
    SearchResult favorite,
  ) {
    if (targetExternalIds.isEmpty) {
      return 0;
    }

    final favoriteExternalIds = _normalizedExternalIds(
      doubanId: favorite.doubanId,
      imdbId: favorite.imdbId,
      tmdbId: favorite.tmdbId,
      tvdbId: favorite.tvdbId,
      wikidataId: favorite.wikidataId,
    );
    if (favoriteExternalIds.isEmpty) {
      return 0;
    }

    var bestScore = 0;
    var matchedCount = 0;

    void collect(String key, int score) {
      final targetValue = targetExternalIds[key];
      final favoriteValue = favoriteExternalIds[key];
      if (targetValue == null ||
          targetValue.isEmpty ||
          favoriteValue == null ||
          favoriteValue.isEmpty ||
          targetValue != favoriteValue) {
        return;
      }
      matchedCount += 1;
      if (score > bestScore) {
        bestScore = score;
      }
    }

    collect('douban', 420);
    collect('imdb', 410);
    collect('tmdb', 400);
    collect('tvdb', 390);
    collect('wikidata', 380);

    if (bestScore == 0) {
      return 0;
    }
    return bestScore + (matchedCount - 1) * 8;
  }

  String _resolveFavoriteFolderName(
    SearchResult favorite, {
    required String fallback,
  }) {
    for (final candidate in [
      favorite.favoriteFolderName,
      favorite.title,
      favorite.originalSearchTitle,
      fallback,
    ]) {
      final trimmed = candidate.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return '';
  }
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
      .replaceAll(
        RegExp(
          r'(第\s*[0-9一二三四五六七八九十百零两]+\s*[季部篇集])|(season\s*\d+)|(s\d{1,2})|(part\s*\d+)',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (withoutSeason.isNotEmpty && withoutSeason != withoutBrackets) {
    yield withoutSeason;
  }
}

String _normalizeTitle(String value) {
  return MediaNaming.normalizeLookupTitle(value);
}

Map<String, String> _normalizedExternalIds({
  String doubanId = '',
  String imdbId = '',
  String tmdbId = '',
  String tvdbId = '',
  String wikidataId = '',
}) {
  final values = <String, String>{};

  void add(String key, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }
    values[key] = trimmed;
  }

  add('douban', doubanId);
  add('imdb', imdbId.toLowerCase());
  add('tmdb', tmdbId);
  add('tvdb', tvdbId);
  add('wikidata', wikidataId.toUpperCase());
  return values;
}

String _relativePathFromRoot({
  required String rootPath,
  required String entryPath,
}) {
  final normalizedRoot = normalizeQuarkDirectoryPath(rootPath);
  final normalizedEntry = normalizeQuarkDirectoryPath(entryPath);
  if (normalizedRoot == '/') {
    return normalizedEntry.replaceFirst(RegExp(r'^/+'), '');
  }
  if (normalizedEntry == normalizedRoot) {
    return '';
  }
  final normalizedPrefix = '$normalizedRoot/';
  if (!normalizedEntry.startsWith(normalizedPrefix)) {
    return normalizedEntry.replaceFirst(RegExp(r'^/+'), '');
  }
  return normalizedEntry.substring(normalizedPrefix.length);
}

String _normalizePathKey(String value) {
  return value.trim().replaceAll('\\', '/').toLowerCase();
}

String _formatEpisodeLabel(String relativePath) {
  final normalized = relativePath.replaceAll('\\', '/').trim();
  if (normalized.isEmpty) {
    return relativePath.trim();
  }
  return normalized;
}
