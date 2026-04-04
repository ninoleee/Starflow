import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/data/pansou_api_client.dart';
import 'package:starflow/features/search/domain/search_models.dart';

abstract class SearchRepository {
  Future<List<SearchResult>> searchOnline(
    String query, {
    required SearchProviderConfig provider,
  });

  Future<List<SearchResult>> searchLocal(
    String query, {
    String? sourceId,
    int limit = 60,
  });
}

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => AppSearchRepository(
    ref.read(panSouApiClientProvider),
    ref.read(mediaRepositoryProvider),
  ),
);

class AppSearchRepository implements SearchRepository {
  AppSearchRepository(this._panSouApiClient, this._mediaRepository);

  final PanSouApiClient _panSouApiClient;
  final MediaRepository _mediaRepository;

  static const _qualities = [
    '1080p WEB-DL',
    '2160p HDR',
    'BluRay REMUX',
    '4K HEVC',
    '1080p AVC',
  ];

  @override
  Future<List<SearchResult>> searchOnline(
    String query, {
    required SearchProviderConfig provider,
  }) async {
    final keyword = query.trim();
    if (keyword.isEmpty) {
      return const [];
    }

    if (PanSouApiClient.supports(provider)) {
      return _panSouApiClient.search(keyword, provider: provider);
    }

    await Future<void>.delayed(const Duration(milliseconds: 280));

    return List.generate(6, (index) {
      final quality = _qualities[index % _qualities.length];
      final posterSeed = Uri.encodeComponent('${provider.id}-$keyword-$index');
      return SearchResult(
        id: '${provider.id}-$index',
        title: '$keyword ${_variantTitle(index)}',
        posterUrl: 'https://picsum.photos/seed/$posterSeed/400/600',
        providerId: provider.id,
        providerName: provider.name,
        quality: quality,
        sizeLabel: '${12 + index * 4} GB',
        seeders: 18 + index * 7,
        summary: '${provider.kind.label} 结果，适合后续接入下载器或离线缓存流程。',
        resourceUrl:
            '${provider.endpoint}?q=${Uri.encodeQueryComponent(keyword)}',
        source: provider.name,
      );
    });
  }

  @override
  Future<List<SearchResult>> searchLocal(
    String query, {
    String? sourceId,
    int limit = 60,
  }) async {
    final keyword = query.trim();
    if (keyword.isEmpty) {
      return const [];
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

    return scored
        .take(limit)
        .map((entry) => _mapLocalResult(entry.item))
        .toList();
  }

  String _variantTitle(int index) {
    switch (index) {
      case 0:
        return '导演剪辑版';
      case 1:
        return '全集打包';
      case 2:
        return '高码率收藏版';
      case 3:
        return '中字修复版';
      case 4:
        return '杜比视界版';
      default:
        return '资源集合';
    }
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
      source: item.sourceName,
      detailTarget: MediaDetailTarget.fromMediaItem(item),
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
