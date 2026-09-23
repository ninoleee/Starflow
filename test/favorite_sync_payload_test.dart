import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/mpv_tuning_policy.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/search/domain/favorite_sync_document.dart';
import 'package:starflow/features/search/domain/favorite_sync_payload.dart';
import 'package:starflow/features/search/domain/search_models.dart';

SearchResult richFavorite([String id = 'one']) => SearchResult(
      id: id,
      title: 'Favorite $id',
      posterUrl: 'https://images.example.com/$id/poster.jpg',
      posterHeaders: const {'Authorization': 'image-only-secret'},
      providerId: 'provider',
      providerName: 'Provider',
      quality: '4K',
      sizeLabel: '20 GB',
      seeders: 5,
      summary: List.filled(40, 'Cached resource description.').join(' '),
      resourceUrl: 'https://example.com/share/$id',
      password: 'abcd',
      cloudType: 'quark',
      source: 'Cached source label',
      publishedAt: '2026-09-10',
      imageUrls:
          List.generate(8, (i) => 'https://images.example.com/$id/$i.jpg'),
      favoriteFolderName: 'My folder',
      originalSearchTitle: 'Original query',
      metadataMediaType: 'tv',
      doubanId: '1001',
      imdbId: 'tt1001',
      tmdbId: '1001',
      tvdbId: '1001',
      wikidataId: 'Q1001',
      detailTarget: MediaDetailTarget(
        title: 'Series',
        posterUrl: 'https://images.example.com/detail.jpg',
        posterHeaders: const {'Authorization': 'image-only-secret'},
        backdropUrl: 'https://images.example.com/backdrop.jpg',
        backdropHeaders: const {'Authorization': 'image-only-secret'},
        logoUrl: 'https://images.example.com/logo.png',
        logoHeaders: const {'Authorization': 'image-only-secret'},
        bannerUrl: 'https://images.example.com/banner.jpg',
        bannerHeaders: const {'Authorization': 'image-only-secret'},
        extraBackdropUrls: const ['https://images.example.com/extra.jpg'],
        extraBackdropHeaders: const {'Authorization': 'image-only-secret'},
        overview: List.filled(50, 'Cached plot information.').join(' '),
        year: 2026,
        durationLabel: '45 min',
        ratingLabels: const ['IMDb 8.0'],
        genres: const ['Drama'],
        directors: const ['Director'],
        directorProfiles: const [MediaPersonProfile(name: 'Director')],
        actors: const ['Actor'],
        actorProfiles: List.generate(
            20,
            (i) => MediaPersonProfile(
                name: 'Actor $i',
                avatarUrl: 'https://images.example.com/actor-$i.jpg')),
        platforms: const ['Platform'],
        platformProfiles: const [MediaPersonProfile(name: 'Platform')],
        availabilityLabel: 'Ready',
        searchQuery: 'Series',
        itemId: id,
        sourceId: 'nas-one',
        itemType: 'Episode',
        seasonNumber: 2,
        episodeNumber: 3,
        sectionId: 'shows',
        sectionName: 'Shows',
        resourcePath: '/shows/$id.strm',
        doubanId: '1001',
        imdbId: 'tt1001',
        tmdbId: '1001',
        tvdbId: '1001',
        wikidataId: 'Q1001',
        tmdbSetId: '2001',
        providerIds: const {'Tmdb': '1001', 'Imdb': 'tt1001'},
        sourceKind: MediaSourceKind.nas,
        sourceName: 'NAS',
        playbackTarget: PlaybackTarget(
          title: 'Episode',
          sourceId: 'nas-one',
          sourceName: 'NAS',
          sourceKind: MediaSourceKind.nas,
          streamUrl: 'https://media.example.com/$id',
          actualAddress: '/shows/$id.strm',
          originalTitle: 'Original episode',
          allowResume: false,
          itemId: id,
          itemType: 'Episode',
          year: 2026,
          imdbId: 'tt1001',
          tmdbId: '1001',
          seriesId: 'series-one',
          seriesTitle: 'Series',
          preferredMediaSourceId: 'source-one',
          headers: const {
            'Referer': 'https://media.example.com/',
            'Authorization': 'playback-secret',
            'X-Empty': '',
          },
          posterUrl: 'https://images.example.com/playback.jpg',
          posterHeaders: const {'Authorization': 'image-only-secret'},
          backdropUrl: 'https://images.example.com/playback-bg.jpg',
          backdropHeaders: const {'Authorization': 'image-only-secret'},
          subtitle: 'Cached playback description',
          externalSubtitleFilePath: '/local/subtitle.srt',
          externalSubtitleDisplayName: 'Local subtitles',
          container: 'iso',
          videoCodec: 'hevc',
          audioCodec: 'eac3',
          seasonNumber: 2,
          episodeNumber: 3,
          width: 3840,
          height: 2160,
          bitrate: 20000000,
          fileSizeBytes: 20000000000,
        ),
      ),
    );

