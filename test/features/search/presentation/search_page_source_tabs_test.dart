import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/data/search_repository.dart';
import 'package:starflow/features/search/data/search_preferences_repository.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/search/presentation/search_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  for (final mode in [
    (name: 'mobile', television: false, size: const Size(390, 844)),
    (name: 'desktop', television: false, size: const Size(1280, 900)),
    (name: 'TV', television: true, size: const Size(1280, 900)),
  ]) {
    testWidgets('recent searches stay on one scrollable row in ${mode.name}',
        (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      tester.view.physicalSize = mode.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final queries = List.generate(8,
          (index) => '历史电影 $index ${List.filled(5, '完整搜索关键词').join()}');
      final preferences = SearchPreferencesRepository(
        preferences: _MemoryAppPreferencesStore(recentQueries: queries),
      );
      addTearDown(preferences.dispose);
      final repository = _RecordingSearchRepository();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => mode.television),
          searchRepositoryProvider.overrideWithValue(repository),
          searchPreferencesRepositoryProvider.overrideWithValue(preferences),
          appSettingsProvider.overrideWithValue(_settings),
        ],
        child: const MaterialApp(home: SearchPage()),
      ));
      await tester.pumpAndSettle();

      final history = find.byKey(
          const PageStorageKey<String>('search-recent-queries'));
      final scrollable = tester.state<ScrollableState>(find.descendant(
        of: history,
        matching: find.byType(Scrollable),
      ));
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      final y = tester.getCenter(find.text(queries.first)).dy;
      for (final query in queries) {
        expect(tester.getCenter(find.text(query)).dy, closeTo(y, 0.1));
      }
      final originalHeight = tester.getSize(history).height;
      final lastQuery = find.text(queries.last);
      if (mode.television) {
        final firstAction = tester.widget<TvFocusableAction>(find.ancestor(
          of: find.text(queries.first),
          matching: find.byType(TvFocusableAction),
        ));
        firstAction.focusNode!.requestFocus();
        await tester.pumpAndSettle();
        for (var index = 1; index < queries.length; index++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
        }
        final lastAction = tester.widget<TvFocusableAction>(find.ancestor(
          of: lastQuery,
          matching: find.byType(TvFocusableAction),
        ));
        expect(lastAction.focusNode!.hasFocus, isTrue);
      } else {
        for (var attempt = 0;
            attempt < 16 &&
                scrollable.position.pixels < scrollable.position.maxScrollExtent;
            attempt++) {
          await tester.drag(history, Offset(-mode.size.width * 0.7, 0),
              kind: mode.name == 'desktop'
                  ? PointerDeviceKind.mouse
                  : PointerDeviceKind.touch);
          await tester.pumpAndSettle();
        }
      }
      expect(scrollable.position.pixels, greaterThan(0));
      expect(tester.getRect(history).contains(tester.getCenter(lastQuery)), isTrue);
      expect(tester.getSize(history).height, originalHeight);
      if (mode.television) {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      } else {
        await tester.tap(lastQuery);
      }
      await tester.pumpAndSettle();
      expect(repository.onlineQueries, [queries.last, queries.last]);
      expect((await preferences.loadRecentQueries()).first, queries.last);
      expect(tester.takeException(), isNull);
    });

    testWidgets('recent searches display and rerun in ${mode.name}',
        (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      tester.view.physicalSize = mode.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final preferences = SearchPreferencesRepository(
        preferences: _MemoryAppPreferencesStore(
          recentQueries: List.generate(9, (index) => '历史电影 $index'),
        ),
      );
      addTearDown(preferences.dispose);
      final repository = _RecordingSearchRepository();

      await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => mode.television),
          searchRepositoryProvider.overrideWithValue(repository),
          searchPreferencesRepositoryProvider.overrideWithValue(preferences),
          appSettingsProvider.overrideWithValue(_settings),
        ],
        child: const MaterialApp(home: SearchPage()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('最近搜索'), findsOneWidget);
      for (var index = 0; index < 8; index++) {
        expect(find.text('历史电影 $index'), findsOneWidget);
      }
      expect(find.text('历史电影 8'), findsNothing);
      expect(repository.onlineQueries, isEmpty);

      final recentQuery = find.text('历史电影 1');
      if (mode.television) {
        final action = tester.widget<TvFocusableAction>(find.ancestor(
          of: recentQuery,
          matching: find.byType(TvFocusableAction),
        ));
        action.focusNode!.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      } else {
        await tester.tap(recentQuery);
      }
      await tester.pumpAndSettle();

      expect(repository.onlineProviderIds, ['source-a', 'source-b']);
      expect(repository.onlineQueries, ['历史电影 1', '历史电影 1']);
      expect(await preferences.loadRecentQueries(), [
        '历史电影 1',
        '历史电影 0',
        for (var index = 2; index < 8; index++) '历史电影 $index',
      ]);
      if (!mode.television) {
        expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
            '历史电影 1');
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final television in [false, true]) {
    testWidgets('cloud type filters results without searching again TV=$television',
        (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final resultsReady = Completer<void>();
      final repository = _RecordingSearchRepository(
        resultsReady: resultsReady.future,
        items: [
          _result('quark', 'https://pan.quark.cn/s/example', 'baidu'),
          _result('baidu', 'https://example.com/share', 'baidu'),
          _result('other', 'https://example.com/other', ''),
        ],
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => television),
          searchRepositoryProvider.overrideWithValue(repository),
          appSettingsProvider.overrideWithValue(_settings),
        ],
        child: const MaterialApp(home: SearchPage(initialQuery: '电影')),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(repository.onlineProviderIds, ['source-a', 'source-b']);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('网盘类型'), findsNothing);
      expect(find.text('全部类型'), findsNothing);
      resultsReady.complete();
      await tester.pumpAndSettle();
      final requests = repository.onlineProviderIds.length;
      expect(find.text('网盘类型'), findsOneWidget);
      expect(find.textContaining('结果 3 条'), findsOneWidget);
      expect(find.text('阿里云盘'), findsNothing);
      expect(find.text('UC 网盘'), findsNothing);
      expect(find.text('115 网盘'), findsNothing);
      expect(find.text('全部类型'), findsNothing);

      Future<void> selectType(String label) async {
        if (television) {
          final action = tester.widget<TvFocusableAction>(find.ancestor(
            of: find.text(label),
            matching: find.byType(TvFocusableAction),
          ));
          action.focusNode!.requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(find.text(label));
        }
      }

      await selectType('夸克网盘');
      await tester.pumpAndSettle();
      expect(find.textContaining('结果 1 条'), findsOneWidget);
      expect(find.text('资源 quark'), findsOneWidget);
      expect(find.text('资源 baidu'), findsNothing);

      await selectType('百度网盘');
      await tester.pumpAndSettle();
      expect(find.text('资源 baidu'), findsOneWidget);
      expect(find.text('资源 quark'), findsNothing);

      await selectType('百度网盘');
      await tester.pumpAndSettle();
      expect(find.textContaining('结果 3 条'), findsOneWidget);
      expect(find.text('全部类型'), findsNothing);
      expect(repository.onlineProviderIds.length, requests);

      await selectType('夸克网盘');
      await tester.pumpAndSettle();
      await selectType('来源 B');
      await tester.pumpAndSettle();
      expect(find.text('夸克网盘'), findsNothing);
      expect(find.text('百度网盘'), findsOneWidget);
      expect(find.textContaining('结果 3 条'), findsOneWidget);
    });
  }

  testWidgets(
    'settings choose visible source tabs and selected tabs drive search',
    (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      final repository = _RecordingSearchRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isTelevisionProvider.overrideWith((ref) => false),
            searchRepositoryProvider.overrideWithValue(repository),
            appSettingsProvider.overrideWithValue(_settings),
          ],
          child: const MaterialApp(home: SearchPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('来源 A'), findsOneWidget);
      expect(find.text('来源 B'), findsOneWidget);
      expect(find.text('设置未展示来源'), findsNothing);
      expect(find.text('最近搜索'), findsNothing);
      expect(find.text('网盘类型'), findsNothing);
      expect(find.text('全部类型'), findsNothing);

      await tester.tap(find.text('来源 A'));
      await tester.tap(find.text('来源 B'));
      await tester.enterText(find.byType(TextField), '测试电影');
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();

      expect(repository.onlineProviderIds, ['source-a', 'source-b']);
      expect(find.text('网盘类型'), findsNothing);
      expect(find.text('全部类型'), findsNothing);

      repository.onlineProviderIds.clear();
      await tester.tap(find.text('来源 A'));
      await tester.pumpAndSettle();

      expect(repository.onlineProviderIds, ['source-b']);
    },
  );

  testWidgets('hidden saved tabs fall back to all visible tabs',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final preferencesRepository = SearchPreferencesRepository(
      preferences: _MemoryAppPreferencesStore(
        selectedTargetIds: const ['provider:hidden-source'],
      ),
    );
    final repository = _RecordingSearchRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => false),
          searchRepositoryProvider.overrideWithValue(repository),
          searchPreferencesRepositoryProvider.overrideWithValue(
            preferencesRepository,
          ),
          appSettingsProvider.overrideWithValue(_settings),
        ],
        child: const MaterialApp(home: SearchPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '测试电影');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();

    expect(repository.onlineProviderIds, ['source-a', 'source-b']);
  });

  testWidgets('detail entry auto-search waits for saved source tabs',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final preferencesRepository = SearchPreferencesRepository(
      preferences: _MemoryAppPreferencesStore(
        selectedTargetIds: const ['provider:source-b'],
      ),
    );
    final repository = _RecordingSearchRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => false),
          searchRepositoryProvider.overrideWithValue(repository),
          searchPreferencesRepositoryProvider.overrideWithValue(
            preferencesRepository,
          ),
          appSettingsProvider.overrideWithValue(_settings),
        ],
        child: const MaterialApp(
          home: SearchPage(
            initialQuery: '详情页电影',
            showBackButton: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.onlineProviderIds, ['source-b']);
  });
}

