import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/widgets/detail_hero_section.dart';

void main() {
  group('detail hero helpers', () {
    test('resolvePrimaryBackdropAsset prefers backdrop first', () {
      const target = MediaDetailTarget(
        title: '测试影片',
        posterUrl: 'https://example.com/poster.jpg',
        overview: '',
        backdropUrl: 'https://example.com/backdrop.jpg',
        bannerUrl: 'https://example.com/banner.jpg',
        extraBackdropUrls: ['https://example.com/extra.jpg'],
      );

      final asset = resolvePrimaryBackdropAsset(target);

      expect(asset.url, 'https://example.com/backdrop.jpg');
    });

    test(
        'resolvePrimaryBackdropAsset falls back through banner extra and poster',
        () {
      const bannerTarget = MediaDetailTarget(
        title: '测试影片',
        posterUrl: 'https://example.com/poster.jpg',
        overview: '',
        bannerUrl: 'https://example.com/banner.jpg',
        extraBackdropUrls: ['https://example.com/extra.jpg'],
      );
      const extraTarget = MediaDetailTarget(
        title: '测试影片',
        posterUrl: 'https://example.com/poster.jpg',
        overview: '',
        extraBackdropUrls: ['https://example.com/extra.jpg'],
      );
      const posterTarget = MediaDetailTarget(
        title: '测试影片',
        posterUrl: 'https://example.com/poster.jpg',
        overview: '',
      );

      expect(
        resolvePrimaryBackdropAsset(bannerTarget).url,
        'https://example.com/banner.jpg',
      );
      expect(
        resolvePrimaryBackdropAsset(extraTarget).url,
        'https://example.com/extra.jpg',
      );
      expect(
        resolvePrimaryBackdropAsset(posterTarget).url,
        'https://example.com/poster.jpg',
      );
    });

    test('buildPrimaryBackdropFallbackSources keeps unique remaining sources',
        () {
      const target = MediaDetailTarget(
        title: '测试影片',
        posterUrl: 'https://example.com/poster.jpg',
        overview: '',
        backdropUrl: 'https://example.com/backdrop.jpg',
        bannerUrl: 'https://example.com/banner.jpg',
        extraBackdropUrls: [
          'https://example.com/banner.jpg',
          'https://example.com/extra-1.jpg',
          'https://example.com/extra-1.jpg',
        ],
      );

      final fallbackUrls = buildPrimaryBackdropFallbackSources(target)
          .map((item) => item.url)
          .toList(growable: false);

      expect(
        fallbackUrls,
        [
          'https://example.com/banner.jpg',
          'https://example.com/extra-1.jpg',
          'https://example.com/poster.jpg',
        ],
      );
    });
  });
}
