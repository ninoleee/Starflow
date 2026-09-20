import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/features/playback/data/online_subtitle_repository.dart';
import 'package:starflow/features/playback/domain/online_subtitle_structured_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/playback/domain/subtitle_operation.dart';
import 'package:starflow/features/playback/presentation/subtitle_search_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  testWidgets('successful handoff keeps the accepted download after pop',
      (tester) async {
    final repository = _FakeOnlineSubtitleRepository();
    repository.pendingSearch = Future.value(const [
      ValidatedSubtitleCandidate(
        hit: ProviderSubtitleHit(
            id: 'accepted',
            source: OnlineSubtitleSource.assrt,
            providerLabel: 'ASSRT',
            title: 'ACCEPTED',
            downloadUrl: 'https://example.com/a.srt',
            packageName: 'a.srt',
            packageKind: SubtitlePackageKind.subtitleFile),
        status: SubtitleValidationStatus.skipped,
      )
    ]);
    repository.pendingDownload = Completer<SubtitleDownloadResult>();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => false),
          appSettingsProvider.overrideWithValue(AppSettings.fromJson({
            'onlineSubtitleSources': ['assrt'],
            'assrtToken': 'token',
          })),
          onlineSubtitleRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('Player')))));
    final selected =
        navigator.currentState!.push<SubtitleSearchSelection>(MaterialPageRoute(
            builder: (_) => const SubtitleSearchPage(
                  request: SubtitleSearchRequest(query: 'Film'),
                )));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载并加载'));
    await tester.pump();
    var discarded = 0;
    repository.pendingDownload!.complete(SubtitleDownloadResult(
      cachedPath: '/accepted',
      displayName: 'accepted',
      subtitleFilePath: '/accepted/a.srt',
      discard: () async {
        discarded++;
      },
    ));
    await tester.pumpAndSettle();
    expect((await selected)!.subtitleFilePath, '/accepted/a.srt');
    expect(repository.downloadOperation!.isCancelled, isTrue);
    expect(discarded, 0);
  });

  testWidgets('disposing cancels a download and discards its late result',
      (tester) async {
    final repository = _FakeOnlineSubtitleRepository();
    repository.pendingSearch = Future.value(const [
      ValidatedSubtitleCandidate(
        hit: ProviderSubtitleHit(
            id: 'late',
            source: OnlineSubtitleSource.assrt,
            providerLabel: 'ASSRT',
            title: 'LATE',
            downloadUrl: 'https://example.com/late.srt',
            packageName: 'late.srt',
            packageKind: SubtitlePackageKind.subtitleFile),
        status: SubtitleValidationStatus.skipped,
      )
    ]);
    repository.pendingDownload = Completer<SubtitleDownloadResult>();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => false),
          appSettingsProvider.overrideWithValue(AppSettings.fromJson({
            'onlineSubtitleSources': ['assrt'],
            'assrtToken': 'token',
          })),
          onlineSubtitleRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
            home: SubtitleSearchPage(
          request: SubtitleSearchRequest(query: 'Film'),
        ))));
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载并加载'));
    await tester.pump();
    expect(repository.downloadOperation!.isCancelled, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(repository.downloadOperation!.isCancelled, isTrue);
    var discarded = 0;
    repository.pendingDownload!.complete(SubtitleDownloadResult(
        cachedPath: '/late',
        displayName: 'late',
        subtitleFilePath: '/late/a.srt',
        discard: () async {
          discarded++;
        }));
    await tester.pumpAndSettle();
    expect(discarded, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV subtitle search has one result target and retains busy focus',
      (tester) async {
    final repository = _FakeOnlineSubtitleRepository();
    final pending = Completer<List<ValidatedSubtitleCandidate>>();
    repository.pendingSearch = pending.future;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWith((ref) => true),
        appSettingsProvider.overrideWithValue(AppSettings.fromJson({
          'onlineSubtitleSources': ['assrt'],
          'assrtToken': 'token',
        })),
        onlineSubtitleRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(
        home: SubtitleSearchPage(
          request: SubtitleSearchRequest(query: 'Film', title: 'Film'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(hasActionableTvFocus(), isTrue);
    expect(find.byType(TextField), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    final submit = tester
        .widgetList<TvFocusableAction>(find.byType(TvFocusableAction))
        .firstWhere((widget) => widget.focusId == 'subtitle-search:submit');
    submit.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump();
    expect(submit.focusNode!.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(repository.requests, hasLength(1));
    pending.complete(const [
      ValidatedSubtitleCandidate(
        hit: ProviderSubtitleHit(
          id: 'result',
          source: OnlineSubtitleSource.assrt,
          providerLabel: 'ASSRT',
          title: 'RESULT',
          downloadUrl: 'https://example.com/a.srt',
          packageName: 'a.srt',
          packageKind: SubtitlePackageKind.subtitleFile,
        ),
        status: SubtitleValidationStatus.skipped,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(submit.focusNode!.hasPrimaryFocus, isTrue);
    final result = tester
        .widgetList<TvFocusableAction>(find.byType(TvFocusableAction))
        .firstWhere(
            (widget) => widget.focusId == 'subtitle-search:result:result');
    final node = tester
        .widget<FocusableActionDetector>(find
            .descendant(
              of: find.byWidget(result),
              matching: find.byType(FocusableActionDetector),
            )
            .first)
        .focusNode!;
    node.requestFocus();
    await tester.pump();
    expect(node.traversalDescendants, isEmpty);
    repository.pendingDownload = Completer<SubtitleDownloadResult>();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump();
    expect(node.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(repository.downloadCalls, 1);
    repository.pendingDownload!.completeError(StateError('download failed'));
    await tester.pumpAndSettle();
    expect(node.hasPrimaryFocus, isTrue);
  });

  testWidgets(
      'search ignores repeated submission and stale results after target changes',
      (tester) async {
    final repository = _FakeOnlineSubtitleRepository();
    final pending = Completer<List<ValidatedSubtitleCandidate>>();
    repository.pendingSearch = pending.future;
    final request = ValueNotifier(
        const SubtitleSearchRequest(query: 'Old Film', title: 'Old Film'));
    addTearDown(request.dispose);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(AppSettings.fromJson({
            'onlineSubtitleSources': ['assrt'],
            'assrtToken': 'token',
          })),
          onlineSubtitleRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
            home: ValueListenableBuilder<SubtitleSearchRequest>(
          valueListenable: request,
          builder: (_, value, child) => SubtitleSearchPage(request: value),
        ))));
    final submit =
        tester.widget<TextField>(find.byType(TextField)).onSubmitted!;
    submit('Old Film');
    submit('Old Film');
    await tester.pump();
    await tester.pump();
    expect(repository.requests, hasLength(1));
    request.value =
        const SubtitleSearchRequest(query: 'New Film', title: 'New Film');
    await tester.pump();
    expect(repository.searchOperation!.isCancelled, isTrue);
    pending.complete(const [
      ValidatedSubtitleCandidate(
        hit: ProviderSubtitleHit(
            id: 'old',
            source: OnlineSubtitleSource.assrt,
            providerLabel: 'ASSRT',
            title: 'STALE RESULT',
            downloadUrl: 'https://example.com/a.srt',
            packageName: 'a.srt',
            packageKind: SubtitlePackageKind.subtitleFile),
        status: SubtitleValidationStatus.skipped,
      )
    ]);
    await tester.pumpAndSettle();
    expect(find.text('STALE RESULT'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'New Film');
  });

  testWidgets('edited query drops the original movie identity', (tester) async {
    final repository = _FakeOnlineSubtitleRepository();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(AppSettings.fromJson({
            'onlineSubtitleSources': ['assrt'],
            'assrtToken': 'token',
          })),
          onlineSubtitleRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
            home: SubtitleSearchPage(
                request: SubtitleSearchRequest(
          query: 'Old Film',
          title: 'Old Film',
          imdbId: 'tt1234567',
          tmdbId: '42',
          seasonNumber: 1,
          episodeNumber: 2,
          filePath: '/old/film.mkv',
        )))));
    await tester.enterText(find.byType(TextField), 'Corrected Film');
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();
    final request = repository.requests.single;
    expect(request.normalizedQuery, 'Corrected Film');
    expect(request.normalizedImdbId, isEmpty);
    expect(request.normalizedTmdbId, isEmpty);
    expect(request.filePath, isEmpty);
    expect(request.seasonNumber, isNull);
    expect(
        request
            .buildQueryPlan()
            .every((query) => query.query.contains('Corrected Film')),
        isTrue);
  });

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
              'assrtToken': 'assrt-token',
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
  Future<List<ValidatedSubtitleCandidate>>? pendingSearch;
  Completer<SubtitleDownloadResult>? pendingDownload;
  int downloadCalls = 0;
  SubtitleOperation? searchOperation;
  SubtitleOperation? downloadOperation;
  final requests = <OnlineSubtitleSearchRequest>[];
  final List<String> searchQueries = <String>[];
  final List<List<OnlineSubtitleSource>> searchSources =
      <List<OnlineSubtitleSource>>[];

  @override
  Future<SubtitleDownloadResult> download(SubtitleSearchResult result,
      {SubtitleOperation? operation}) {
    downloadOperation = operation;
    downloadCalls++;
    if (pendingDownload != null) return pendingDownload!.future;
    throw UnimplementedError();
  }

  @override
  Future<LocalStorageCacheSummary> inspectCacheSummary() async {
    return const LocalStorageCacheSummary(
      type: LocalStorageCacheType.subtitleCache,
      entryCount: 0,
      totalBytes: 0,
    );
  }

  @override
  Future<void> clearCache() async {}

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
    SubtitleOperation? operation,
  }) async {
    searchOperation = operation;
    searchQueries.add(request.normalizedQuery);
    requests.add(request);
    searchSources.add(List<OnlineSubtitleSource>.from(sources));
    return pendingSearch ?? Future.value(const []);
  }
}
