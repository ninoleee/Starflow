import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';

void main() {
  const source = MediaSourceConfig(
    id: 'nas-real-world-structure',
    name: 'NAS',
    kind: MediaSourceKind.nas,
    endpoint: 'https://nas.example.com/movies/',
    enabled: true,
    webDavStructureInferenceEnabled: true,
    webDavSeriesTitleFilterKeywords: ['movies', 'strm', 'quark'],
  );

  test('groups SE folders under the parent series with explicit episodes', () {
    final resolved = applyExternalDirectoryStructureInference(
      [
        _pendingItem(
          id: 'friends-s08e06',
          address:
              '/movies/strm/quark/老友记/SE08/老友记.H265.1080P.SE08.06.(mkv).strm',
          directories: const ['strm', 'quark', '老友记', 'SE08'],
        ),
        _pendingItem(
          id: 'friends-s02e03',
          address:
              '/movies/strm/quark/老友记/SE02/老友记.H265.1080P.SE02.03.(mkv).strm',
          directories: const ['strm', 'quark', '老友记', 'SE02'],
        ),
      ],
      source: source,
    );

    final seasonEight =
        resolved.singleWhere((item) => item.resourceId == 'friends-s08e06');
    expect(seasonEight.metadataSeed.itemType, 'episode');
    expect(seasonEight.metadataSeed.seasonNumber, 8);
    expect(seasonEight.metadataSeed.episodeNumber, 6);

    final seasonTwo =
        resolved.singleWhere((item) => item.resourceId == 'friends-s02e03');
    expect(seasonTwo.metadataSeed.itemType, 'episode');
    expect(seasonTwo.metadataSeed.seasonNumber, 2);
    expect(seasonTwo.metadataSeed.episodeNumber, 3);
  });

  test('groups hash-numbered interview folders into season one', () {
    final resolved = applyExternalDirectoryStructureInference(
      [
        _pendingItem(
          id: 'luyu-19',
          address: '/movies/strm/quark/陈鲁豫/陈鲁豫 · 慢谈 #19 对话张泉灵/video.strm',
          directories: const [
            'strm',
            'quark',
            '陈鲁豫',
            '陈鲁豫 · 慢谈 #19 对话张泉灵',
          ],
        ),
        _pendingItem(
          id: 'luyu-02',
          address: '/movies/strm/quark/陈鲁豫/陈鲁豫 · 慢谈 #02 对话陈奕迅/video.strm',
          directories: const [
            'strm',
            'quark',
            '陈鲁豫',
            '陈鲁豫 · 慢谈 #02 对话陈奕迅',
          ],
        ),
      ],
      source: source,
    );

    expect(
      resolved.map((item) => item.metadataSeed.itemType),
      everyElement('episode'),
    );
    expect(
      resolved.map((item) => item.metadataSeed.seasonNumber),
      everyElement(1),
    );
    expect(
      resolved.map((item) => item.metadataSeed.episodeNumber).toSet(),
      {2, 19},
    );
  });
}

ExternalScanPendingItem _pendingItem({
  required String id,
  required String address,
  required List<String> directories,
}) {
  final fileName = address.split('/').last;
  return ExternalScanPendingItem(
    resourceId: id,
    fileName: fileName,
    actualAddress: address,
    sectionId: 'movies',
    sectionName: 'movies',
    streamUrl: 'https://media.example.com/$id',
    streamHeaders: const {},
    addedAt: DateTime.utc(2026, 8, 8),
    modifiedAt: DateTime.utc(2026, 8, 8),
    fileSizeBytes: 1,
    metadataSeed: WebDavMetadataSeed(
      title: fileName,
      overview: '',
      posterUrl: '',
      posterHeaders: const {},
      backdropUrl: '',
      backdropHeaders: const {},
      logoUrl: '',
      logoHeaders: const {},
      bannerUrl: '',
      bannerHeaders: const {},
      extraBackdropUrls: const [],
      extraBackdropHeaders: const {},
      year: 0,
      durationLabel: '',
      genres: const [],
      directors: const [],
      actors: const [],
      itemType: '',
      seasonNumber: null,
      episodeNumber: null,
      imdbId: '',
      tmdbId: '',
      container: '',
      videoCodec: '',
      audioCodec: '',
      width: null,
      height: null,
      bitrate: null,
      hasSidecarMatch: false,
    ),
    relativeDirectories: directories,
  );
}
