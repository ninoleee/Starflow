import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/search/domain/search_models.dart';

abstract class SearchRepository {
  Future<List<SearchResult>> search(
    String query, {
    required SearchProviderConfig provider,
  });
}

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => MockSearchRepository(),
);

class MockSearchRepository implements SearchRepository {
  static const _qualities = [
    '1080p WEB-DL',
    '2160p HDR',
    'BluRay REMUX',
    '4K HEVC',
    '1080p AVC',
  ];

  @override
  Future<List<SearchResult>> search(
    String query, {
    required SearchProviderConfig provider,
  }) async {
    final keyword = query.trim();
    if (keyword.isEmpty) {
      return const [];
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
        resourceUrl: '${provider.endpoint}?q=${Uri.encodeQueryComponent(keyword)}',
      );
    });
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
}
