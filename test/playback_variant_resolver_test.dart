import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/data/media_server_client.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_variant_resolver.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/domain/playback_episode_queue.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const target = PlaybackTarget(
    title: 'Movie',
    sourceId: 'server',
    sourceName: 'Server',
    sourceKind: MediaSourceKind.fntv,
    itemId: 'movie',
    itemType: 'movie',
    streamUrl: 'https://server/current',
    preferredMediaSourceId: 'file-a',
    actualAddress: '/Movie/a.mkv');

class _Client extends Fake implements MediaServerClient {
  List<PlaybackTarget> choices = [];
  int calls = 0;
  @override
  Future<List<PlaybackTarget>> fetchPlaybackVariants({
    required MediaSourceConfig source,
    required PlaybackTarget target,
  }) async {
    calls++;
    return choices;
  }
}

class _Indexer extends Fake implements NasMediaIndexer {
  _Indexer(this.items);

  final List<MediaItem> items;
  final List<String> requests = [];

  @override
  Future<List<MediaItem>> loadMovieVariants(
    MediaSourceConfig source, {
    required String itemId,
    String sectionId = '',
    List<MediaCollection>? scopedCollections,
  }) async {
    requests.add('movie:$itemId');
    return items;
  }

  @override
  Future<List<MediaItem>> loadEpisodeVariants(
    MediaSourceConfig source, {
    required String itemId,
    String sectionId = '',
    List<MediaCollection>? scopedCollections,
  }) async {
    requests.add('episode:$itemId');
    return items;
  }
}

