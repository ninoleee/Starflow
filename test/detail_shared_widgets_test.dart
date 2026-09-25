import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/app/theme/app_typography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/widgets/detail_shared_widgets.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  testWidgets('detail block title is 10 and bottom spacing is 8',
      (tester) async {
    const contentKey = ValueKey('content');
    const nextKey = ValueKey('next');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const DetailBlock(
              title: 'Episodes',
              child: SizedBox(key: contentKey, height: 100),
            ),
            const SizedBox(key: nextKey, height: 20),
          ],
        ),
      ),
    ));
    expect(
        tester.getRect(find.byKey(nextKey)).top -
            tester.getRect(find.byKey(contentKey)).bottom,
        8);
    expect(
      tester.getRect(find.byKey(contentKey)).top -
          tester.getRect(find.text('Episodes')).bottom,
        10,
    );
    expect(tester.takeException(), isNull);
  });

  group('detail shared widget helpers', () {
    testWidgets('DetailGroupLabel uses the title text size', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: DetailGroupLabel('导演'),
        ),
      ));
      final text = tester.widget<Text>(find.text('导演'));
      expect(text.style!.fontSize, AppTextSizes.title);
      expect(text.style!.fontWeight, FontWeight.w700);
      expect(text.style!.height, AppLineHeights.title);
    });

    test('resolveDetailPathTail decodes url and path tails', () {
      expect(
        resolveDetailPathTail(
          'https://example.com/video/%E7%AC%AC1%E9%9B%86%20%E9%A3%8E%E6%9A%B4.mkv?x=1',
        ),
        '第1集 风暴.mkv',
      );
      expect(
        resolveDetailPathTail(r'D:\media\shows\episode-01.mkv'),
        'episode-01.mkv',
      );
    });

    test('resolveDetailEpisodeTitleLine shares one episode title rule', () {
      const pageTarget = MediaDetailTarget(
        title: '风暴前夜',
        posterUrl: '',
        overview: '',
        itemType: 'episode',
        searchQuery: '人生切割术',
      );
      const currentTarget = MediaDetailTarget(
        title: '风暴前夜',
        posterUrl: '',
        overview: '',
        itemType: 'episode',
        searchQuery: '人生切割术',
        playbackTarget: PlaybackTarget(
          title: '风暴前夜',
          sourceId: 'emby-main',
          streamUrl: 'https://example.com/stream/episode-01.m3u8',
          sourceName: 'Home Emby',
          sourceKind: MediaSourceKind.emby,
          actualAddress:
              'https://example.com/video/%E7%AC%AC1%E9%9B%86%20%E9%A3%8E%E6%9A%B4%E5%89%8D%E5%A4%9C.mkv',
          itemType: 'episode',
          seriesTitle: '人生切割术',
        ),
      );

      expect(
        resolveDetailPrimaryTitle(
          currentTarget: currentTarget,
          pageTarget: pageTarget,
          emptyFallback: '剧情简介',
        ),
        '人生切割术',
      );
      expect(
        resolveDetailEpisodeTitleLine(
          currentTarget: currentTarget,
          pageTarget: pageTarget,
        ),
        '第1集 风暴前夜.mkv',
      );
    });

    testWidgets('PersonRail avatar does not force square decode',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Material(
              child: PersonRail(
                people: const [
                  MediaPersonProfile(
                    name: 'Keanu Reeves',
                    avatarUrl: 'https://example.com/profile.jpg',
                  ),
                ],
                focusScopePrefix: 'detail:actor',
                onPersonTap: (_) {},
              ),
            ),
          ),
        ),
      );

      final image = tester.widget<AppNetworkImage>(
        find.byType(AppNetworkImage),
      );
      expect(image.cacheWidth, 148);
      expect(image.cacheHeight, isNull);
      expect(image.fit, BoxFit.cover);
      final focusAction = tester.widget<TvFocusableAction>(
        find.byType(TvFocusableAction),
      );
      expect(focusAction.focusId, 'detail:actor:Keanu Reeves');
      expect(focusAction.borderRadius, BorderRadius.circular(37));
      expect(focusAction.focusScale, 1.06);
    });

    testWidgets('PlatformRail keeps company logos in one horizontal row',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isTelevisionProvider.overrideWith((ref) => true),
          ],
          child: MaterialApp(
            home: Material(
              child: PlatformRail(
                platforms: [
                  MediaPersonProfile(
                    name: 'Company A',
                    avatarUrl: 'https://example.com/company-a.png',
                  ),
                  MediaPersonProfile(
                    name: 'Company B',
                    avatarUrl: 'https://example.com/company-b.png',
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(listView.scrollDirection, Axis.horizontal);
      final delegate = listView.childrenDelegate as SliverChildBuilderDelegate;
      expect(delegate.childCount, 3); // 2 logos plus 1 separator.
    });

    testWidgets('PlatformRail company logos expose TV focus targets',
        (tester) async {
      MediaPersonProfile? tappedCompany;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isTelevisionProvider.overrideWith((ref) => true),
          ],
          child: MaterialApp(
            home: Material(
              child: PlatformRail(
                platforms: [
                  MediaPersonProfile(
                    name: 'Company A',
                    avatarUrl: 'https://example.com/company-a.png',
                  ),
                ],
                onPlatformTap: (company) {
                  tappedCompany = company;
                },
              ),
            ),
          ),
        ),
      );

      final focusableActions = tester
          .widgetList<TvFocusableAction>(find.byType(TvFocusableAction))
          .toList(growable: false);
      expect(focusableActions, hasLength(1));
      expect(focusableActions.single.focusId, 'detail:company:Company A');
      focusableActions.single.onPressed!();
      expect(tappedCompany?.name, 'Company A');
    });

    testWidgets('DetailImageGallery exposes a visible TV focus style',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Material(
              child: DetailImageGallery(
                images: [
                  DetailImageAsset(url: 'https://example.com/still-1.jpg'),
                  DetailImageAsset(url: 'https://example.com/still-2.jpg'),
                ],
              ),
            ),
          ),
        ),
      );

      final focusableActions = tester
          .widgetList<TvFocusableAction>(find.byType(TvFocusableAction))
          .toList(growable: false);

      expect(focusableActions, isNotEmpty);
      expect(
        focusableActions.every(
          (widget) => widget.visualStyle == TvFocusVisualStyle.subtle,
        ),
        isTrue,
      );
      expect(
        focusableActions.every(
          (widget) => widget.focusScale == kTvButtonFocusScale,
        ),
        isTrue,
      );
    });

    test('gallery images use in-memory-only image caching', () {
      const target = MediaDetailTarget(
        title: '剧集',
        posterUrl: 'https://example.com/poster.jpg',
        overview: '',
        backdropUrl: 'https://example.com/backdrop.jpg',
        bannerUrl: 'https://example.com/banner.jpg',
        extraBackdropUrls: ['https://example.com/still.jpg'],
      );

      final images = buildDetailGalleryImages(target);

      expect(images, hasLength(3));
      expect(
        images.every(
          (image) =>
              image.cachePolicy == AppNetworkImageCachePolicy.networkOnly,
        ),
        isTrue,
      );
    });
  });
}
