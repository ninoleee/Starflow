import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  group('PlaybackTarget playback readiness', () {
    test('treats emby target without stream url but with item id as resolvable',
        () {
      const target = PlaybackTarget(
        title: 'Emby Movie',
        sourceId: 'emby-main',
        streamUrl: '',
        sourceName: 'Emby',
        sourceKind: MediaSourceKind.emby,
        itemId: 'movie-1',
      );

      expect(target.needsResolution, isTrue);
      expect(target.canPlay, isTrue);
    });

    test(
        'treats quark target without stream url but with item id as resolvable',
        () {
      const target = PlaybackTarget(
        title: 'Quark Movie',
        sourceId: 'quark-main',
        streamUrl: '',
        sourceName: 'Quark',
        sourceKind: MediaSourceKind.quark,
        itemId: 'movie-1',
      );

      expect(target.needsResolution, isTrue);
      expect(target.canPlay, isTrue);
    });

    test('treats nas strm target as resolvable', () {
      const target = PlaybackTarget(
        title: 'NAS STRM',
        sourceId: 'nas-main',
        streamUrl: '',
        sourceName: 'NAS',
        sourceKind: MediaSourceKind.nas,
        actualAddress: r'\\nas\videos\movie.strm',
      );

      expect(target.needsResolution, isTrue);
      expect(target.canPlay, isTrue);
    });

    test('does not allow playback when no url and no resolution path exists',
        () {
      const target = PlaybackTarget(
        title: 'Invalid',
        sourceId: 'nas-main',
        streamUrl: '',
        sourceName: 'NAS',
        sourceKind: MediaSourceKind.nas,
      );

      expect(target.needsResolution, isFalse);
      expect(target.canPlay, isFalse);
    });
  });

  group('PlaybackTarget.isIsoLike', () {
    test('detects ISO from container name', () {
      const target = PlaybackTarget(
        title: 'Movie ISO',
        sourceId: 'emby-main',
        streamUrl: 'https://example.com/videos/movie',
        sourceName: 'Emby',
        sourceKind: MediaSourceKind.emby,
        container: 'iso',
      );

      expect(target.isIsoLike, isTrue);
    });

    test('detects ISO from stream url', () {
      const target = PlaybackTarget(
        title: 'Movie ISO',
        sourceId: 'nas-main',
        streamUrl: 'https://example.com/videos/movie.iso?token=abc',
        sourceName: 'NAS',
        sourceKind: MediaSourceKind.nas,
      );

      expect(target.isIsoLike, isTrue);
    });

    test('detects ISO from file uri', () {
      const target = PlaybackTarget(
        title: 'Movie ISO',
        sourceId: 'local-main',
        streamUrl: 'file:///D:/Movies/Movie.iso',
        sourceName: 'Local',
        sourceKind: MediaSourceKind.nas,
      );

      expect(target.isIsoLike, isTrue);
    });

    test('detects ISO from actual address path', () {
      const target = PlaybackTarget(
        title: 'Movie ISO',
        sourceId: 'local-main',
        streamUrl: '',
        sourceName: 'Local',
        sourceKind: MediaSourceKind.nas,
        actualAddress: r'D:\Movies\Movie.ISO',
      );

      expect(target.isIsoLike, isTrue);
    });

    test('detects ISO from unc path with mixed casing', () {
      const target = PlaybackTarget(
        title: 'Movie ISO',
        sourceId: 'nas-main',
        streamUrl: '',
        sourceName: 'NAS',
        sourceKind: MediaSourceKind.nas,
        actualAddress: r'\\NAS\Movies\Movie.Iso',
      );

      expect(target.isIsoLike, isTrue);
    });

    test('does not flag regular media as ISO', () {
      const target = PlaybackTarget(
        title: 'Movie MKV',
        sourceId: 'emby-main',
        streamUrl: 'https://example.com/videos/movie.mkv',
        sourceName: 'Emby',
        sourceKind: MediaSourceKind.emby,
        actualAddress: r'D:\Movies\Movie.mkv',
        container: 'mkv',
      );

      expect(target.isIsoLike, isFalse);
    });
  });
}
