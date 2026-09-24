import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/app/theme/app_theme.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/search/data/search_preferences_repository.dart';
import 'package:starflow/features/search/data/search_repository.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/search/domain/favorite_sync_document.dart';
import 'package:starflow/features/search/presentation/search_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  for (final mode in [
    (name: 'mobile', tv: false, size: const Size(390, 844), scale: 1.0),
    (name: 'large text', tv: false, size: const Size(390, 844), scale: 2.0),
    (name: 'desktop', tv: false, size: const Size(1280, 900), scale: 1.0),
    (name: 'TV', tv: true, size: const Size(1280, 900), scale: 1.0),
  ]) {
    testWidgets('resolution and cloud filters combine in ${mode.name}',
        (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      tester.view.physicalSize = mode.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = _Repository([
        _result('a', '影片甲 2160p', 'quark'),
        _result('b', '影片乙 1080P', 'baidu'),
        _result('c', '影片丙', 'baidu'),
        _result('d', '影片丁 4K / 1080P', 'baidu'),
        _result('local', '本地影片 8K', '', local: true),
      ]);
      await tester.pumpWidget(_app(repository, tv: mode.tv, scale: mode.scale));
      await tester.pumpAndSettle();

      Future<void> select(String key) async {
        final chip = find.byKey(ValueKey(key));
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        if (mode.tv) {
          final action = tester.widget<TvFocusableAction>(find.descendant(
              of: chip, matching: find.byType(TvFocusableAction)));
          action.focusNode!.requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(chip);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      void count(int value) =>
          expect(find.textContaining('结果 $value 条'), findsOneWidget);

      count(5);
      expect(find.text('搜索来源'), findsOneWidget);
      expect(find.text('清晰度'), findsOneWidget);
      expect(find.byKey(const ValueKey('search-resolution:ultra8k')),
          findsNothing);
      await select('search-resolution:ultra4k');
      count(2);
      expect(find.text('本地影片 8K'), findsNothing);
      await select('search-cloud-type:baidu');
      count(1);
      await select('search-resolution:fullHd');
      count(2);
      await select('search-cloud-type:quark');
      count(0);
      expect(find.text('当前筛选条件下暂无结果。'), findsOneWidget);
      final clear = find.byTooltip('清除结果筛选');
      await tester.ensureVisible(clear);
      await tester.pumpAndSettle();
      if (mode.tv) {
        final action = tester.widget<TvFocusableAction>(find.descendant(
            of: clear, matching: find.byType(TvFocusableAction)));
        action.focusNode!.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      } else {
        await tester.tap(clear);
      }
      await tester.pumpAndSettle();
      count(5);
      expect(repository.calls, 1);
      expect(find.text('搜索来源'), findsOneWidget);
      await select('search-resolution:fullHd');
      await select('search-cloud-type:quark');
      count(0);
      // Empty intersections keep both filter groups available for recovery.
      await select('search-cloud-type:quark');
      count(2);
      await select('search-resolution:fullHd');
      count(5);
      await select('search-resolution:unknown');
      count(1);
      expect(repository.calls, 1);

      // A new request clears the selection, even with the same result objects.
      await tester.pumpWidget(
          _app(repository, tv: mode.tv, scale: mode.scale, query: '再次搜索'));
      await tester.pumpAndSettle();
      count(5);
      expect(repository.calls, 2);

      repository.items = [_result('new', '新影片 720P', 'baidu')];
      await tester.pumpWidget(
          _app(repository, tv: mode.tv, scale: mode.scale, query: '另一部电影'));
      await tester.pumpAndSettle();
      count(1);
      expect(find.byKey(const ValueKey('search-resolution:unknown')),
          findsNothing);
      expect(
          tester
              .widget<StarflowChipButton>(
                  find.byKey(const ValueKey('search-resolution:hd')))
              .selected,
          isFalse);
      expect(repository.calls, 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('many filter choices stay compact in ${mode.name}',
        (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      tester.view.physicalSize = mode.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const labels = ['8K', '4K', '2K', '1080P', '720P', '480P', ''];
      final repository = _Repository([
        for (var index = 0; index < SearchCloudType.values.length; index++)
          _result('item$index', '影片 $index ${labels[index % labels.length]}',
              SearchCloudType.values[index].code),
      ]);
      final boundary = GlobalKey();
      final output = Platform.environment['STARFLOW_LAYOUT_SCREENSHOTS'];
      if (output != null) {
        await tester.runAsync(() async {
          final font = FontLoader('SearchReview');
          font.addFont(File('/System/Library/Fonts/STHeiti Light.ttc')
              .readAsBytes()
              .then(ByteData.sublistView));
          await font.load();
          final icons = FontLoader('MaterialIcons');
          icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
        });
      }
      await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: _app(repository,
            tv: mode.tv, scale: mode.scale, review: output != null),
      ));
      await tester.pumpAndSettle();
      if (mode.size.width < 600) {
        for (final group in ['sources', 'cloud-types', 'resolutions']) {
          final row = find.byKey(PageStorageKey('search-filter:$group'));
          expect(tester.getSize(row).height,
              StarflowChipButton.minimumHeight(tester.element(row)) + 12);
        }
        final row =
            find.byKey(const PageStorageKey('search-filter:resolutions'));
        final first = find.byKey(const ValueKey('search-resolution:ultra8k'));
        final last = find.byKey(const ValueKey('search-resolution:unknown'));
        expect(tester.getCenter(first).dy, tester.getCenter(last).dy);
        await tester.ensureVisible(last);
        await tester.pumpAndSettle();
        expect(tester.getRect(row).contains(tester.getCenter(last)), isTrue);
        await tester.tap(last);
        await tester.pumpAndSettle();
        expect(find.textContaining('结果 1 条'), findsOneWidget);
      } else {
        final sourceX = tester.getTopLeft(find.text('搜索来源')).dx;
        expect(tester.getTopLeft(find.text('网盘类型')).dx, sourceX);
        expect(tester.getTopLeft(find.text('清晰度')).dx, sourceX);
      }
      expect(tester.takeException(), isNull);
      if (output != null) {
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          await Directory(output).create(recursive: true);
          await File('$output/search-filters-${mode.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        });
      }
    });
  }

  testWidgets('later batches retain the selected resolution', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final later = Completer<SearchFetchResult>();
    final repository = _Repository([_result('first', '先到 4K', 'baidu')])
      ..later = later.future;
    await tester.pumpWidget(_app(repository, secondProvider: true));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('search-resolution:ultra4k')));
    await tester.pump();
    later.complete(SearchFetchResult(items: [
      _result('later4k', '后到 2160p', 'baidu'),
      _result('laterHd', '后到 1080P', 'baidu'),
    ], filteredCount: 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('结果 2 条'), findsOneWidget);
    expect(find.text('后到 1080P'), findsNothing);
    expect(repository.calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'local-only searches and favorites do not show resolution filters',
      (tester) async {
    final favorite = _result('favorite', '已收藏 4K', 'baidu');
    SharedPreferences.setMockInitialValues({
      SearchPreferencesRepository.favoriteResultsPreferenceKey:
          FavoriteSyncDocument()
              .setFavorite(searchResultFavoriteKey(favorite), favorite)
              .encode(),
    });
    final preferences = SearchPreferencesRepository(
      preferences:
          SharedPreferencesStore(await SharedPreferences.getInstance()),
    );
    addTearDown(preferences.dispose);
    final repository =
        _Repository([_result('local', '本地影片 8K', '', local: true)]);
    await tester.pumpWidget(_app(repository, preferences: preferences));
    await tester.pumpAndSettle();
    expect(find.text('清晰度'), findsNothing);
    await tester.pumpWidget(
        _app(repository, favorites: true, preferences: preferences));
    await tester.pumpAndSettle();
    expect(find.text('已收藏 4K'), findsOneWidget);
    expect(find.text('清晰度'), findsNothing);
    expect(repository.calls, 1);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(_Repository repository,
        {bool tv = false,
        double scale = 1,
        String query = '电影',
        bool favorites = false,
        bool review = false,
        SearchPreferencesRepository? preferences,
        bool secondProvider = false}) =>
    ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWith((ref) => tv),
        searchRepositoryProvider.overrideWithValue(repository),
        if (preferences != null)
          searchPreferencesRepositoryProvider.overrideWithValue(preferences),
        appSettingsProvider.overrideWithValue(AppSettings(
          mediaSources: const [],
          homeModules: const [],
          doubanAccount: const DoubanAccountConfig(enabled: false),
          searchProviders: [
            const SearchProviderConfig(
              id: 'first',
              name: '搜索服务',
              kind: SearchProviderKind.panSou,
              endpoint: 'https://example.test',
              enabled: true,
            ),
            if (secondProvider)
              const SearchProviderConfig(
                id: 'second',
                name: '另一服务',
                kind: SearchProviderKind.cloudSaver,
                endpoint: 'https://second.example.test',
                enabled: true,
              ),
          ],
        )),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: review
            ? AppTheme.dark().copyWith(
                textTheme:
                    AppTheme.dark().textTheme.apply(fontFamily: 'SearchReview'))
            : null,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: SearchPage(
          key: ValueKey(favorites),
          initialQuery: favorites ? null : query,
          favoritesOnly: favorites,
        ),
      ),
    );

class _Repository implements SearchRepository {
  _Repository(this.items);

  List<SearchResult> items;
  Future<SearchFetchResult>? later;
  int calls = 0;

  @override
  Future<SearchFetchResult> searchOnline(String query,
      {required SearchProviderConfig provider}) async {
    calls++;
    if (provider.id == 'second') return later!;
    return SearchFetchResult(items: items, filteredCount: 0);
  }

  @override
  Future<SearchFetchResult> searchLocal(String query,
          {String? sourceId, String? sectionId, int limit = 60}) async =>
      SearchFetchResult(items: const [], filteredCount: 0);
}

SearchResult _result(String id, String title, String cloudType,
        {bool local = false}) =>
    SearchResult(
      id: id,
      title: title,
      posterUrl: '',
      providerId: 'first',
      providerName: '搜索服务',
      quality: '',
      sizeLabel: '',
      seeders: 0,
      summary: '',
      resourceUrl: 'https://example.test/$id',
      cloudType: cloudType,
      detailTarget: local ? MediaDetailTarget.fromJson({'title': title}) : null,
    );
