import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/application/detail_start_playback_resolver.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/widgets/detail_hero_section.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/active_playback_cleanup.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

const _series = MediaDetailTarget(
  title: 'Series',
  posterUrl: '',
  overview: '',
  sourceId: 'nas',
  itemId: 'series',
  itemType: 'series',
);
const _history = PlaybackTarget(
  title: 'S02E04',
  sourceId: 'nas',
  itemId: 's2e4',
  itemType: 'episode',
  sourceName: 'NAS',
  sourceKind: MediaSourceKind.nas,
  streamUrl: 'https://example.com/s2e4.mkv',
  seriesId: 'series',
  seriesTitle: 'Series',
  seasonNumber: 2,
  episodeNumber: 4,
  headers: {'Authorization': 'old-episode'},
  preferredMediaSourceId: 'old-version',
);

MediaItem _item(String id, String type, int season, [int? episode]) =>
    MediaItem(
      id: id,
      title: id,
      overview: '',
      posterUrl: '',
      year: 2026,
      durationLabel: '',
      genres: const [],
      itemType: type,
      sourceId: 'nas',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
      streamUrl: type == 'episode' ? 'https://example.com/$id.mkv' : '',
      playbackItemId: type == 'episode' ? id : '',
      streamHeaders: const {'Authorization': 'first-episode'},
      preferredMediaSourceId: 'first-version',
      seasonNumber: season,
      episodeNumber: episode,
      addedAt: DateTime(2026),
    );