const _settings = AppSettings(
  mediaSources: <MediaSourceConfig>[],
  searchProviders: <SearchProviderConfig>[
    SearchProviderConfig(
      id: 'source-a',
      name: '来源 A',
      kind: SearchProviderKind.panSou,
      endpoint: 'https://a.example.com',
      enabled: true,
      allowedCloudTypes: ['quark'],
    ),
    SearchProviderConfig(
      id: 'source-b',
      name: '来源 B',
      kind: SearchProviderKind.panSou,
      endpoint: 'https://b.example.com',
      enabled: true,
      allowedCloudTypes: ['baidu', '115'],
    ),
    SearchProviderConfig(
      id: 'hidden-source',
      name: '设置未展示来源',
      kind: SearchProviderKind.panSou,
      endpoint: 'https://hidden.example.com',
      enabled: true,
      allowedCloudTypes: ['aliyun'],
    ),
  ],
  doubanAccount: DoubanAccountConfig(enabled: false),
  homeModules: <HomeModuleConfig>[],
  searchSourceIds: <String>[
    'provider:source-a',
    'provider:source-b',
  ],
);

class _RecordingSearchRepository implements SearchRepository {
  _RecordingSearchRepository({this.items = const [], this.resultsReady});

  final List<SearchResult> items;
  final Future<void>? resultsReady;
  final List<String> onlineProviderIds = <String>[];
  final List<String> onlineQueries = <String>[];

