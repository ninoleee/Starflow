import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/widgets/detail_shared_widgets.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  group('detail shared widget helpers', () {
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
  });
}
