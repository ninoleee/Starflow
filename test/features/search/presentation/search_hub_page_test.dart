import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/discovery/data/douban_api_client.dart';
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
    expect(_hubTab('选片'), findsOneWidget);
    expect(find.textContaining('豆瓣模块已关闭'), findsOneWidget);
    expect(find.text('电影'), findsOneWidget);
    expect(find.text('电视剧'), findsOneWidget);
    expect(find.text('综艺'), findsOneWidget);
    expect(
        tester
            .widget<StarflowChipButton>(
                find.widgetWithText(StarflowChipButton, '选片'))
            .selected,
        isTrue);
    expect(
        tester
            .widget<StarflowChipButton>(
                find.widgetWithText(StarflowChipButton, '电影'))
            .selected,
        isTrue);
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
    expect(_hubTab('搜索'), findsOneWidget);
  });

  for (final mode in [
    (size: const Size(390, 844), tv: false, maxWidth: 240.0),
    (size: const Size(1280, 720), tv: true, maxWidth: 320.0),
  ]) {
    testWidgets('mode tabs use compact width on ${mode.size}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = mode.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(overrides: [
        appSettingsProvider.overrideWithValue(settings),
        isTelevisionProvider.overrideWith((ref) => mode.tv),
      ], child: const MaterialApp(home: SearchHubPage())));
      await tester.pumpAndSettle();

      final group = find.byKey(const ValueKey('search-hub-mode-tabs-group'));
      expect(tester.getSize(group).width, mode.maxWidth);
      expect(tester.getCenter(group).dx, closeTo(mode.size.width / 2, 1));
    });
  }

  testWidgets('mode tabs scroll with the page content', (tester) async {
    SharedPreferences.setMockInitialValues({'search.browseMode': 'douban'});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = SearchPreferencesRepository();
    await preferences.saveBrowseMode(true);
    addTearDown(preferences.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      searchPreferencesRepositoryProvider.overrideWithValue(preferences),
      appSettingsProvider.overrideWithValue(const AppSettings(
        mediaSources: [],
        searchProviders: [],
        homeModules: [],
        doubanAccount: DoubanAccountConfig(enabled: true),
      )),
      isTelevisionProvider.overrideWith((ref) => false),
      doubanApiClientProvider.overrideWithValue(DoubanApiClient(MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(jsonEncode({
            'items': [
              for (var index = 0; index < 20; index++)
                {
                  'id': '$index',
                  'title': '作品$index',
                  'type': 'movie',
                  'year': '2024',
                }
            ],
            'total': 20,
          })),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      ))),
    ], child: const MaterialApp(home: SearchHubPage())));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    final tabs = find.byKey(const ValueKey('search-hub-tabs'));
    final initialTop = tester.getTopLeft(tabs).dy;

    await tester.drag(
        find.byType(CustomScrollView).first, const Offset(0, -320));
    await tester.pumpAndSettle();
    expect(tabs, findsNothing);

    await tester.drag(
        find.byType(CustomScrollView).first, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(tabs, findsOneWidget);
    expect(tester.getTopLeft(tabs).dy, greaterThan(initialTop - 120));
  });

  testWidgets('TV back first returns focus to the selected mode tab',
      (tester) async {
    SharedPreferences.setMockInitialValues({'search.browseMode': 'douban'});
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = SearchPreferencesRepository();
    await preferences.saveBrowseMode(true);
    addTearDown(preferences.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      searchPreferencesRepositoryProvider.overrideWithValue(preferences),
      appSettingsProvider.overrideWithValue(const AppSettings(
        mediaSources: [],
        searchProviders: [],
        homeModules: [],
        doubanAccount: DoubanAccountConfig(enabled: true),
      )),
      isTelevisionProvider.overrideWith((ref) => true),
      doubanApiClientProvider.overrideWithValue(DoubanApiClient(MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(jsonEncode({
            'items': [
              for (var index = 0; index < 20; index++)
                {
                  'id': '$index',
                  'title': '作品$index',
                  'type': 'movie',
                  'year': '2024',
                }
            ],
            'total': 40,
          })),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      ))),
    ], child: const MaterialApp(home: SearchHubPage())));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    final bottomNext = find.byKey(const ValueKey('movie:19'));
    await tester.dragUntilVisible(
      bottomNext,
      find.byType(CustomScrollView).first,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    final bottomFocus = tester.widget<MediaPosterTile>(bottomNext).focusNode!;
    bottomFocus.requestFocus();
    await tester.pumpAndSettle();
    expect(bottomFocus.hasPrimaryFocus, isTrue);
    expect(find.byKey(const ValueKey('search-hub-tabs')), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final selectedTab = _hubTab('选片');
    expect(selectedTab, findsOneWidget);
    final tabFocus = Focus.of(tester.element(selectedTab));
    expect(tabFocus.hasPrimaryFocus, isTrue);
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
      await tester.tap(_hubTab('选片'));
      await tester.pumpAndSettle();
      expect(find.text('电影'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Finder _hubTab(String label) => find.text(label);
