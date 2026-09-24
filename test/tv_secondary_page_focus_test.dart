import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/person_credits_page.dart';
import 'package:starflow/features/discovery/data/discovery_repository.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/home/presentation/home_module_collection_page.dart';
import 'package:starflow/features/library/application/library_cached_items.dart';
import 'package:starflow/features/library/domain/library_collection_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/presentation/library_collection_page.dart';
import 'package:starflow/features/library/presentation/library_resource_deletion.dart';
import 'package:starflow/features/library/presentation/widgets/library_paged_grid.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  testWidgets('TV resource deletion initially focuses cancel', (tester) async {
    final item = MediaItem(
      id: 'https://example.com/movie.mkv',
      title: 'Movie',
      overview: '',
      posterUrl: '',
      year: 2026,
      durationLabel: '',
      genres: const [],
      sourceId: 'nas',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
      streamUrl: '',
      addedAt: DateTime(2026),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [isTelevisionProvider.overrideWith((ref) => true)],
      child: MaterialApp(
          home: Scaffold(
              body: Consumer(
        builder: (context, ref, _) => TextButton(
          onPressed: () => confirmLibraryResourceDeletion(context, ref, item),
          child: const Text('Delete'),
        ),
      ))),
    ));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    final cancel = find.widgetWithText(StarflowButton, '取消');
    final focus = tester
        .widget<FocusableActionDetector>(find.descendant(
          of: cancel,
          matching: find.byType(FocusableActionDetector),
        ))
        .focusNode!;
    expect(focus.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  for (final fail in [false, true]) {
    for (final library in [false, true]) {
      testWidgets(
          'TV collection has focus during loading and empty/error: '
          'library=$library fail=$fail', (tester) async {
        final discovery = _Discovery();
        final pending = Completer<LibraryVisiblePageItemsResult>();
        await tester.pumpWidget(ProviderScope(
          overrides: [
            isTelevisionProvider.overrideWith((ref) => true),
            appSettingsProvider.overrideWithValue(AppSettings.fromJson({})),
            discoveryRepositoryProvider.overrideWithValue(discovery),
            libraryCollectionVisiblePageItemsProvider
                .overrideWith((ref, request) => pending.future),
          ],
          child: MaterialApp(
            home: library
                ? const LibraryCollectionPage(
                    target: LibraryCollectionTarget(
                    title: 'Collection',
                    sourceId: 'nas',
                    sourceName: 'NAS',
                    sourceKind: MediaSourceKind.nas,
                  ))
                : const HomeModuleCollectionPage(
                    module: HomeModuleConfig(
                    id: 'list',
                    type: HomeModuleType.doubanList,
                    title: 'Collection',
                    enabled: true,
                  )),
          ),
        ));
        await tester.pump();
        await tester.pump();
        final label =
            library ? 'library-collection-header' : 'home-module-header';
        expect(FocusManager.instance.primaryFocus?.debugLabel, label);
        if (library) {
          if (fail) {
            pending.completeError(StateError('unavailable'));
          } else {
            pending.complete(
                const LibraryVisiblePageItemsResult(totalItems: 0, items: []));
          }
        } else {
          if (fail) {
            discovery.pending.completeError(StateError('unavailable'));
          } else {
            discovery.pending.complete([]);
          }
        }
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, label);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('TV person page has focus even without configured metadata',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWith((ref) => true),
        appSettingsProvider.overrideWithValue(AppSettings.fromJson({})),
      ],
      child: const MaterialApp(
          home: PersonCreditsPage(
        target: PersonCreditsPageTarget(
          person: MediaPersonProfile(name: 'Person'),
          role: PersonCreditsRole.actor,
        ),
      )),
    ));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        'person-credits-header');
    expect(tester.takeException(), isNull);
  });

  testWidgets('company credits page uses company work labels', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appSettingsProvider.overrideWithValue(AppSettings.fromJson({})),
      ],
      child: const MaterialApp(
        home: PersonCreditsPage(
          target: PersonCreditsPageTarget(
            person: MediaPersonProfile(name: 'Company A'),
            role: PersonCreditsRole.company,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Company A'), findsOneWidget);
    expect(find.text('公司作品'), findsOneWidget);
    expect(find.byIcon(Icons.business_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('company credits page requests and displays TMDB pages',
      (tester) async {
    final client = _PagedTmdbMetadataClient();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWith((ref) => true),
        appSettingsProvider.overrideWithValue(AppSettings.fromJson({
          'tmdbMetadataMatchEnabled': true,
          'tmdbReadAccessToken': 'tmdb-token',
        })),
        tmdbMetadataClientProvider.overrideWithValue(client),
      ],
      child: const MaterialApp(
        home: PersonCreditsPage(
          target: PersonCreditsPageTarget(
            person: MediaPersonProfile(name: 'Company A', tmdbId: 33),
            role: PersonCreditsRole.company,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('第 1 / 2 页'), findsWidgets);
    expect(find.text('Page 1 Movie'), findsOneWidget);
    final nextButton = find.byWidgetPredicate(
      (widget) =>
          widget is TvFocusableAction &&
          widget.focusId == 'person-credits:pager:top:next',
    );
    expect(nextButton, findsOneWidget);

    final nextFocusDetector = find.descendant(
      of: nextButton,
      matching: find.byType(FocusableActionDetector),
    );
    tester
        .widget<FocusableActionDetector>(nextFocusDetector)
        .focusNode
        ?.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'person-credits:first-item',
    );

    await tester.tap(nextButton);
    await tester.pumpAndSettle();

    expect(client.requestedPages, [1, 2]);
    expect(find.text('第 2 / 2 页'), findsWidgets);
    expect(find.text('Page 2 Series'), findsOneWidget);

    await tester.tap(find.text('最旧'));
    await tester.pumpAndSettle();

    expect(client.requestedPages, [1, 2, 1]);
    expect(
      client.requestedSorts.last,
      TmdbCompanyCreditsSort.oldest,
    );
    expect(find.text('第 1 / 2 页'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('person credits page paginates locally without refetching',
      (tester) async {
    final client = _PagedTmdbMetadataClient();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWith((ref) => true),
        appSettingsProvider.overrideWithValue(AppSettings.fromJson({
          'tmdbMetadataMatchEnabled': true,
          'tmdbReadAccessToken': 'tmdb-token',
        })),
        tmdbMetadataClientProvider.overrideWithValue(client),
      ],
      child: const MaterialApp(
        home: PersonCreditsPage(
          target: PersonCreditsPageTarget(
            person: MediaPersonProfile(name: 'Actor A', tmdbId: 99),
            role: PersonCreditsRole.actor,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(client.personCreditsRequests, 1);
    expect(find.text('演员作品分页'), findsOneWidget);
    expect(find.text('第 1 / 2 页'), findsWidgets);
    expect(find.text('Person Work 41'), findsOneWidget);

    final nextButton = find.byWidgetPredicate(
      (widget) =>
          widget is TvFocusableAction &&
          widget.focusId == 'person-credits:pager:top:next',
    );
    await tester.tap(nextButton);
    await tester.pumpAndSettle();

    expect(client.personCreditsRequests, 1);
    expect(find.text('第 2 / 2 页'), findsWidgets);
    expect(find.text('Person Work 1'), findsOneWidget);

    await tester.tap(find.text('最旧'));
    await tester.pumpAndSettle();

    expect(client.personCreditsRequests, 1);
    expect(find.text('第 1 / 2 页'), findsWidgets);
    expect(find.text('Person Work 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV library pager retains focus when reaching the final page',
      (tester) async {
    final page = ValueNotifier(0);
    addTearDown(page.dispose);
    var changes = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [isTelevisionProvider.overrideWith((ref) => true)],
      child: MaterialApp(
          home: Scaffold(
              body: ValueListenableBuilder<int>(
        valueListenable: page,
        builder: (_, current, child) => LibraryPagedGrid(
          pageItems: const [],
          totalItems: 48,
          currentPage: current,
          isTelevision: true,
          onPageChanged: (next) {
            changes++;
            page.value = next;
          },
        ),
      ))),
    ));
    await tester.pumpAndSettle();
    final action = find.byWidgetPredicate(
        (w) => w is TvFocusableAction && w.focusId == 'library:pager:top:next');
    final node = tester
        .widget<FocusableActionDetector>(find.descendant(
          of: action,
          matching: find.byType(FocusableActionDetector),
        ))
        .focusNode!;
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(page.value, 1);
    expect(node.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(changes, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(node.hasPrimaryFocus, isFalse);
    expect(hasActionableTvFocus(), isTrue);
  });
}

class _PagedTmdbMetadataClient extends TmdbMetadataClient {
  _PagedTmdbMetadataClient()
      : super(MockClient((request) async => http.Response('{}', 200)));

  final List<int> requestedPages = [];
  final List<TmdbCompanyCreditsSort> requestedSorts = [];
  int personCreditsRequests = 0;

  @override
  Future<List<TmdbPersonCredit>> fetchPersonCredits({
    required String name,
    required String avatarUrl,
    required TmdbPersonCreditsRole role,
    required String readAccessToken,
    int limit = 60,
  }) async {
    personCreditsRequests++;
    return List.generate(
      41,
      (index) => TmdbPersonCredit(
        tmdbId: index + 1,
        isSeries: false,
        title: 'Person Work ${index + 1}',
        originalTitle: 'Person Work ${index + 1}',
        posterUrl: '',
        backdropUrl: '',
        bannerUrl: '',
        overview: '',
        year: 2000 + index,
        genres: const ['剧情'],
        ratingLabels: const ['TMDB 7.5'],
        subtitle: '电影',
        popularity: (index + 1).toDouble(),
      ),
    );
  }

  @override
  Future<TmdbCompanyCreditsPage> fetchCompanyCreditsPage({
    required int companyId,
    required String readAccessToken,
    int page = 1,
    int limit = 60,
    TmdbCompanyCreditsSort sort = TmdbCompanyCreditsSort.newest,
  }) async {
    requestedPages.add(page);
    requestedSorts.add(sort);
    return TmdbCompanyCreditsPage(
      items: page == 1
          ? const [
              TmdbPersonCredit(
                tmdbId: 1,
                isSeries: false,
                title: 'Page 1 Movie',
                originalTitle: 'Page 1 Movie',
                posterUrl: '',
                backdropUrl: '',
                bannerUrl: '',
                overview: '',
                year: 2026,
                genres: ['剧情'],
                ratingLabels: ['TMDB 8.0'],
                subtitle: '电影',
                popularity: 10,
              ),
            ]
          : const [
              TmdbPersonCredit(
                tmdbId: 2,
                isSeries: true,
                title: 'Page 2 Series',
                originalTitle: 'Page 2 Series',
                posterUrl: '',
                backdropUrl: '',
                bannerUrl: '',
                overview: '',
                year: 2025,
                genres: ['剧情'],
                ratingLabels: ['TMDB 8.1'],
                subtitle: '剧集',
                popularity: 20,
              ),
            ],
      page: page,
      totalPages: 2,
    );
  }
}

class _Discovery implements DiscoveryRepository {
  final pending = Completer<List<DoubanEntry>>();
  @override
  Future<List<DoubanEntry>> fetchEntries(HomeModuleConfig module,
          {int page = 1, int? pageSize}) =>
      pending.future;
  @override
  Future<List<DoubanCarouselEntry>> fetchCarouselItems() async => [];
}
