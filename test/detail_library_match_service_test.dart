import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/details/application/detail_library_match_service.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';

void main() {
  group('DetailLibraryMatchService.buildManualMatchCandidates', () {
    const service = DetailLibraryMatchService();

    test('falls back to title match when external ids miss in a source', () {
      const target = MediaDetailTarget(
        title: '乘风2026',
        posterUrl: '',
        overview: '',
        year: 2026,
        itemType: 'series',
        tmdbId: '317948',
        sourceName: 'WebDAV',
      );
      final items = [
        MediaItem(
          id: 'nas-series',
          title: '乘风2026',
          overview: '',
          posterUrl: '',
          year: 2026,
          durationLabel: '剧集',
          genres: const [],
          itemType: 'series',
          sectionId: 'movies',
          sectionName: 'movies',
          sourceId: 'nas-main',
          sourceName: 'WebDAV',
          sourceKind: MediaSourceKind.nas,
          streamUrl: '',
          actualAddress: '/movies/strm/quark/乘风2026',
          addedAt: DateTime.utc(2026, 4, 12),
        ),
      ];

      final candidates = service.buildManualMatchCandidates(
        target: target,
        items: items,
        titles: const ['乘风2026'],
        year: 2026,
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.item.id, 'nas-series');
      expect(candidates.single.matchReason, '按标题 + 年份匹配');
    });

    test('keeps external id matches as highest priority', () {
      const target = MediaDetailTarget(
        title: '乘风2026',
        posterUrl: '',
        overview: '',
        year: 2026,
        itemType: 'series',
        tmdbId: '317948',
        sourceName: 'Quark',
      );
      final items = [
        MediaItem(
          id: 'quark-series',
          title: '乘风2026',
          overview: '',
          posterUrl: '',
          year: 2026,
          durationLabel: '剧集',
          genres: const [],
          itemType: 'series',
          sectionId: 'quark',
          sectionName: 'Quark',
          sourceId: 'quark-main',
          sourceName: 'Quark',
          sourceKind: MediaSourceKind.quark,
          streamUrl: '',
          actualAddress: '/乘风2026',
          tmdbId: '317948',
          addedAt: DateTime.utc(2026, 4, 12),
        ),
      ];

      final candidates = service.buildManualMatchCandidates(
        target: target,
        items: items,
        titles: const ['乘风2026'],
        year: 2026,
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.item.id, 'quark-series');
      expect(candidates.single.matchReason, '按 TMDB ID 匹配');
      expect(candidates.single.score, 1e9);
    });
  });
}