FavoriteSyncDocument documentWithFavorites(List<SearchResult> items) {
  var result = FavoriteSyncDocument();
  for (final item in items) {
    result = result.setFavorite(searchResultFavoriteKey(item), item);
  }
  return result;
}

FavoriteSyncDocument documentOf(SearchResult result) =>
    FavoriteSyncDocument().setFavorite(searchResultFavoriteKey(result), result);

void main() {
  test('compact roundtrip preserves resource identity and usable playback', () {
    final original = richFavorite();
    final document = documentOf(original);
    final raw = document.encodeForSync();
    final compact = FavoriteSyncDocument.decode(raw);
    final result = compact.favorites.single;
    expect(searchResultFavoriteKey(result), searchResultFavoriteKey(original));
    expect(favoriteSyncResultJson(result), favoriteSyncResultJson(original));
    expect(result.resourceUrl, original.resourceUrl);
    expect(result.password, 'abcd');
    expect(result.favoriteFolderName, 'My folder');
    expect(result.originalSearchTitle, 'Original query');
    expect(result.tmdbId, '1001');
    expect(
        result.detailTarget!.providerIds, original.detailTarget!.providerIds);
    final playback = result.detailTarget!.playbackTarget!;
    expect(playback.canPlay, isTrue);
    expect(playback.isIsoLike, isTrue);
    expect(playback.allowResume, isFalse);
    expect(playback.headers, original.detailTarget!.playbackTarget!.headers);
    expect(playback.externalSubtitleFilePath, isEmpty);
    expect(playback.width, 3840);
    expect(playback.fileSizeBytes, 20000000000);
    expect(isHeavyPlaybackTargetMetadata(playback), isTrue);
    expect(result.posterUrl, isEmpty);
    expect(result.summary, isEmpty);
    expect(result.detailTarget!.overview, isEmpty);
    expect(result.detailTarget!.actorProfiles, isEmpty);
    for (final field in [
      'posterUrl',
      'posterHeaders',
      'backdropUrl',
      'backdropHeaders',
      'logoUrl',
      'logoHeaders',
      'bannerUrl',
      'bannerHeaders',
      'extraBackdropUrls',
      'extraBackdropHeaders',
      'imageUrls',
      'summary',
      'overview',
      'ratingLabels',
      'directorProfiles',
      'actorProfiles',
      'platformProfiles',
      'externalSubtitleFilePath',
    ]) {
      expect(raw, isNot(contains('"$field":')), reason: field);
    }
    expect(raw, isNot(contains('image-only-secret')));
    expect(compact.encodeForSync(), raw);
    expect(FavoriteSyncDocument.decode(document.encode()).encode(),
        document.encode());
    expect(document.encode(), contains('image-only-secret'));
  });

  test('detail and linkless identities survive compact encoding', () {
    final detail = richFavorite().copyWith(resourceUrl: '');
    final fallback = SearchResult.fromJson({
      ...detail.toJson(),
      'detailTarget': null,
      'summary': 'Linkless identity',
    });
    for (final result in [
      detail,
      fallback,
      fallback.copyWith(resourceUrl: '<>'),
    ]) {
      final restored =
          FavoriteSyncDocument.decode(documentOf(result).encodeForSync())
              .favorites
              .single;
      expect(
          searchResultFavoriteKey(restored), searchResultFavoriteKey(result));
    }
    expect(favoriteSyncResultJson(detail), isNot(contains('summary')));
    expect(favoriteSyncResultJson(fallback), isNot(contains('summary')));
  });

  test('compact playback retains deferred source and STRM resolution', () {
    final original = richFavorite();
    for (final kind in MediaSourceKind.values) {
      final playback = original.detailTarget!.playbackTarget!
          .copyWith(sourceKind: kind, streamUrl: '');
      final result = original.copyWith(
          detailTarget:
              original.detailTarget!.copyWith(playbackTarget: playback));
      final restored =
          FavoriteSyncDocument.decode(documentOf(result).encodeForSync())
              .favorites
              .single
              .detailTarget!
              .playbackTarget!;
      expect(restored.needsResolution, playback.needsResolution);
      expect(restored.canPlay, playback.canPlay);
    }
  });

  test('presentation-only changes preserve all sync clocks and ordering', () {
    final original = richFavorite();
    final key = searchResultFavoriteKey(original);
    final base = documentOf(original);
    final refreshed = SearchResult.fromJson({
      ...original.toJson(),
      'summary': 'Updated description',
      'imageUrls': ['https://images.example.com/new.jpg'],
      'quality': 'New label',
    }).copyWith(
        posterUrl: 'https://images.example.com/new-poster.jpg',
        detailTarget: original.detailTarget!.copyWith(
            overview: 'Updated plot',
            actors: ['New actor'],
            playbackTarget: original.detailTarget!.playbackTarget!.copyWith(
                posterUrl: 'https://images.example.com/new-playback.jpg')));
    final updated = base.setFavorite(key, refreshed);
    expect(updated.encodeForSync(), base.encodeForSync());
    expect(updated.encode(), isNot(base.encode()));
    expect(updated.entries[key]!.generation, base.entries[key]!.generation);
    expect(updated.entries[key]!.revision, base.entries[key]!.revision);
    expect(updated.entries[key]!.operation, base.entries[key]!.operation);
    expect(updated.entries[key]!.position, base.entries[key]!.position);
    expect(base.merge(updated).encodeForSync(),
        updated.merge(base).encodeForSync());
    final renamed =
        updated.setFavorite(key, refreshed.copyWith(title: 'Renamed'));
    expect(renamed.entries[key]!.revision, base.entries[key]!.revision + 1);
  });

  test('newer core values and clearing fields preserve local presentation', () {
    final original = richFavorite();
    final key = searchResultFavoriteKey(original);
    final local = documentOf(original);
    final remoteBase = FavoriteSyncDocument.decode(local.encodeForSync());
    final remoteResult = remoteBase.favorites.single.copyWith(
        title: 'Renamed', password: '', favoriteFolderName: '', tmdbId: '');
    final remote = remoteBase.setFavorite(key, remoteResult);
    final merged = local.merge(remote).withLocalPresentation(local);
    final result = merged.favorites.single;
    expect(merged.encodeForSync(), remote.encodeForSync());
    expect(result.title, 'Renamed');
    expect(result.password, isEmpty);
    expect(result.favoriteFolderName, isEmpty);
    expect(result.tmdbId, isEmpty);
    expect(result.posterUrl, original.posterUrl);
    expect(result.posterHeaders, original.posterHeaders);
    expect(result.summary, original.summary);
    expect(result.detailTarget!.toJson(), original.detailTarget!.toJson());
  });

  test('changed targets do not reuse stale nested caches or transport headers',
      () {
    final original = richFavorite();
    final compact = SearchResult.fromJson(favoriteSyncResultJson(original));
    final playback = compact.detailTarget!.playbackTarget!
        .copyWith(streamUrl: 'https://media.example.com/changed', headers: {});
    final changedPlayback = compact.copyWith(
        detailTarget: compact.detailTarget!.copyWith(playbackTarget: playback));
    final restored = preserveFavoritePresentation(changedPlayback, original);
    expect(restored.detailTarget!.posterUrl, original.detailTarget!.posterUrl);
    expect(restored.detailTarget!.playbackTarget!.posterUrl, isEmpty);
    expect(restored.detailTarget!.playbackTarget!.externalSubtitleFilePath,
        isEmpty);
    expect(restored.detailTarget!.playbackTarget!.headers, isEmpty);
    final changedDetail = compact.copyWith(
        detailTarget: compact.detailTarget!.copyWith(itemId: 'different-item'));
    expect(
        preserveFavoritePresentation(changedDetail, original)
            .detailTarget!
            .posterUrl,
        isEmpty);
    final withoutDetail =
        SearchResult.fromJson({...compact.toJson(), 'detailTarget': null});
    expect(preserveFavoritePresentation(withoutDetail, original).detailTarget,
        isNull);
  });

  test('compact tombstones prevent restoration by stale presentation caches',
      () {
    final original = richFavorite();
    final key = searchResultFavoriteKey(original);
    final local = documentOf(original);
    final deleted = local.setFavorite(key, null);
    final remote = FavoriteSyncDocument.decode(deleted.encodeForSync());
    expect(remote.encodeForSync(), deleted.encodeForSync());
    expect(remote.merge(local).withLocalPresentation(local).favorites, isEmpty);
    expect(local.merge(remote).withLocalPresentation(local).favorites, isEmpty);
    expect(remote.entries[key]!.deleted, isTrue);
  });

  test('string maps have stable ordering and retain explicit empty headers',
      () {
    final original = richFavorite();
    final reversed = original.copyWith(
        detailTarget: original.detailTarget!.copyWith(
            providerIds: {'Imdb': 'tt1001', 'Tmdb': '1001'},
            playbackTarget:
                original.detailTarget!.playbackTarget!.copyWith(headers: {
              'X-Empty': '',
              'Authorization': 'playback-secret',
              'Referer': 'https://media.example.com/'
            })));
    final base = documentOf(original);
    expect(
        base
            .setFavorite(searchResultFavoriteKey(original), reversed)
            .encodeForSync(),
        base.encodeForSync());
    expect(favoriteSyncResultJson(original)['posterHeaders'], isNull);
  });

  test('rich sample is materially smaller without discarding records', () {
    final original =
        documentWithFavorites(List.generate(50, (i) => richFavorite('$i')));
    final fullBytes = utf8.encode(original.encode()).length;
    final compactBytes = utf8.encode(original.encodeForSync()).length;
    expect(compactBytes, lessThan(fullBytes * 0.4));
    expect(FavoriteSyncDocument.decode(original.encodeForSync()).entries.length,
        50);
    // Synthetic payload measurement, not an end-to-end network benchmark.
    // ignore: avoid_print
    print('Favorite sample: $fullBytes -> $compactBytes bytes '
        '(${(100 * (1 - compactBytes / fullBytes)).toStringAsFixed(1)}% smaller)');
  });
}
