import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/data/mock_search_repository.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/search/presentation/search_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('detail search page requests TV focus on query input',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(
            const AppSettings(
              mediaSources: <MediaSourceConfig>[],
              searchProviders: <SearchProviderConfig>[],
              doubanAccount: DoubanAccountConfig(enabled: false),
              homeModules: <HomeModuleConfig>[],
            ),
          ),
        ],
        child: const MaterialApp(
          home: SearchPage(
            initialQuery: '测试电影',
            showBackButton: true,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'search-query');
  });

  testWidgets('detail search route push requests TV focus on query input',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(
            const AppSettings(
              mediaSources: <MediaSourceConfig>[],
              searchProviders: <SearchProviderConfig>[],
              doubanAccount: DoubanAccountConfig(enabled: false),
              homeModules: <HomeModuleConfig>[],
            ),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const SearchPage(
                            initialQuery: '测试电影',
                            showBackButton: true,
                          ),
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'search-query');
  });

  testWidgets('TV query dialog moves down out of its text field',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(
            const AppSettings(
              mediaSources: <MediaSourceConfig>[],
              searchProviders: <SearchProviderConfig>[],
              doubanAccount: DoubanAccountConfig(enabled: false),
              homeModules: <HomeModuleConfig>[],
            ),
          ),
        ],
        child: const MaterialApp(
          home: SearchPage(
            initialQuery: '测试电影',
            showBackButton: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'search-query-dialog-field',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      isNot('search-query-dialog-field'),
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      anyOf('search-query-dialog-cancel', 'search-query-dialog-submit'),
    );
  });

  testWidgets('detail search restores TV focus after online result update',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final repository = _PendingSearchRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          searchRepositoryProvider.overrideWithValue(repository),
          appSettingsProvider.overrideWithValue(
            const AppSettings(
              mediaSources: <MediaSourceConfig>[],
              searchProviders: <SearchProviderConfig>[
                SearchProviderConfig(
                  id: 'online',
                  name: 'Online',
                  kind: SearchProviderKind.panSou,
                  endpoint: 'https://example.com',
                  enabled: true,
                ),
              ],
              doubanAccount: DoubanAccountConfig(enabled: false),
              homeModules: <HomeModuleConfig>[],
            ),
          ),
        ],
        child: const MaterialApp(
          home: SearchPage(
            initialQuery: '测试电影',
            showBackButton: true,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'search-query');

    for (var i = 0; i < 10 && !repository.onlineStarted.isCompleted; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(repository.onlineStarted.isCompleted, isTrue);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    repository.onlineResult.complete(
      SearchFetchResult(
        filteredCount: 0,
        items: const [
          SearchResult(
            id: 'online-1',
            title: '测试电影 4K',
            posterUrl: '',
            providerId: 'online',
            providerName: 'Online',
            quality: '4K',
            sizeLabel: '10GB',
            seeders: 0,
            summary: 'online result',
            resourceUrl: 'https://example.com/share/1',
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('测试电影 4K'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'search-query');
  });

  testWidgets('standalone favorites page hides search controls and tabs',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => false),
          appSettingsProvider.overrideWithValue(
            const AppSettings(
              mediaSources: <MediaSourceConfig>[],
              searchProviders: <SearchProviderConfig>[],
              doubanAccount: DoubanAccountConfig(enabled: false),
              homeModules: <HomeModuleConfig>[],
            ),
          ),
        ],
        child: const MaterialApp(
          home: SearchPage(favoritesOnly: true),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('收藏'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('搜索'), findsNothing);
    expect(find.text('全部'), findsNothing);
  });
}

class _PendingSearchRepository implements SearchRepository {
  final Completer<void> onlineStarted = Completer<void>();
  final Completer<SearchFetchResult> onlineResult =
      Completer<SearchFetchResult>();

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
  }) {
    if (!onlineStarted.isCompleted) {
      onlineStarted.complete();
    }
    return onlineResult.future;
  }
}
