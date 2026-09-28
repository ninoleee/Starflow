import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/discovery/domain/douban_browse_models.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/search/presentation/search_hub_page.dart';
import 'package:starflow/features/search/data/search_preferences_repository.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  const settings = AppSettings(
    mediaSources: [],
    searchProviders: [],
    homeModules: [],
    doubanAccount: DoubanAccountConfig(enabled: false),
  );

  testWidgets('saved browse mode opens browse without creating search work',
      (tester) async {
    SharedPreferences.setMockInitialValues({'search.browseMode': 'douban'});
    final preferences = SearchPreferencesRepository();
    await preferences.saveBrowseMode(true);
    addTearDown(preferences.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      searchPreferencesRepositoryProvider.overrideWithValue(preferences),
      appSettingsProvider.overrideWithValue(settings),
      isTelevisionProvider.overrideWith((ref) => false),
    ], child: const MaterialApp(home: SearchHubPage())));
    await tester.pumpAndSettle();
    expect(find.text('豆瓣选片'), findsOneWidget);
    expect(find.textContaining('豆瓣模块已关闭'), findsOneWidget);
    expect(find.text('电影'), findsOneWidget);
    expect(find.text('电视剧'), findsOneWidget);
    expect(find.text('综艺'), findsOneWidget);
    expect(
        tester
            .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
            .showSelectedIcon,
        false);
    expect(
        tester
            .widget<SegmentedButton<DoubanBrowseCategory>>(
                find.byType(SegmentedButton<DoubanBrowseCategory>))
            .showSelectedIcon,
        false);
  });

  testWidgets('explicit query overrides saved browse mode', (tester) async {
    SharedPreferences.setMockInitialValues({'search.browseMode': 'douban'});
    final preferences = SearchPreferencesRepository();
    await preferences.saveBrowseMode(true);
    addTearDown(preferences.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      searchPreferencesRepositoryProvider.overrideWithValue(preferences),
      appSettingsProvider.overrideWithValue(settings),
      isTelevisionProvider.overrideWith((ref) => false),
    ], child: const MaterialApp(home: SearchHubPage(initialQuery: '测试片名'))));
    await tester.pumpAndSettle();
    expect(find.textContaining('豆瓣模块已关闭'), findsNothing);
    expect(find.text('电影'), findsNothing);
    expect(find.text('资源搜索'), findsOneWidget);
  });

  for (final mode in [
    (size: const Size(390, 844), scale: 1.3, tv: false),
    (size: const Size(1280, 720), scale: 1.0, tv: true),
  ]) {
    testWidgets('browse controls fit ${mode.size} at ${mode.scale}x',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = mode.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            appSettingsProvider.overrideWithValue(settings),
            isTelevisionProvider.overrideWith((ref) => mode.tv),
          ],
          child: MaterialApp(
              home: MediaQuery(
            data: MediaQueryData(
                size: mode.size, textScaler: TextScaler.linear(mode.scale)),
            child: const SearchHubPage(),
          ))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('豆瓣选片'));
      await tester.pumpAndSettle();
      expect(find.text('电影'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
