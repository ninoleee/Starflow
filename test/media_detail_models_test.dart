import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  group('MediaDetailTarget.needsMetadataMatch', () {
    test('returns true when poster exists but rich metadata is missing', () {
      const target = MediaDetailTarget(
        title: 'Inception',
        posterUrl: 'https://example.com/poster.jpg',
        overview: '',
      );

      expect(target.needsMetadataMatch, isTrue);
    });

    test('returns true when overview is only a raw url', () {
      const target = MediaDetailTarget(
        title: 'Movie File',
        posterUrl: '',
        overview: 'https://nas.local/dav/movies/file.mkv',
      );

      expect(target.needsMetadataMatch, isTrue);
    });

    test('returns false when overview or cast data is already useful', () {
      const target = MediaDetailTarget(
        title: 'Arrival',
        posterUrl: 'https://example.com/poster.jpg',
        overview: 'A linguist works with the military after alien crafts land.',
      );

      expect(target.needsMetadataMatch, isFalse);
    });
  });

  group('MediaDetailTarget.needsImdbRatingMatch', () {
    test('returns true when only non-IMDb ratings exist', () {
      const target = MediaDetailTarget(
        title: 'Inception',
        posterUrl: '',
        overview: '',
        ratingLabels: ['豆瓣 8.8'],
      );

      expect(target.needsImdbRatingMatch, isTrue);
    });

    test('returns false when IMDb rating already exists', () {
      const target = MediaDetailTarget(
        title: 'Inception',
        posterUrl: '',
        overview: '',
        ratingLabels: ['IMDb 8.7', '豆瓣 8.8'],
      );

      expect(target.needsImdbRatingMatch, isFalse);
    });
  });

  group('MediaDetailTarget.fromMediaItem', () {
    test('does not mark non-playable items as ready resources', () {
      final target = MediaDetailTarget.fromMediaItem(
        MediaItem(
          id: 'series-1',
          title: 'Lost',
          overview: '',
          posterUrl: '',
          year: 0,
          durationLabel: '剧集',
          genres: const [],
          itemType: 'series',
          sourceId: 'webdav-1',
          sourceName: 'WebDAV',
          sourceKind: MediaSourceKind.nas,
          streamUrl: '',
          addedAt: DateTime(2026),
        ),
      );

      expect(target.availabilityLabel, isEmpty);
      expect(target.isPlayable, isFalse);
    });

    test('preserves tmdb id from media item', () {
      final target = MediaDetailTarget.fromMediaItem(
        MediaItem(
          id: 'movie-1',
          title: 'Avatar',
          overview: '',
          posterUrl: '',
          year: 2009,
          durationLabel: '162分钟',
          genres: const [],
          sourceId: 'emby-main',
          sourceName: 'Home Emby',
          sourceKind: MediaSourceKind.emby,
          streamUrl: '',
          tmdbId: '19995',
          addedAt: DateTime(2026),
        ),
      );

      expect(target.tmdbId, '19995');
    });
  });

  group('MediaDetailTarget.canManuallyMatchLibraryResource', () {
    test('stays available when resource status is none', () {
      const target = MediaDetailTarget(
        title: 'The Last of Us',
        posterUrl: '',
        overview: '',
        availabilityLabel: '无',
        sourceId: 'douban-seed',
        itemId: 'subject-1',
        sourceName: '豆瓣',
      );

      expect(target.needsLibraryMatch, isFalse);
      expect(target.canManuallyMatchLibraryResource, isTrue);
    });

    test('stops showing once playable resource is ready', () {
      const target = MediaDetailTarget(
        title: 'The Last of Us',
        posterUrl: '',
        overview: '',
        availabilityLabel: '资源已就绪：Emby · Home Emby',
        playbackTarget: PlaybackTarget(
          title: 'The Last of Us',
          sourceId: 'emby-main',
          streamUrl: 'https://example.com/video.mp4',
          sourceName: 'Home Emby',
          sourceKind: MediaSourceKind.emby,
        ),
      );

      expect(target.canManuallyMatchLibraryResource, isFalse);
    });
  });

  group('MediaDetailTarget.shouldAutoMatchLibraryResource', () {
    test('auto matches only when local resource is still missing', () {
      const target = MediaDetailTarget(
        title: 'The Last of Us',
        posterUrl: '',
        overview: '',
        availabilityLabel: '无',
      );

      expect(target.needsLibraryMatch, isTrue);
      expect(target.shouldAutoMatchLibraryResource, isTrue);
    });

    test('does not auto match when series already has linked resource', () {
      const target = MediaDetailTarget(
        title: 'The Last of Us',
        posterUrl: '',
        overview: '',
        sourceId: 'webdav-main',
        itemId: 'series-1',
        sourceName: 'WebDAV',
      );

      expect(target.needsLibraryMatch, isFalse);
      expect(target.shouldAutoMatchLibraryResource, isFalse);
      expect(target.canManuallyMatchLibraryResource, isTrue);
    });
  });
}
