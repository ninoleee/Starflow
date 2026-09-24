import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/search/data/search_preferences_repository.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/search/presentation/search_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  for (final tv in [false, true]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('search chips fit long labels at $scale TV=$tv',
          (tester) async {
        tester.view.physicalSize = Size(tv ? 1280 : 390, tv ? 720 : 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const history = 'A very long recent query with multilingual titles';
        SharedPreferences.setMockInitialValues({
          'search.recentQueries': [history],
        });
        final preferences = SearchPreferencesRepository(
          preferences:
              SharedPreferencesStore(await SharedPreferences.getInstance()),
        );
        addTearDown(preferences.dispose);
        final boundary = GlobalKey();
        await tester.pumpWidget(ProviderScope(
          overrides: [
            isTelevisionProvider.overrideWith((ref) => tv),
            searchPreferencesRepositoryProvider.overrideWithValue(preferences),
            appSettingsProvider.overrideWithValue(const AppSettings(
              mediaSources: [],
              homeModules: [],
              searchProviders: [
                SearchProviderConfig(
                  id: 'long',
                  name: 'A very long translated provider name',
                  kind: SearchProviderKind.panSou,
                  endpoint: 'https://example.test',
                  enabled: true,
                ),
                SearchProviderConfig(
                  id: 'other',
                  name: 'Another provider',
                  kind: SearchProviderKind.panSou,
                  endpoint: 'https://other.example.test',
                  enabled: true,
                ),
              ],
              doubanAccount: DoubanAccountConfig(enabled: false),
            )),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: RepaintBoundary(key: boundary, child: const SearchPage()),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text(history), findsOneWidget);
        expect(tester.getCenter(find.text('最近搜索')).dy,
            closeTo(tester.getCenter(find.text(history)).dy, 0.1));
        expect(tester.getRect(find.text('最近搜索')).right,
            lessThan(tester.getRect(find.text(history)).left));
        final chips = find.byType(StarflowChipButton);
        expect(chips, findsWidgets);
        final sizes = <Size>[];
        for (final element in chips.evaluate()) {
          final chip = find.byWidget(element.widget);
          final label =
              find.descendant(of: chip, matching: find.byType(Text)).first;
          final text = tester.renderObject<RenderParagraph>(label);
          final box = tester.getRect(chip);
          final labelBox = tester.getRect(label);
          final painter = TextPainter(
              text: text.text,
              textDirection: text.textDirection,
              textScaler: text.textScaler,
              maxLines: 1)
            ..layout();
          expect(labelBox.height, greaterThanOrEqualTo(painter.height));
          painter.dispose();
          expect(labelBox.top - box.top, greaterThanOrEqualTo(15));
          expect(box.bottom - labelBox.bottom, greaterThanOrEqualTo(15));
          if (tv || (element.widget as StarflowChipButton).label == history) {
            expect(box.width, lessThanOrEqualTo(tv ? 1280 : 390));
          }
          sizes.add(box.size);
        }
        if (tv) {
          final action = tester.widget<TvFocusableAction>(find.descendant(
              of: chips.first, matching: find.byType(TvFocusableAction)));
          action.focusNode!.requestFocus();
          await tester.pumpAndSettle();
          expect(action.focusNode!.hasPrimaryFocus, isTrue);
          expect(tester.getSize(chips.first), sizes.first);
        }
        expect(tester.takeException(), isNull);
        // Optional host screenshots without checking machine-font goldens in.
        final output = Platform.environment['STARFLOW_LAYOUT_SCREENSHOTS'];
        if (output != null) {
          final render = boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await render.toImage();
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            await Directory(output).create(recursive: true);
            await File('$output/search-$tv-$scale.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          });
        }
      });
    }
  }
}
