import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/details/application/detail_page_controller.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/widgets/detail_resource_info_section.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  group('DetailResourceInfoSection', () {
    test('douban id alone keeps the resource section visible', () {
      const target = MediaDetailTarget(
        title: '测试影片',
        posterUrl: '',
        overview: '',
        doubanId: '1292052',
      );

      expect(shouldShowDetailResourceInfo(target), isTrue);
    });

    testWidgets('matched local resource keeps the douban link', (tester) async {
      const target = MediaDetailTarget(
        title: '测试影片',
        posterUrl: '',
        overview: '',
        sourceId: 'emby-main',
        itemId: 'movie-1',
        sourceKind: MediaSourceKind.emby,
        sourceName: '客厅 Emby',
        availabilityLabel: '已匹配',
        durationLabel: '2 小时',
        doubanId: '1292052',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DetailResourceInfoSection(
              target: target,
              isTelevision: false,
              playbackEngine: PlaybackEngine.embeddedMpv,
              libraryView: const DetailLibraryMatchViewState(),
              onSearchOnline: () {},
              onLibraryMatchSelected: (_) {},
              onOpenTelevisionLibraryMatchPicker: () {},
              onMatchLocalResource: () {},
              onCheckOnlineResourceUpdate: null,
              isCheckingOnlineResourceUpdate: false,
              onOpenPlaybackEnginePicker: () {},
              onPlaybackEngineSelected: (_) {},
              onOpenMetadataIndexManager: () {},
            ),
          ),
        ),
      );

      expect(find.text('Emby · 客厅 Emby'), findsOneWidget);
      expect(find.text('链接'), findsOneWidget);
      expect(find.text('跳转豆瓣详情页'), findsOneWidget);
      for (final pair in [
        ('状态', '已匹配'),
        ('来源', 'Emby · 客厅 Emby'),
        ('链接', '跳转豆瓣详情页'),
        ('时长', '2 小时'),
      ]) {
        expect(
          tester.getTopLeft(find.text(pair.$2)).dy -
              tester.getTopLeft(find.text(pair.$1)).dy,
          closeTo(0, 0.1),
          reason: '${pair.$1} label should align with its value',
        );
      }
    });
  });
}
