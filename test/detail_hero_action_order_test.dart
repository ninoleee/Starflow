import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/application/detail_start_playback_resolver.dart';
import 'package:starflow/features/details/presentation/widgets/detail_hero_section.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/application/active_playback_cleanup.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  setUp(() => activePlaybackLaunchInProgress.value = false);
  tearDown(() => activePlaybackLaunchInProgress.value = false);

  const seriesTarget = MediaDetailTarget(
    title: 'Series',
    posterUrl: '',
    overview: '',
    sourceId: 'nas',
    itemId: 'series',
    itemType: 'series',
  );
  const historyTarget = PlaybackTarget(
    title: 'Episode 4',
    sourceId: 'nas',
    itemId: 'episode-4',
    itemType: 'episode',
    seriesId: 'series',
    seriesTitle: 'Series',
    seasonNumber: 2,
    episodeNumber: 4,
    streamUrl: 'https://example.com/episode-4.mkv',
    sourceName: 'NAS',
    sourceKind: MediaSourceKind.nas,
    headers: {'Authorization': 'test-token'},
    preferredMediaSourceId: 'version-2',
  );
  final historyEntry = PlaybackProgressEntry(
    key: buildPlaybackItemKey(historyTarget),
    target: historyTarget,
    updatedAt: _testUpdatedAt,
    position: const Duration(minutes: 12),
    duration: const Duration(hours: 1),
  );

  test('matched resource identity does not require a playback target', () {
    expect(seriesTarget.hasMatchedResource, isTrue);
    expect(seriesTarget.copyWith(itemType: 'movie').hasMatchedResource, isTrue);
    const metadataOnly = MediaDetailTarget(
      title: 'Series',
      posterUrl: '',
      overview: '',
      tmdbId: '123',
    );
    expect(metadataOnly.hasMatchedResource, isFalse);
    expect(metadataOnly.copyWith(sourceId: 'nas').hasMatchedResource, isFalse);
    expect(metadataOnly.copyWith(itemId: 'series').hasMatchedResource, isFalse);
    expect(
        metadataOnly.copyWith(playbackTarget: historyTarget).hasMatchedResource,
        isTrue);
  });

  for (final itemType in ['series', 'movie']) {
    for (final historyFails in [false, true]) {
      testWidgets(
          '$itemType match shows start independently of history, error: $historyFails',
          (tester) async {
        final snapshot = Completer<PlaybackMemorySnapshot>();
        final target = ValueNotifier(const MediaDetailTarget(
          title: 'Unmatched',
          posterUrl: '',
          overview: '',
        ));
        addTearDown(target.dispose);
        await tester.pumpWidget(ProviderScope(
          overrides: [
            appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
            isTelevisionProvider.overrideWith((ref) => true),
            playbackMemorySnapshotProvider
                .overrideWith((ref) => snapshot.future),
            detailStartPlaybackResolverProvider.overrideWith((ref) {
              throw StateError('Rendering must not resolve playback');
            }),
          ],
          child: MaterialApp(
              home: Scaffold(
            body: ValueListenableBuilder<MediaDetailTarget>(
              valueListenable: target,
              builder: (_, current, __) => DetailHeroSection(
                target: current,
                simplifyVisualEffects: true,
                isTelevision: true,
              ),
            ),
          )),
        ));
        expect(find.text('从头播放'), findsNothing);
        target.value = seriesTarget.copyWith(itemType: itemType);
        await tester.pump();
        expect(find.text('从头播放'), findsOneWidget);
        final start = tester.element(find.text('从头播放'));
        expect(
            tester
                .widget<StarflowButton>(find.byType(StarflowButton))
                .onPressed,
            isNotNull);
        if (historyFails) {
          snapshot.completeError(StateError('History unavailable'));
        } else {
          snapshot.complete(PlaybackMemorySnapshot());
        }
        await tester.pumpAndSettle();
        target.value = target.value.copyWith(overview: 'Updated metadata');
        await tester.pumpAndSettle();
        expect(tester.element(find.text('从头播放')), same(start));
        expect(find.text('继续播放'), findsNothing);
        expect(
            tester
                .widget<StarflowButton>(find.byType(StarflowButton))
                .onPressed,
            isNotNull);
        target.value =
            target.value.copyWith(sourceId: 'other', itemId: 'other-item');
        await tester.pumpAndSettle();
        expect(tester.element(find.text('从头播放')), same(start));
        target.value = const MediaDetailTarget(
          title: 'Unmatched',
          posterUrl: '',
          overview: '',
        );
        await tester.pumpAndSettle();
        expect(find.text('从头播放'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('completed and cleared history leave matched start mounted',
      (tester) async {
    final seriesKey = buildSeriesKeyForMetadata(
      sourceId: 'nas',
      itemId: 'series',
      title: 'Series',
      year: 0,
    );
    var snapshot = PlaybackMemorySnapshot(series: {seriesKey: historyEntry});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
        isTelevisionProvider.overrideWith((ref) => true),
        playbackMemorySnapshotProvider.overrideWith((ref) => snapshot),
      ],
      child: const MaterialApp(
          home: Scaffold(
              body: DetailHeroSection(
        target: seriesTarget,
        simplifyVisualEffects: true,
        isTelevision: true,
      ))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('继续播放'), findsOneWidget);
    final start = tester.element(find.text('从头播放'));
    final container = ProviderScope.containerOf(start);
    for (final next in [
      PlaybackMemorySnapshot(
          series: {seriesKey: historyEntry.copyWith(completed: true)}),
      PlaybackMemorySnapshot(),
    ]) {
      snapshot = next;
      container.invalidate(playbackMemorySnapshotProvider);
      await tester.pumpAndSettle();
      expect(find.text('继续播放'), findsNothing);
      expect(tester.element(find.text('从头播放')), same(start));
      expect(
          tester.widget<StarflowButton>(find.byType(StarflowButton)).onPressed,
          isNotNull);
      expect(tester.takeException(), isNull);
    }
  });

  for (final startsWithPlayback in [false, true]) {
    testWidgets(
        'series resume always has start, initial playback: $startsWithPlayback',
        (tester) async {
      final snapshot = Completer<PlaybackMemorySnapshot>();
      final target = ValueNotifier(startsWithPlayback
          ? seriesTarget.copyWith(playbackTarget: historyTarget)
          : seriesTarget);
      addTearDown(target.dispose);
      final playFocusNode = FocusNode(debugLabel: 'series-primary-play');
      addTearDown(playFocusNode.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
          isTelevisionProvider.overrideWith((ref) => true),
          playbackMemorySnapshotProvider.overrideWith((ref) => snapshot.future),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<MediaDetailTarget>(
              valueListenable: target,
              builder: (_, current, __) => DetailHeroSection(
                target: current,
                simplifyVisualEffects: true,
                isTelevision: true,
                playFocusNode: playFocusNode,
              ),
            ),
          ),
        ),
      ));
      expect(find.text('从头播放'), findsOneWidget);
      expect(find.text('继续播放'), findsNothing);
      final startElement = tester.element(find.text('从头播放'));
      snapshot.complete(PlaybackMemorySnapshot(series: {
        buildSeriesKeyForMetadata(
          sourceId: 'nas',
          itemId: 'series',
          title: 'Series',
          year: 0,
        ): historyEntry,
      }));
      await tester.pumpAndSettle();
      expect(find.text('继续播放'), findsOneWidget);
      expect(find.text('从头播放'), findsOneWidget);
      expect(playFocusNode.hasFocus, isTrue);
      expect(tester.element(find.text('从头播放')), same(startElement));

      // A series-only refresh must not remove start while resume stays valid.
      target.value = seriesTarget;
      await tester.pumpAndSettle();
      expect(tester.element(find.text('从头播放')), same(startElement));
      expect(tester.getTopLeft(find.text('继续播放')).dx,
          lessThan(tester.getTopLeft(find.text('从头播放')).dx));
      expect(
          tester
              .widgetList<StarflowButton>(find.byType(StarflowButton))
              .every((button) => button.onPressed != null),
          isTrue);
      expect(
          tester
              .widget<DetailHeroContent>(find.byType(DetailHeroContent))
              .resolveStartTarget,
          isNotNull);
      final content =
          tester.widget<DetailHeroContent>(find.byType(DetailHeroContent));
      expect(content.resumePlaybackTarget!.itemId, 'episode-4');
      expect(content.resumePlaybackTarget!.allowResume, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  test('resume position label names season, episode and clock position', () {
    const resumeTarget = PlaybackTarget(
      title: '测试剧 第 8 集',
      sourceId: 'nas-main',
      streamUrl: 'https://media.example.com/e08.mkv',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
      seasonNumber: 2,
      episodeNumber: 8,
    );
    final resumeEntry = PlaybackProgressEntry(
      key: 'item|nas-main|e08',
      target: resumeTarget,
      updatedAt: _testUpdatedAt,
      position: Duration(minutes: 18, seconds: 32),
    );
    expect(
      buildDetailHeroResumePositionLabel(
        const MediaDetailTarget(title: '', posterUrl: '', overview: ''),
        resumeEntry,
      ),
      '上次播放：第 2 季 · 第 8 集 · 18:32',
    );
  });

  testWidgets('resume action precedes start action and owns primary focus',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playFocusNode = FocusNode(debugLabel: 'detail-primary-play');
    addTearDown(playFocusNode.dispose);
    const startTarget = PlaybackTarget(
      title: '测试剧',
      sourceId: 'nas-main',
      streamUrl: 'https://media.example.com/start.mkv',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
    );
    const resumeTarget = PlaybackTarget(
      title: '测试剧 第 4 集',
      sourceId: 'nas-main',
      streamUrl: 'https://media.example.com/resume.mkv',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
      episodeNumber: 4,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
          isTelevisionProvider.overrideWith((ref) => true),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DetailHeroContent(
              target: const MediaDetailTarget(
                title: '测试剧',
                posterUrl: '',
                overview: '',
                year: 2026,
              ),
              metadata: const [],
              peopleLine: '',
              simplifyVisualEffects: true,
              isTelevision: true,
              resolveStartTarget: () async => startTarget,
              resumePlaybackTarget: resumeTarget,
              playFocusNode: playFocusNode,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.getTopLeft(find.text('继续播放')).dx,
      lessThan(tester.getTopLeft(find.text('从头播放')).dx),
    );
    final resumeButton = tester.widget<StarflowButton>(
      find.ancestor(
        of: find.text('继续播放'),
        matching: find.byType(StarflowButton),
      ),
    );
    final startButton = tester.widget<StarflowButton>(
      find.ancestor(
        of: find.text('从头播放'),
        matching: find.byType(StarflowButton),
      ),
    );
    expect(resumeButton.focusNode, same(playFocusNode));
    expect(resumeButton.autofocus, isTrue);
    expect(resumeButton.variant, StarflowButtonVariant.secondary);
    expect(startButton.focusNode, isNull);
    expect(startButton.autofocus, isFalse);
    expect(startButton.variant, StarflowButtonVariant.secondary);
  });

  testWidgets('hero actions do not disappear for metadata-only target changes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playFocusNode = FocusNode(debugLabel: 'detail-primary-play');
    addTearDown(playFocusNode.dispose);

    const playbackTarget = PlaybackTarget(
      title: '共享快照',
      sourceId: 'nas-main',
      streamUrl: 'https://nas.example.com/shared.mkv',
      sourceName: '家庭 NAS',
      sourceKind: MediaSourceKind.nas,
      itemId: 'shared-1',
      itemType: 'movie',
    );
    final itemKey = buildPlaybackItemKey(playbackTarget);
    final repository = _HeroMemoryRepository(
      PlaybackMemorySnapshot(
        items: {
          itemKey: PlaybackProgressEntry(
            key: itemKey,
            target: playbackTarget,
            updatedAt: DateTime.utc(2026, 8, 29, 12),
            position: const Duration(minutes: 17, seconds: 24),
            duration: const Duration(hours: 2),
            progress: 0.145,
          ),
        },
      ),
    );
    const initialTarget = MediaDetailTarget(
      title: '共享快照',
      posterUrl: '',
      overview: '',
      playbackTarget: playbackTarget,
      sourceId: 'nas-main',
      itemId: 'shared-1',
      itemType: 'movie',
    );
    final enrichedTarget = initialTarget.copyWith(
      posterUrl: 'https://images.example.com/poster.jpg',
      overview: '补充后的简介',
      ratingLabels: const ['豆瓣 8.8'],
    );

    Widget buildHero(MediaDetailTarget target) {
      return ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
          isTelevisionProvider.overrideWith((ref) => true),
          playbackMemoryRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DetailHeroSection(
              target: target,
              simplifyVisualEffects: true,
              isTelevision: true,
              playFocusNode: playFocusNode,
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildHero(initialTarget));
    await tester.pump();
    await tester.pump();

    expect(find.text('继续播放'), findsOneWidget);
    expect(find.text('从头播放'), findsOneWidget);

    await tester.pumpWidget(buildHero(enrichedTarget));

    expect(find.text('继续播放'), findsOneWidget);
    expect(find.text('从头播放'), findsOneWidget);
    expect(repository.loadSnapshotCount, 1);
  });

  testWidgets(
      'cold history load keeps start action mounted while adding resume',
      (tester) async {
    final snapshot = Completer<PlaybackMemorySnapshot>();
    const playback = PlaybackTarget(
      title: 'Movie',
      sourceId: 'nas',
      itemId: '1',
      streamUrl: 'https://example.com/1',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
        isTelevisionProvider.overrideWith((ref) => true),
        playbackMemorySnapshotProvider.overrideWith((ref) => snapshot.future),
      ],
      child: const MaterialApp(
          home: Scaffold(
              body: DetailHeroSection(
        target: MediaDetailTarget(
            title: 'Movie',
            posterUrl: '',
            overview: '',
            playbackTarget: playback),
        simplifyVisualEffects: true,
        isTelevision: true,
      ))),
    ));
    expect(find.text('从头播放'), findsOneWidget);
    expect(find.text('继续播放'), findsNothing);
    final startElement = tester.element(find.text('从头播放'));
    final key = buildPlaybackItemKey(playback);
    snapshot.complete(PlaybackMemorySnapshot(items: {
      key: PlaybackProgressEntry(
          key: key,
          target: playback,
          updatedAt: DateTime(2026),
          position: const Duration(minutes: 10)),
    }));
    await tester.pump();
    await tester.pump();
    expect(find.text('继续播放'), findsOneWidget);
    expect(find.text('从头播放'), findsOneWidget);
    expect(tester.element(find.text('从头播放')), same(startElement));
  });

  testWidgets('start action stays mounted when playback identity is resolved',
      (tester) async {
    const playback = PlaybackTarget(
      title: 'Movie',
      sourceId: 'nas',
      streamUrl: 'https://example.com/movie',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
    );
    const target = MediaDetailTarget(
      title: 'Movie',
      posterUrl: '',
      overview: '',
      playbackTarget: playback,
    );
    final repository = _HeroMemoryRepository(PlaybackMemorySnapshot());
    Widget buildHero(MediaDetailTarget target) => ProviderScope(
          overrides: [
            appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
            isTelevisionProvider.overrideWith((ref) => true),
            playbackMemoryRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DetailHeroSection(
                target: target,
                simplifyVisualEffects: true,
                isTelevision: true,
              ),
            ),
          ),
        );
    await tester.pumpWidget(buildHero(target));
    await tester.pumpAndSettle();
    final button = tester.element(find.text('从头播放'));
    final position = tester.getTopLeft(find.text('从头播放'));

    await tester.pumpWidget(buildHero(target.copyWith(
      playbackTarget: playback.copyWith(itemId: 'resolved-movie'),
    )));

    expect(find.text('从头播放'), findsOneWidget);
    expect(tester.element(find.text('从头播放')), same(button));
    expect(tester.getTopLeft(find.text('从头播放')), position);
    expect(repository.loadSnapshotCount, 1);
    expect(find.text('继续播放'), findsNothing);
  });

  testWidgets('history readiness changes never remove the start button',
      (tester) async {
    const playback = PlaybackTarget(
      title: 'Movie',
      sourceId: 'nas',
      streamUrl: 'https://example.com/movie',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
    );
    Widget app(bool ready) => ProviderScope(
          overrides: [
            appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
            isTelevisionProvider.overrideWith((ref) => true),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DetailHeroContent(
                target: const MediaDetailTarget(
                    title: 'Movie', posterUrl: '', overview: ''),
                metadata: const [],
                peopleLine: '',
                simplifyVisualEffects: true,
                isTelevision: true,
                resolveStartTarget: () async => playback,
                resumePlaybackTarget: null,
                playbackActionsReady: ready,
              ),
            ),
          ),
        );
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    final element = tester.element(find.text('从头播放'));
    for (final ready in [false, true, false, true]) {
      await tester.pumpWidget(app(ready));
      expect(find.text('从头播放'), findsOneWidget);
      expect(tester.element(find.text('从头播放')), same(element));
      final button = tester.widget<StarflowButton>(find.byType(StarflowButton));
      expect(button.onPressed, isNotNull);
    }
  });

  testWidgets('play actions share a lock until player returns', (tester) async {
    final cleanup = Completer<void>();
    var cleanups = 0;
    final token = ActivePlaybackCleanupCoordinator.register((_) {
      cleanups++;
      return cleanup.future;
    });
    addTearDown(() => ActivePlaybackCleanupCoordinator.unregister(token));
    const playback = PlaybackTarget(
        title: 'Movie',
        sourceId: 'nas',
        streamUrl: 'https://example.com/1',
        sourceName: 'NAS',
        sourceKind: MediaSourceKind.nas);
    var launches = 0;
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
                body: DetailHeroContent(
                  target: const MediaDetailTarget(
                      title: 'Movie', posterUrl: '', overview: ''),
                  metadata: [],
                  peopleLine: '',
                  simplifyVisualEffects: true,
                  isTelevision: false,
                  resolveStartTarget: () async => playback,
                  resumePlaybackTarget: playback,
                ),
              )),
      GoRoute(
          path: '/player',
          name: 'player',
          builder: (_, __) {
            launches++;
            return const Scaffold(body: Text('Player'));
          }),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
      isTelevisionProvider.overrideWith((ref) => false),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    final buttons =
        tester.widgetList<StarflowButton>(find.byType(StarflowButton)).toList();
    buttons.first.onPressed!();
    buttons.last.onPressed!();
    await tester.pump();
    expect(cleanups, 1);
    expect(
        tester
            .widgetList<StarflowButton>(find.byType(StarflowButton))
            .every((button) => button.onPressed == null),
        isTrue);
    cleanup.complete();
    await tester.pumpAndSettle();
    expect(launches, 1);
    router.pop();
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<StarflowButton>(find.byType(StarflowButton))
            .every((button) => button.onPressed != null),
        isTrue);
  });
}

final _testUpdatedAt = DateTime(2026);

class _HeroMemoryRepository extends PlaybackMemoryRepository {
  _HeroMemoryRepository(this.snapshot);

  final PlaybackMemorySnapshot snapshot;
  int loadSnapshotCount = 0;

  @override
  Future<PlaybackMemorySnapshot> loadSnapshot() async {
    loadSnapshotCount += 1;
    return snapshot;
  }
}