  @override
  Future<SearchFetchResult> searchLocal(
    String query, {
    String? sourceId,
    String? sectionId,
    int limit = 60,
  }) async {
    return SearchFetchResult(items: const [], filteredCount: 0);
  }

  @override
  Future<SearchFetchResult> searchOnline(
    String query, {
    required SearchProviderConfig provider,
  }) async {
    onlineProviderIds.add(provider.id);
    onlineQueries.add(query);
    await resultsReady;
    return SearchFetchResult(items: items, filteredCount: 0);
  }
}

SearchResult _result(String id, String url, String cloudType) => SearchResult(
      id: id,
      title: '资源 $id',
      posterUrl: '',
      providerId: 'source-a',
      providerName: '来源 A',
      quality: '',
      sizeLabel: '',
      seeders: 0,
      summary: '',
      resourceUrl: url,
      cloudType: cloudType,
    );

class _MemoryAppPreferencesStore extends AppPreferencesStore {
  _MemoryAppPreferencesStore({
    List<String> selectedTargetIds = const [],
    List<String> recentQueries = const [],
  }) : _stringLists = <String, List<String>>{
          SearchPreferencesRepository.selectedTargetIdsPreferenceKey:
              selectedTargetIds,
          SearchPreferencesRepository.recentQueriesPreferenceKey: recentQueries,
        };

  final Map<String, List<String>> _stringLists;

  @override
  Future<String?> getString(String key) async => null;

  @override
  Future<List<String>?> getStringList(String key) async => _stringLists[key];

  @override
  Future<void> setStringList(String key, List<String> value) async {
    _stringLists[key] = value;
  }
}
