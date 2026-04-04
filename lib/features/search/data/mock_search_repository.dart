import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/search/data/cloud_saver_api_client.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/data/pansou_api_client.dart';
import 'package:starflow/features/search/domain/search_models.dart';

abstract class SearchRepository {
  Future<SearchFetchResult> searchOnline(
    String query, {
    required SearchProviderConfig provider,
  });

  Future<SearchFetchResult> searchLocal(
    String query, {
    String? sourceId,
    int limit = 60,
  });
}

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => AppSearchRepository(
    ref.read(panSouApiClientProvider),
    ref.read(cloudSaverApiClientProvider),
    ref.read(mediaRepositoryProvider),
  ),
);

class AppSearchRepository implements SearchRepository {
  AppSearchRepository(
    this._panSouApiClient,
    this._cloudSaverApiClient,
    this._mediaRepository,
  );

  final PanSouApiClient _panSouApiClient;
  final CloudSaverApiClient _cloudSaverApiClient;
  final MediaRepository _mediaRepository;

  @override
  Future<SearchFetchResult> searchOnline(
    String query, {
    required SearchProviderConfig provider,
  }) async {
    final keyword = query.trim();
    if (keyword.isEmpty) {
      return SearchFetchResult(items: [], filteredCount: 0);
    }

    List<SearchResult> rawResults;
    if (PanSouApiClient.supports(provider)) {
      rawResults = await _panSouApiClient.search(keyword, provider: provider);
    } else if (CloudSaverApiClient.supports(provider)) {
      rawResults =
          await _cloudSaverApiClient.search(keyword, provider: provider);
    } else {
      return SearchFetchResult(items: [], filteredCount: 0);
    }

    if (rawResults.isEmpty) {
      return SearchFetchResult(items: [], filteredCount: 0);
    }

    final filtered = _applyProviderFilters(rawResults, provider: provider);
    return filtered;
  }

  @override
  Future<SearchFetchResult> searchLocal(
    String query, {
    String? sourceId,
    int limit = 60,
  }) async {
    final keyword = query.trim();
    if (keyword.isEmpty) {
      return SearchFetchResult(items: [], filteredCount: 0);
    }

    final library = await _mediaRepository.fetchLibrary(
      sourceId: sourceId,
      limit: 2000,
    );
    final normalizedKeyword = _normalizeSearchText(keyword);
    final terms = normalizedKeyword
        .split(' ')
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);

    final scored = <_ScoredMediaItem>[];
    for (final item in library) {
      final score = _scoreLocalItem(
        item,
        normalizedKeyword: normalizedKeyword,
        terms: terms,
      );
      if (score <= 0) {
        continue;
      }
      scored.add(_ScoredMediaItem(item: item, score: score));
    }

    scored.sort((left, right) {
      final byScore = right.score.compareTo(left.score);
      if (byScore != 0) {
        return byScore;
      }
      return right.item.addedAt.compareTo(left.item.addedAt);
    });

    final items =
        scored.take(limit).map((entry) => _mapLocalResult(entry.item)).toList();
    return SearchFetchResult(
      items: items,
      rawCount: items.length,
      filteredCount: 0,
    );
  }

  SearchResult _mapLocalResult(MediaItem item) {
    final summary = item.overview.trim().isEmpty ||
            Uri.tryParse(item.overview)?.hasScheme == true
        ? '本地资源已就绪'
        : item.overview.trim();
    return SearchResult(
      id: 'local-${item.id}',
      title: item.title,
      posterUrl: item.posterUrl,
      providerId: item.sourceId,
      providerName: item.sourceName,
      quality: item.sectionName.trim().isEmpty
          ? item.sourceKind.label
          : item.sectionName,
      sizeLabel: item.year > 0
          ? '${item.year}'
          : (item.durationLabel.trim().isEmpty ? '本地资源' : item.durationLabel),
      seeders: 0,
      summary: summary,
      resourceUrl: item.streamUrl,
      cloudType: '',
      source: item.sourceName,
      detailTarget: MediaDetailTarget.fromMediaItem(item),
    );
  }

  SearchFetchResult _applyProviderFilters(
    List<SearchResult> rawResults, {
    required SearchProviderConfig provider,
  }) {
    final blockedKeywords = provider.blockedKeywords
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final allowedCloudTypes = provider.allowedCloudTypes
        .map((item) => SearchCloudTypeX.fromCode(item)?.code ?? item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();

    final filtered = <SearchResult>[];
    final seen = <String>{};
    var filteredCount = 0;

    for (final item in rawResults) {
      final detectedCloudType =
          detectSearchCloudTypeFromUrl(item.resourceUrl)?.code ??
              item.cloudType.trim();
      if (allowedCloudTypes.isNotEmpty &&
          !allowedCloudTypes.contains(detectedCloudType)) {
        filteredCount += 1;
        continue;
      }

      final haystack = [
        item.title,
        item.summary,
        item.source,
        item.providerName,
      ].join(' ').toLowerCase();
      if (blockedKeywords.any(haystack.contains)) {
        filteredCount += 1;
        continue;
      }

      final dedupeKey = normalizeSearchResourceUrl(item.resourceUrl).isEmpty
          ? item.id
          : normalizeSearchResourceUrl(item.resourceUrl);
      if (!seen.add(dedupeKey)) {
        filteredCount += 1;
        continue;
      }

      filtered.add(item);
    }

    return SearchFetchResult(
      items: filtered,
      rawCount: rawResults.length,
      filteredCount: filteredCount,
    );
  }

  int _scoreLocalItem(
    MediaItem item, {
    required String normalizedKeyword,
    required List<String> terms,
  }) {
    final normalizedTitles = [
      item.title,
      item.originalTitle,
      item.sortTitle,
      item.sectionName,
    ].map(_normalizeSearchText).where((value) => value.isNotEmpty).toSet();
    final normalizedOverview = _normalizeSearchText(item.overview);

    var bestScore = 0;
    for (final candidate in normalizedTitles) {
      if (candidate == normalizedKeyword) {
        bestScore = 140;
        break;
      }
      if (candidate.contains(normalizedKeyword)) {
        bestScore = bestScore < 110 ? 110 : bestScore;
      } else if (normalizedKeyword.contains(candidate) &&
          candidate.length >= 2) {
        bestScore = bestScore < 90 ? 90 : bestScore;
      }

      final matchedTerms = terms.where(candidate.contains).length;
      if (matchedTerms > 0) {
        final score = 48 + matchedTerms * 18;
        if (score > bestScore) {
          bestScore = score;
        }
      }
    }

    if (bestScore == 0 && normalizedOverview.isNotEmpty) {
      if (normalizedOverview.contains(normalizedKeyword)) {
        bestScore = 42;
      } else {
        final matchedTerms = terms.where(normalizedOverview.contains).length;
        if (matchedTerms > 0) {
          bestScore = 20 + matchedTerms * 10;
        }
      }
    }

    return bestScore;
  }

  String _normalizeSearchText(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), ' ')
        .trim();
    return normalized;
  }
}

class _ScoredMediaItem {
  const _ScoredMediaItem({
    required this.item,
    required this.score,
  });

  final MediaItem item;
  final int score;
}