void main() {
  for (final type in ['movie', 'episode']) {
    test(
        'indexed $type versions remain available after switching and switching back',
        () async {
      final items = [
        for (final id in ['a', 'b'])
          MediaItem(
            id: id,
            title: 'Title',
            overview: '',
            posterUrl: '',
            year: 2026,
            durationLabel: '',
            genres: const [],
            sourceId: 'nas',
            sourceName: 'NAS',
            sourceKind: MediaSourceKind.nas,
            itemType: id == 'a' ? type : '',
            streamUrl: 'https://nas/$id.strm',
            actualAddress: '/$id.strm',
            addedAt: DateTime(2026),
          )
      ];
      final indexer = _Indexer(items);
      final container = ProviderContainer(overrides: [
        appSettingsProvider.overrideWithValue(const AppSettings(
          searchProviders: [],
          homeModules: [],
          doubanAccount: DoubanAccountConfig(enabled: false),
          mediaSources: [
            MediaSourceConfig(
                id: 'nas',
                name: 'NAS',
                kind: MediaSourceKind.nas,
                enabled: true,
                endpoint: 'https://nas')
          ],
        )),
        nasMediaIndexerProvider.overrideWithValue(indexer),
      ]);
      addTearDown(container.dispose);
      final resolver = PlaybackVariantResolver(read: container.read);
      var current = PlaybackTarget.fromMediaItem(items.first).copyWith(
        itemId: 'a',
        seriesId: 'series',
        seriesTitle: 'Series',
        seasonNumber: type == 'episode' ? 2 : null,
        episodeNumber: type == 'episode' ? 3 : null,
      );
      for (final id in ['b', 'a', 'b']) {
        final choices = await resolver.load(current);
        expect(choices, hasLength(2));
        final selected =
            choices.firstWhere((choice) => choice.actualAddress == '/$id.strm');
        expect(selected.itemId, id);
        expect(selected.seriesId, 'series');
        expect(selected.seasonNumber, current.seasonNumber);
        expect(selected.episodeNumber, current.episodeNumber);
        // Native playback receives the same target through JSON; resolved
        // transport URLs must not remove the stable index identity.
        current = PlaybackTarget.fromJson(
                jsonDecode(jsonEncode(selected.toJson()))
                    as Map<String, dynamic>)
            .copyWith(streamUrl: 'https://cdn/$id.mkv');
        expect(supportsPlaybackVariants(current), isTrue);
      }
      expect(indexer.requests, ['$type:a', '$type:b', '$type:a']);
    });
  }
  test(
      'replacing a version updates current identity without changing queue order',
      () {
    final queue = PlaybackEpisodeQueue(entries: [
      PlaybackEpisodeQueueEntry(
          target: target, playbackItemKey: 'old', seriesKey: 'series'),
      PlaybackEpisodeQueueEntry(
          target: target, playbackItemKey: 'next', seriesKey: 'series'),
    ]);
    final next = target.copyWith(itemId: 'other-file');
    final updated = queue.replaceCurrentTarget(next,
        playbackItemKey: 'new', seriesKey: 'series');
    expect(updated.currentIndex, 0);
    expect(updated.currentEntry!.target, same(next));
    expect(updated.currentEntry!.playbackItemKey, 'new');
    expect(updated.nextEntry!.playbackItemKey, 'next');
    expect(queue.currentEntry!.playbackItemKey, 'old');
  });
  test('variant identity uses server file ID before matching item ID or path',
      () {
    expect(
        isSamePlaybackVariant(
            target, target.copyWith(preferredMediaSourceId: 'file-b')),
        isFalse);
    expect(
        isSamePlaybackVariant(
            target, target.copyWith(streamUrl: 'https://server/refreshed')),
        isTrue);
    expect(isSamePlaybackVariant(target, target.copyWith(sourceId: 'other')),
        isFalse);
    expect(playbackVariantLabel(target), 'a.mkv');
  });

  test('NAS resource IDs survive STRM address resolution', () {
    final nas = target.copyWith(
        sourceKind: MediaSourceKind.nas, preferredMediaSourceId: '');
    expect(
        isSamePlaybackVariant(nas,
            nas.copyWith(actualAddress: 'https://resolved.example/video.mkv')),
        isTrue);
    expect(
        isSamePlaybackVariant(nas,
            nas.copyWith(itemId: 'other-file', actualAddress: '/Movie/b.mkv')),
        isFalse);
  });

  test('server variants deduplicate, preserve current and clear old file state',
      () async {
    final client = _Client();
    final next = target.copyWith(
        preferredMediaSourceId: 'file-b',
        actualAddress: '/Movie/b.mkv',
        streamUrl: '',
        fntvSessionLink: 'old',
        preferredAudioStreamId: 'old-audio',
        preferredSubtitleStreamId: 'old-sub',
        preferredPlaybackQualityIndex: -1,
        fntvTrackSelectionExplicit: true,
        audioStreams: const [PlaybackAudioStream(id: 'old-audio')]);
    client.choices = [next, next];
    final container = ProviderContainer(overrides: [
      appSettingsProvider.overrideWithValue(const AppSettings(
        searchProviders: [],
        homeModules: [],
        doubanAccount: DoubanAccountConfig(enabled: false),
        mediaSources: [
          MediaSourceConfig(
              id: 'server',
              name: 'Server',
              kind: MediaSourceKind.fntv,
              enabled: true,
              endpoint: 'https://server')
        ],
      )),
      mediaServerClientProvider(MediaSourceKind.fntv).overrideWithValue(client),
    ]);
    addTearDown(container.dispose);
    final choices =
        await PlaybackVariantResolver(read: container.read).load(target);
    expect(choices, hasLength(2));
    expect(choices.first, same(target));
    expect(choices.last.preferredMediaSourceId, 'file-b');
    expect(choices.last.fntvSessionLink, isEmpty);
    expect(choices.last.audioStreams, isEmpty);
    expect(choices.last.preferredAudioStreamId, isEmpty);
    expect(choices.last.preferredSubtitleStreamId, isEmpty);
    expect(choices.last.fntvTrackSelectionExplicit, isFalse);
    expect(choices.last.preferredPlaybackQualityIndex, 0);
    expect(client.calls, 1);
  });

  test('unsupported targets never read providers', () async {
    final resolver = PlaybackVariantResolver(
        read: <T>(_) => throw StateError('unexpected read'));
    final series = target.copyWith(itemType: 'series');
    expect(supportsPlaybackVariants(series), isFalse);
    expect(await resolver.load(series), [series]);
  });
}