void main() {
  test('uses the first listed season and its first sorted episode', () async {
    final repository = _Repository({
      'series': [
        _item('s2', 'season', 2),
        _item('s5', 'season', 5),
      ],
      's2': [_item('s2e7', 'episode', 2, 7), _item('s2e3', 'episode', 2, 3)],
    });
    final start = await DetailStartPlaybackResolver(repository).resolve(
      detail: _series,
    );
    expect(start.itemId, 's2e3');
    expect(start.seasonNumber, 2);
    expect(start.episodeNumber, 3);
    expect(start.allowResume, isFalse);
    expect(start.seriesId, 'series');
    expect(start.streamUrl, 'https://example.com/s2e3.mkv');
    expect(start.headers, {'Authorization': 'first-episode'});
    expect(start.preferredMediaSourceId, 'first-version');
    expect(repository.requests, ['series', 's2']);
  });

  test('flat series and episode details also resolve the first episode',
      () async {
    final repository = _Repository({
      'series': [
        _item('special', 'episode', 0, 1),
        _item('s2e1', 'episode', 2, 1),
        _item('s1e1', 'episode', 1, 1)
      ],
    });
    final start = await DetailStartPlaybackResolver(repository).resolve(
      detail: _series.copyWith(
          itemType: 'episode', itemId: 's2e4', playbackTarget: _history),
    );
    expect(start.itemId, 'special');
    expect(start.allowResume, isFalse);
    expect(repository.requests, ['series']);
  });

  test('movies start at zero without listing children', () async {
    final repository = _Repository({});
    final resolver = DetailStartPlaybackResolver(repository);
    final movie = _history.copyWith(itemType: 'movie', itemId: 'movie');
    final movieStart = await resolver.resolve(
      detail: _series.copyWith(itemType: 'movie', playbackTarget: movie),
    );
    expect(movieStart.itemId, 'movie');
    expect(movieStart.allowResume, isFalse);
    expect(movieStart.streamUrl, movie.streamUrl);
    expect(repository.requests, isEmpty);
  });

  test('matched movie without a playback target resolves within its own source',
      () async {
    final repository = _Repository({}, library: [
      _item('movie', 'movie', 0).copyWith(
          sourceId: 'other', streamUrl: 'https://other.example.com/movie.mkv'),
      _item('movie', 'movie', 0).copyWith(
          playbackItemId: 'movie', streamUrl: 'https://example.com/movie.mkv'),
    ]);
    final start = await DetailStartPlaybackResolver(repository).resolve(
      detail: _series.copyWith(
          itemType: 'movie', itemId: 'movie', sectionId: 'movies'),
    );
    expect(start.itemId, 'movie');
    expect(start.sourceId, 'nas');
    expect(start.streamUrl, 'https://example.com/movie.mkv');
    expect(start.allowResume, isFalse);
    expect(repository.requests, ['library:nas:movies']);
  });

  test('an S01E01 history target does not override the first listed season',
      () async {
    final repository = _Repository({
      'series': [_item('specials', 'season', 0), _item('s1', 'season', 1)],
      'specials': [_item('special', 'episode', 0, 2)],
    });
    final start = await DetailStartPlaybackResolver(repository).resolve(
      detail: _series.copyWith(
          playbackTarget: _history.copyWith(seasonNumber: 1, episodeNumber: 1)),
    );
    expect(start.itemId, 'special');
    expect(start.seasonNumber, 0);
    expect(start.episodeNumber, 2);
    expect(start.allowResume, isFalse);
  });

  test('empty or unplayable earliest season does not fall back to history',
      () async {
    for (final children in [
      [_item('s2', 'season', 2)],
      <MediaItem>[],
      [
        _item('s1e2', 'episode', 1, 2)
            .copyWith(streamUrl: '', playbackItemId: '')
      ],
    ]) {
      final resolver =
          DetailStartPlaybackResolver(_Repository({'series': children}));
      await expectLater(
        resolver.resolve(detail: _series),
        throwsA(isA<DetailStartPlaybackException>()),
      );
    }
  });

  testWidgets('empty season keeps both actions available for retry',
      (tester) async {
    var resolutions = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
        isTelevisionProvider.overrideWith((ref) => false),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: DetailHeroContent(
            target: _series,
            metadata: const [],
            peopleLine: '',
            simplifyVisualEffects: true,
            isTelevision: false,
            resumePlaybackTarget: _history,
            resolveStartTarget: () async {
              resolutions++;
              throw const DetailStartPlaybackException('No playable episodes');
            },
          ),
        ),
      ),
    ));
    final startElement = tester.element(find.text('从头播放'));
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.text('从头播放'));
      await tester.pumpAndSettle();
      expect(tester.element(find.text('从头播放')), same(startElement));
      expect(find.text('继续播放'), findsOneWidget);
      expect(find.text('播放失败：No playable episodes'), findsOneWidget);
      expect(activePlaybackLaunchInProgress.value, isFalse);
      expect(
        tester
            .widgetList<StarflowButton>(find.byType(StarflowButton))
            .every((button) => button.onPressed != null),
        isTrue,
      );
    }
    expect(resolutions, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'TV start stays mounted across source changes and opens the latest source',
      (tester) async {
    final episodes = Completer<List<MediaItem>>();
    final repository = _Repository({}, pending: episodes.future);
    final memory = PlaybackMemorySnapshot();
    final target = ValueNotifier(_series);
    addTearDown(target.dispose);
    PlaybackTarget? launched;
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
                body: ValueListenableBuilder<MediaDetailTarget>(
                  valueListenable: target,
                  builder: (_, detail, __) => DetailHeroSection(
                    target: detail,
                    simplifyVisualEffects: true,
                    isTelevision: true,
                  ),
                ),
              )),
      GoRoute(
          path: '/player',
          name: 'player',
          builder: (_, state) {
            launched = state.extra! as PlaybackTarget;
            return const Scaffold(body: Text('Player'));
          }),
    ]);
    addTearDown(router.dispose);
    addTearDown(() => activePlaybackLaunchInProgress.value = false);
    await tester.pumpWidget(ProviderScope(overrides: [
      appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
      isTelevisionProvider.overrideWith((ref) => true),
      playbackMemorySnapshotProvider.overrideWith((ref) => memory),
      detailStartPlaybackResolverProvider
          .overrideWithValue(DetailStartPlaybackResolver(repository)),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    final button = tester.element(find.text('从头播放'));
    expect(find.text('继续播放'), findsNothing);
    target.value = _series.copyWith(sourceId: 'other', itemId: 'other-series');
    await tester.pumpAndSettle();
    expect(tester.element(find.text('从头播放')), same(button));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(tester.element(find.text('从头播放')), same(button));
    expect(find.text('继续播放'), findsNothing);
    expect(launched, isNull);
    expect(repository.requests, ['other-series']);
    expect(repository.childSources, ['other']);
    expect(
        tester
            .widgetList<StarflowButton>(find.byType(StarflowButton))
            .every((button) => button.onPressed == null),
        isTrue);
    episodes.complete([
      _item('s2e4', 'episode', 2, 4).copyWith(sourceId: 'other'),
      _item('s2e3', 'episode', 2, 3).copyWith(sourceId: 'other'),
    ]);
    await tester.pumpAndSettle();
    expect(launched!.itemId, 's2e3');
    expect(launched!.sourceId, 'other');
    expect(launched!.seriesId, 'other-series');
    expect(launched!.allowResume, isFalse);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('从头播放'), findsOneWidget);
    expect(
        tester
            .widgetList<StarflowButton>(find.byType(StarflowButton))
            .every((button) => button.onPressed != null),
        isTrue);
    expect(tester.takeException(), isNull);
  });
}

class _Repository implements MediaRepository {
  _Repository(this.children, {this.pending, this.library = const []});
  final Map<String, List<MediaItem>> children;
  final Future<List<MediaItem>>? pending;
  final List<MediaItem> library;
  final requests = <String>[];
  final childSources = <String>[];

  @override
  Future<List<MediaItem>> fetchLibrary({
    MediaSourceKind? kind,
    String? sourceId,
    String? sectionId,
    int limit = 200,
  }) async {
    requests.add('library:$sourceId:$sectionId');
    return library;
  }

  @override
  Future<List<MediaItem>> fetchChildren({
    required String sourceId,
    required String parentId,
    String sectionId = '',
    String sectionName = '',
    int limit = 200,
  }) async {
    requests.add(parentId);
    childSources.add(sourceId);
    return pending ?? children[parentId] ?? const <MediaItem>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
