import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/data/online_subtitle_repository.dart';
import 'package:starflow/features/playback/domain/online_subtitle_structured_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/playback/presentation/subtitle_search_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  testWidgets('subtitle search page prefills title without auto searching',
      (tester) async {
    final repository = _FakeOnlineSubtitleRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'onlineSubtitleSources': ['assrt'],
            }),
          ),
          onlineSubtitleRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: SubtitleSearchPage(
            request: const SubtitleSearchRequest(
              query: 'Planet Earth II S01E01',
              title: 'Planet Earth II',
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    final searchField = tester.widget<TextField>(find.byType(TextField));
    expect(searchField.controller?.text, 'Planet Earth II');
    expect(repository.searchQueries, isEmpty);
  });

  testWidgets('subtitle search page prefers explicit initial input text',
      (tester) async {
    final repository = _FakeOnlineSubtitleRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'onlineSubtitleSources': ['assrt'],
            }),
          ),
          onlineSubtitleRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: SubtitleSearchPage(
            request: const SubtitleSearchRequest(
              query: 'Planet Earth II S01E01',
              title: 'Planet Earth II S01E01',
              initialInput: 'Planet Earth II',
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    final searchField = tester.widget<TextField>(find.byType(TextField));
    expect(searchField.controller?.text, 'Planet Earth II');
    expect(repository.searchQueries, isEmpty);
  });

  testWidgets('subtitle search page can narrow selected subtitle sources',
      (tester) async {
    final repository = _FakeOnlineSubtitleRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'onlineSubtitleSources': ['assrt'],
              'opensubtitlesEnabled': true,
              'opensubtitlesUsername': 'tester',
              'opensubtitlesPassword': 'secret',
            }),
          ),
          onlineSubtitleRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: SubtitleSearchPage(
            request: const SubtitleSearchRequest(
              query: 'Planet Earth II S01E01',
              title: 'Planet Earth II',
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('OpenSubtitles'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump();
    await tester.pump();

    expect(
      repository.searchSources.last,
      [OnlineSubtitleSource.assrt],
    );
  });
}

class _FakeOnlineSubtitleRepository implements OnlineSubtitleRepository {
  final List<String> searchQueries = <String>[];
  final List<List<OnlineSubtitleSource>> searchSources =
      <List<OnlineSubtitleSource>>[];

  @override
  Future<SubtitleDownloadResult> download(SubtitleSearchResult result) {
    throw UnimplementedError();
  }

  @override
  Future<List<SubtitleSearchResult>> search(
    String query, {
    List<OnlineSubtitleSource> sources = const [OnlineSubtitleSource.assrt],
    int maxResults = 0,
  }) async {
    searchQueries.add(query);
    searchSources.add(List<OnlineSubtitleSource>.from(sources));
    return const [];
  }

  @override
  Future<List<ValidatedSubtitleCandidate>> searchStructured(
    OnlineSubtitleSearchRequest request, {
    List<OnlineSubtitleSource> sources = const [
      OnlineSubtitleSource.assrt,
      OnlineSubtitleSource.opensubtitles,
      OnlineSubtitleSource.subdl,
    ],
    int maxResults = 0,
    int maxValidated = 0,
  }) async {
    return const [];
  }
}
