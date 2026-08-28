import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/data/mock_search_repository.dart';
import 'package:starflow/features/search/data/search_preferences_repository.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/search/presentation/search_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
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

      await tester.tap(find.text('来源 A'));
      await tester.tap(find.text('来源 B'));
      await tester.enterText(find.byType(TextField), '测试电影');
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();

      expect(repository.onlineProviderIds, ['source-a', 'source-b']);

      repository.onlineProviderIds.clear();
      await tester.tap(find.text('来源 A'));
      await tester.pumpAndSettle();

      expect(repository.onlineProviderIds, ['source-b']);
    },
  );

  testWidgets('hidden saved tabs fall back to all visible tabs',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      normalizePreferencesKey(
        SearchPreferencesRepository.selectedTargetIdsPreferenceKey,
      ): <String>['provider:hidden-source'],
    });
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

    await tester.enterText(find.byType(TextField), '测试电影');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();

    expect(repository.onlineProviderIds, ['source-a', 'source-b']);
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
    ),
    SearchProviderConfig(
      id: 'source-b',
      name: '来源 B',
      kind: SearchProviderKind.panSou,
      endpoint: 'https://b.example.com',
      enabled: true,
    ),
    SearchProviderConfig(
      id: 'hidden-source',
      name: '设置未展示来源',
      kind: SearchProviderKind.panSou,
      endpoint: 'https://hidden.example.com',
      enabled: true,
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
  final List<String> onlineProviderIds = <String>[];

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
    return SearchFetchResult(items: const [], filteredCount: 0);
  }
}
