import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/widgets/detail_episode_browser.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

const _series = MediaDetailTarget(
  title: 'Series',
  posterUrl: '',
  overview: '',
  sourceId: 'nas',
  itemId: 'series',
  itemType: 'series',
);

List<DetailEpisodeGroup> _groups() => List.generate(
    24,
    (index) => DetailEpisodeGroup(
          id: 's$index',
          title: index == 9 ? 'Extended Season Name' : 'Season $index',
          seasonNumber: index == 9 ? null : index + 1,
          episodes: const [],
        ));

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(1280, 720)
  ]) {
    for (final initialGroupId in ['s0', 's9', 's12', 's23']) {
      testWidgets(
          'season $initialGroupId positions only on entry at ${size.width}',
          (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final selected = ValueNotifier(initialGroupId);
        addTearDown(selected.dispose);
        final userFocus = FocusNode(debugLabel: 'existing-page-focus');
        addTearDown(userFocus.dispose);
        final pageScroll = ScrollController(initialScrollOffset: 60);
        addTearDown(pageScroll.dispose);
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(ProviderScope(
          overrides: [
            appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
            isTelevisionProvider.overrideWith((ref) => size.width >= 1200),
          ],
          child: MaterialApp(
              home: Scaffold(
            body: RepaintBoundary(
              key: boundaryKey,
              child: Focus(
                focusNode: userFocus,
                child: ListView(
                  controller: pageScroll,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    const SizedBox(height: 100),
                    ValueListenableBuilder<String>(
                      valueListenable: selected,
                      builder: (_, id, __) => DetailEpisodeBrowser(
                        seriesTarget: _series,
                        groups: _groups(),
                        selectedGroupId: id,
                        onSeasonSelected: (id) => selected.value = id,
                      ),
                    ),
                    const SizedBox(height: 1000),
                  ],
                ),
              ),
            ),
          )),
        ));
        userFocus.requestFocus();
        await tester.pumpAndSettle();
        final tabs = find.byWidgetPredicate(
            (widget) => widget is StarflowChipButton && widget.selected);
        if (initialGroupId == 's0') {
          expect(tester.getRect(tabs).left, closeTo(16, 0.1));
        } else if (initialGroupId == 's23') {
          expect(tester.getRect(tabs).right, closeTo(size.width - 16, 0.1));
        } else {
          expect(tester.getCenter(tabs).dx, closeTo(size.width / 2, 1));
        }
        expect(pageScroll.offset, 60);
        expect(userFocus.hasPrimaryFocus, isTrue);

        if (const bool.fromEnvironment('CAPTURE_SEASON_TABS') &&
            initialGroupId == 's12') {
          final boundary = boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('build/season-tabs-${size.width.toInt()}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }

        final horizontal = tester
            .widget<SingleChildScrollView>(
              find
                  .descendant(
                      of: find.byType(DetailEpisodeBrowser),
                      matching: find.byType(SingleChildScrollView))
                  .first,
            )
            .controller!;
        horizontal.jumpTo(400);
        await tester.pumpAndSettle();
        selected.value = 's11';
        await tester.pumpAndSettle();
        expect(horizontal.offset, 400);
        expect(pageScroll.offset, 60);
        expect(userFocus.hasPrimaryFocus, isTrue);

        // Resizing must preserve the user's scroll rather than center selection.
        await tester.pumpAndSettle();
        await tester.binding.setSurfaceSize(Size(size.width + 20, size.height));
        await tester.pumpAndSettle();
        expect(horizontal.offset, 400);

        horizontal.jumpTo(0);
        selected.value = 's0';
        await tester.pumpAndSettle();
        expect(horizontal.offset, 0);
        selected.value = 's23';
        await tester.pumpAndSettle();
        expect(horizontal.offset, 0);
        expect(pageScroll.offset, 60);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
