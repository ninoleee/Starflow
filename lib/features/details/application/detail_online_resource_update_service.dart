import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_naming.dart';
import 'package:starflow/features/library/domain/tmdb_media_identity.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/domain/cloud_save_feedback.dart';
import 'package:starflow/features/search/domain/cloud_save_rules.dart';
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

  CloudSaveDrive get drive =>
      switch (detectSearchCloudTypeFromUrl(result.resourceUrl)) {
        SearchCloudType.quark => CloudSaveDrive.quark,
        SearchCloudType.cloud115 => CloudSaveDrive.cloud115,
        _ => throw const CloudSaveException('此网盘暂不支持检查更新'),
      };

  bool hasConfiguredCookie(NetworkStorageConfig config) =>
      (drive == CloudSaveDrive.cloud115
              ? config.cloud115Cookie
              : config.quarkCookie)
          .trim()
          .isNotEmpty;
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
      '${favoriteMatch.drive.label}目录：$targetFolderPath',
      '在线视频：$onlineVideoCount',
      '本地视频：$localVideoCount',
    ];
    if (!hasUpdates) {
      lines.add(localFolderExists
          ? '没有更新。'
          : '${favoriteMatch.drive.label}目录不存在，分享中没有可保存的视频。');
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
    final matches =
        resolveFavoriteMatches(target: target, favorites: favorites);
    return matches.isEmpty ? null : matches.first;
  }

  List<DetailFavoriteSearchResourceMatch> resolveFavoriteMatches({
    required MediaDetailTarget target,
    required Iterable<SearchResult> favorites,
  }) {
    if (!_supportsTarget(target)) {
      return const [];
    }

    final folderName = _preferredFolderName(target);
    final folderNameKey = _normalizeTitle(folderName);
    final targetExternalIds = _collectTargetExternalIds(target);
    final targetKeys = _collectTargetKeys(target);
    if (folderNameKey.isNotEmpty) {
      targetKeys.add(folderNameKey);
    }
    if (targetExternalIds.isEmpty && targetKeys.isEmpty) {
      return const [];
    }

    final matches = <DetailFavoriteSearchResourceMatch>[];
    for (final favorite in favorites) {
      final targetType = TmdbMediaType.fromItemType(target.itemType);
      final favoriteType =
          TmdbMediaType.fromItemType(favorite.metadataMediaType);
      if (targetType != null &&
          favoriteType != null &&
          targetType != favoriteType) {
        continue;
      }
      if (favorite.detailTarget != null) {
        continue;
      }
      if (!const {SearchCloudType.quark, SearchCloudType.cloud115}
          .contains(detectSearchCloudTypeFromUrl(favorite.resourceUrl))) {
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
        result: prepareSearchResultShareCredentials(favorite),
        folderName: _resolveFavoriteFolderName(
          favorite,
          fallback: folderName,
        ),
        score: score,
      );
      final index = matches.indexWhere((match) => match.score < current.score);
      matches.insert(index < 0 ? matches.length : index, current);
    }
    return matches;
  }

  Future<DetailOnlineResourceUpdateResult> checkForUpdates({
    required MediaDetailTarget target,
    required DetailFavoriteSearchResourceMatch favoriteMatch,
    required NetworkStorageConfig networkStorage,
    required QuarkSaveClient quarkSaveClient,
    Cloud115SaveClient? cloud115SaveClient,
  }) async {
    final drive = favoriteMatch.drive;
    if (!favoriteMatch.hasConfiguredCookie(networkStorage)) {
      throw CloudSaveException('请先在网盘与转存设置中配置${drive.label} Cookie');
    }
    final share = prepareSearchResultShareCredentials(favoriteMatch.result);
    final CloudSavePreview preview;
    if (drive == CloudSaveDrive.cloud115) {
      if (cloud115SaveClient == null) {
        throw const CloudSaveException('115 更新客户端未配置');
      }
      preview = await cloud115SaveClient.previewSave(
        shareUrl: share.resourceUrl,
        password: searchResultSharePassword(share),
        cookie: networkStorage.cloud115Cookie,
        folderId: networkStorage.cloud115SaveFolderId,
        folderPath: networkStorage.cloud115SaveFolderPath,
        saveFolderName: favoriteMatch.folderName,
        sanitizedNameCharacters:
            networkStorage.cloud115SanitizeSavedNamesEnabled
                ? networkStorage.cloud115SanitizedNameCharacters
                : '',
      );
    } else {
      preview = await quarkSaveClient.previewSave(
        shareUrl: share.resourceUrl,
        cookie: networkStorage.quarkCookie,
        folderId: networkStorage.quarkSaveFolderId,
        folderPath: networkStorage.quarkSaveFolderPath,
        saveFolderName: favoriteMatch.folderName,
        sanitizedNameCharacters: networkStorage.quarkSanitizeSavedNamesEnabled
            ? networkStorage.quarkSanitizedNameCharacters
            : '',
      );
    }

    return DetailOnlineResourceUpdateResult(
      favoriteMatch: favoriteMatch,
      targetFolderPath: preview.targetFolderPath,
      updatedEpisodeLabels: preview.missingVideos
          .map((entry) => entry.relativePath)
          .toList(growable: false),
      onlineVideoCount:
          preview.onlineEntries.where((entry) => entry.isVideo).length,
      localVideoCount:
          preview.localEntries.where((entry) => entry.isVideo).length,
      localFolderExists: preview.localFolderExists,
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
      itemType: target.itemType,
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
      itemType: favorite.metadataMediaType,
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
  String itemType = '',
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
  add('tmdb', TmdbMediaIdentity.fromRaw(tmdbId, itemType)?.key ?? '');
  add('tvdb', tvdbId);
  add('wikidata', wikidataId.toUpperCase());
  return values;
}
