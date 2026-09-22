import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/home/presentation/home_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  for (final style in HomeModuleDisplayStyle.values) {
    testWidgets('TV rail restores leading inset after round trip: $style',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final section = HomeSectionViewModel(
        id: 'rail',
        title: 'Rail',
        subtitle: '',
        emptyMessage: '',
        layout: HomeSectionLayout.posterRail,
        items: List.generate(
            12,
            (index) => HomeCardViewModel(
                  id: '$index',
                  title: 'Film $index',
                  subtitle: '',
                  posterUrl: '',
                  detailTarget: MediaDetailTarget(
                    title: 'Film $index',
                    posterUrl: '',
                    overview: '',
                  ),
                )),
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(
            SeedData.defaultSettings.copyWith(
              homeStartupAutoRefreshEnabled: false,
              homeModules: [
                HomeModuleConfig(
                  id: 'rail',
                  type: HomeModuleType.doubanInterest,
                  title: 'Rail',
                  enabled: true,
                  displayStyle: style,
                )
              ],
            ),
          ),
          homeResolvedSectionsProvider.overrideWithValue(
            HomeResolvedSectionsState(sections: [section]),
          ),
          homeSectionProvider.overrideWith((ref, id) async => section),
        ],
        child: const MaterialApp(home: HomePage()),
      ));
      await tester.pumpAndSettle();
      final first = find.byWidgetPredicate(
        (widget) => widget is MediaPosterTile && widget.title == 'Film 0',
      );
      final initialX = tester.getTopLeft(first).dx;
      expect(initialX, 12);
      final rail = tester.widget<ListView>(find.byWidgetPredicate(
        (widget) =>
            widget is ListView && widget.scrollDirection == Axis.horizontal,
      ));
      for (var round = 0; round < 2; round++) {
        for (var i = 0; i < 7; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
        }
        expect(rail.controller!.offset, greaterThan(12));
        for (var i = 0; i < 7; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pumpAndSettle();
        }
        expect(
            tester.widget<MediaPosterTile>(first).focusNode!.hasFocus, isTrue);
        expect(rail.controller!.offset, 0);
        expect(tester.getTopLeft(first).dx, initialX);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
