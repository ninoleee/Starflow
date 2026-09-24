import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';

void main() {
  test('inspect reboot life structure inference', () {
    const source = MediaSourceConfig(
      id: 'reboot-structure',
      name: 'NAS',
      kind: MediaSourceKind.nas,
      endpoint: 'https://webdav.nux.ink/movies/strm/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
      webDavSeriesTitleFilterKeywords: ['quark', 'movies', 'strm', '115'],
    );
    const root = '/movies/strm/quark/重启人生';
    const releaseFolders = <String>[
      '重启人生.全10集.日语中字.无水印.1080P',
      '重启人生.全10集.中日双字.追新番字幕组.720P',
      '重启人生.全10集.中日双字.B站特效字幕版.1080P',
    ];
    final items = <ExternalScanPendingItem>[];
    for (var folderIndex = 0; folderIndex < releaseFolders.length; folderIndex++) {
      final folder = releaseFolders[folderIndex];
      for (var episode = 1; episode <= 10; episode++) {
        final number = episode.toString().padLeft(2, '0');
        final fileName = folderIndex == 2
            ? '重启人生$number 标题.$number.(mp4).strm'
            : '重启人生$number.(mkv).strm';
        items.add(
          _item(
            id: '$folderIndex-$episode',
            address: '$root/$folder/$fileName',
            directories: const ['strm', 'quark', '重启人生'],
          ),
        );
      }
    }
    for (var episode = 1; episode <= 9; episode++) {
      final number = episode.toString().padLeft(2, '0');
      items.add(
        _item(
          id: 'special-$episode',
          address: '$root/番外篇/番外$number.(mp4).strm',
          directories: const ['strm', 'quark', '重启人生', '番外篇'],
        ),
      );
    }

    final resolved =
        applyExternalDirectoryStructureInference(items, source: source);
    debugPrint(
      resolved
          .map(
            (item) =>
                '${item.resourceId}|${item.metadataSeed.itemType}|'
                '${item.metadataSeed.title}|${item.metadataSeed.seasonNumber}|'
                '${item.metadataSeed.episodeNumber}',
          )
          .join('\n'),
    );
  });
}

ExternalScanPendingItem _item({
  required String id,
  required String address,
  required List<String> directories,
}) {
  return ExternalScanPendingItem(
    resourceId: id,
    fileName: address.split('/').last,
    actualAddress: address,
    sectionId: 'https://webdav.nux.ink/movies/strm/',
    sectionName: 'strm',
    streamUrl: 'https://media.example.com/$id',
    streamHeaders: const {},
    addedAt: DateTime.utc(2026, 9, 23),
    modifiedAt: DateTime.utc(2026, 9, 23),
    fileSizeBytes: 1,
    metadataSeed: WebDavMetadataSeed(
      title: address.split('/').last,
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
