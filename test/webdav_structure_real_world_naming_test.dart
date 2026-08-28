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

  test('uses leading ordinals to order direct files in a known series', () {
    final resolved = applyExternalDirectoryStructureInference(
      [
        _pendingItem(
          id: 'food-10',
          address: '/movies/strm/quark/食贫道/10.神佑之地.(mp4).strm',
          directories: const ['strm', 'quark', '食贫道'],
        ),
        _pendingItem(
          id: 'food-2',
          address: '/movies/strm/quark/食贫道/2.迦南孤儿.(mp4).strm',
          directories: const ['strm', 'quark', '食贫道'],
        ),
        _pendingItem(
          id: 'food-28',
          address: '/movies/strm/quark/食贫道/28.首尔夏天.(mp4).strm',
          directories: const ['strm', 'quark', '食贫道'],
        ),
        _pendingItem(
          id: 'food-1',
          address: '/movies/strm/quark/食贫道/1.迷失东京.(mp4).strm',
          directories: const ['strm', 'quark', '食贫道'],
        ),
      ],
      source: source,
    );

    expect(
      {
        for (final item in resolved)
          item.resourceId: item.metadataSeed.episodeNumber,
      },
      {
        'food-1': 1,
        'food-2': 2,
        'food-10': 10,
        'food-28': 28,
      },
    );
    expect(
      resolved.map((item) => item.metadataSeed.seasonNumber),
      everyElement(1),
    );
  });

  test('keeps year folders but collapses unclear quality-count wrappers', () {
    final resolved = applyExternalDirectoryStructureInference(
      [
        _pendingItem(
          id: 'call-me-2025-01',
          address: '/movies/strm/quark/披荆斩棘2026/2025/第01期.strm',
          directories: const ['strm', 'quark', '披荆斩棘2026', '2025'],
        ),
        _pendingItem(
          id: 'call-me-2025-02',
          address: '/movies/strm/quark/披荆斩棘2026/2025/第02期.strm',
          directories: const ['strm', 'quark', '披荆斩棘2026', '2025'],
        ),
        _pendingItem(
          id: 'call-me-2026-01',
          address: '/movies/strm/quark/披荆斩棘2026/2026（4K）/第01期.strm',
          directories: const ['strm', 'quark', '披荆斩棘2026', '2026（4K）'],
        ),
        _pendingItem(
          id: 'call-me-4k-count-01',
          address: '/movies/strm/quark/披荆斩棘2026/4K 12集/第03期.strm',
          directories: const ['strm', 'quark', '披荆斩棘2026', '4K 12集'],
        ),
      ],
      source: source,
    );

    expect(resolved, hasLength(4));
    expect(
      resolved.map((item) => item.metadataSeed.itemType),
      everyElement('episode'),
    );
    expect(
      resolved.map((item) => item.metadataSeed.seasonNumber),
      everyElement(isNotNull),
    );
    expect(
      resolved.map((item) => item.metadataSeed.seasonNumber).toSet(),
      {1, 2, 3},
    );
    expect(
      resolved
          .singleWhere((item) => item.resourceId == 'call-me-4k-count-01')
          .metadataSeed
          .seasonNumber,
      1,
    );
    expect(
      resolved
          .singleWhere((item) => item.resourceId == 'call-me-2025-01')
          .metadataSeed
          .seasonNumber,
      2,
    );
    expect(
      resolved
          .singleWhere((item) => item.resourceId == 'call-me-2026-01')
          .metadataSeed
          .seasonNumber,
      3,
    );
  });

  test('keeps collapsed wrapper episodes out of a root specials group', () {
    final resolved = applyExternalDirectoryStructureInference(
      [
        _pendingItem(
          id: 'show-special',
          address: '/movies/strm/quark/节目/花絮.strm',
          directories: const ['strm', 'quark', '节目'],
        ),
        _pendingItem(
          id: 'show-main-episode',
          address: '/movies/strm/quark/节目/4K 12集/第01期.strm',
          directories: const ['strm', 'quark', '节目', '4K 12集'],
        ),
      ],
      source: source,
    );

    expect(
      resolved
          .singleWhere((item) => item.resourceId == 'show-special')
          .metadataSeed
          .seasonNumber,
      0,
    );
    expect(
      resolved
          .singleWhere((item) => item.resourceId == 'show-main-episode')
          .metadataSeed
          .seasonNumber,
      1,
    );
  });

  test('keeps movie version directories as movies instead of seasons', () {
    final resolved = applyExternalDirectoryStructureInference(
      [
        _pendingItem(
          id: 'basterds-1080p',
          address:
              '/movies/strm/quark/无耻混蛋/1080P.国英双语.双语特效字幕/无耻混蛋.2009.1080p.strm',
          directories: const [
            'strm',
            'quark',
            '无耻混蛋',
            '1080P.国英双语.双语特效字幕',
          ],
        ),
        _pendingItem(
          id: 'basterds-4k',
          address:
              '/movies/strm/quark/无耻混蛋/4K.国英双语.双语特效字幕/无耻混蛋.2009.2160p.strm',
          directories: const [
            'strm',
            'quark',
            '无耻混蛋',
            '4K.国英双语.双语特效字幕',
          ],
        ),
        _pendingItem(
          id: 'basterds-english',
          address:
              '/movies/strm/quark/无耻混蛋/4K.英语.外挂简繁特效/无耻混蛋.2009.english.strm',
          directories: const [
            'strm',
            'quark',
            '无耻混蛋',
            '4K.英语.外挂简繁特效',
          ],
        ),
        _pendingItem(
          id: 'basterds-high-bitrate',
          address:
              '/movies/strm/quark/无耻混蛋/4K.高码.国英双语.双语特效字幕/无耻混蛋.2009.high-bitrate.strm',
          directories: const [
            'strm',
            'quark',
            '无耻混蛋',
            '4K.高码.国英双语.双语特效字幕',
          ],
        ),
      ],
      source: source,
    );

    expect(resolved, hasLength(4));
    expect(
      resolved.map((item) => item.metadataSeed.itemType),
      everyElement('movie'),
    );
    expect(
      resolved.map((item) => item.metadataSeed.title),
      everyElement('无耻混蛋'),
    );
    expect(
      resolved.map((item) => item.metadataSeed.seasonNumber),
      everyElement(isNull),
    );
    expect(
      resolved.map((item) => item.metadataSeed.episodeNumber),
      everyElement(isNull),
    );
  });

  test('uses the outer movie folder for one nested release wrapper', () {
    final resolved = applyExternalDirectoryStructureInference(
      [
        _pendingItem(
          id: 'setouchi-single-release',
          address:
              '/movies/strm/quark/濑户内海/濑户内海（2016）日语中字/Seto.Utsumi.2016.mkv.strm',
          directories: const [
            'strm',
            'quark',
            '濑户内海',
            '濑户内海（2016）日语中字',
          ],
        ),
      ],
      source: source,
    );

    expect(resolved, hasLength(1));
    expect(resolved.single.metadataSeed.itemType, 'movie');
    expect(resolved.single.metadataSeed.title, '濑户内海');
    expect(resolved.single.metadataSeed.seasonNumber, isNull);
    expect(resolved.single.metadataSeed.episodeNumber, isNull);
  });

  test('keeps a single video in a first-level movie folder as a movie', () {
    final resolved = applyExternalDirectoryStructureInference(
      [
        _pendingItem(
          id: 'lock-stock-single',
          address: '/movies/strm/quark/两杆大烟枪/Lock.Stock.1998.mkv.strm',
          directories: const ['strm', 'quark', '两杆大烟枪'],
        ),
      ],
      source: source,
    );

    expect(resolved, hasLength(1));
    expect(resolved.single.metadataSeed.itemType, 'movie');
    expect(resolved.single.metadataSeed.seasonNumber, isNull);
    expect(resolved.single.metadataSeed.episodeNumber, isNull);
  });

  test(
      'does not promote a single movie because a transport sibling is a series',
      () {
    final resolved = applyExternalDirectoryStructureInference(
      [
        _pendingItem(
          id: 'lock-stock-real-name',
          address:
              '/movies/strm/quark/两杆大烟枪/Top026.两杆大烟枪.Lock.Stock.and.Two.Smoking.Barrels.1998.Bluray.1080p.x265.AAC.(mkv).strm',
          directories: const ['strm', 'quark', '两杆大烟枪'],
        ),
        _pendingItem(
          id: 'series-s01e01',
          address: '/movies/strm/quark/示例剧/S01/示例剧.S01E01.mkv.strm',
          directories: const ['strm', 'quark', '示例剧', 'S01'],
        ),
        _pendingItem(
          id: 'root-series-s01e01',
          address: '/movies/独立剧/S01/独立剧.S01E01.mkv.strm',
          directories: const ['独立剧', 'S01'],
        ),
      ],
      source: source,
    );

    final movie = resolved.singleWhere(
      (item) => item.resourceId == 'lock-stock-real-name',
    );
    expect(movie.metadataSeed.itemType, 'movie');
    expect(movie.metadataSeed.seasonNumber, isNull);
    expect(movie.metadataSeed.episodeNumber, isNull);

    final episode = resolved.singleWhere(
      (item) => item.resourceId == 'series-s01e01',
    );
    expect(episode.metadataSeed.itemType, 'episode');
    expect(episode.metadataSeed.seasonNumber, 1);
    expect(episode.metadataSeed.episodeNumber, 1);

    final rootEpisode = resolved.singleWhere(
      (item) => item.resourceId == 'root-series-s01e01',
    );
    expect(rootEpisode.metadataSeed.itemType, 'episode');
  });

  test('keeps 偶然与想象 single-file directory as a movie', () {
    final resolved = applyExternalDirectoryStructureInference(
      [
        _pendingItem(
          id: 'wheel-of-fortune-single',
          address:
              '/movies/strm/quark/偶然与想象/Wheel.of.Fortune.and.Fantasy.2021.1080p.BluRay.DTS-HD.MA.5.1.x265.10bit-DreamHD.(mkv).strm',
          directories: const ['strm', 'quark', '偶然与想象'],
        ),
      ],
      source: source,
    );

    expect(resolved, hasLength(1));
    expect(resolved.single.metadataSeed.itemType, 'movie');
    expect(resolved.single.metadataSeed.seasonNumber, isNull);
    expect(resolved.single.metadataSeed.episodeNumber, isNull);
  });

  test('keeps a single video under an explicit season as an episode', () {
    final resolved = applyExternalDirectoryStructureInference(
      [
        _pendingItem(
          id: 'single-season-episode',
          address: '/movies/strm/quark/示例剧/Season 1/示例剧.S01E01.mkv.strm',
          directories: const ['strm', 'quark', '示例剧', 'Season 1'],
        ),
      ],
      source: source,
    );

    expect(resolved, hasLength(1));
    expect(resolved.single.metadataSeed.itemType, 'episode');
    expect(resolved.single.metadataSeed.seasonNumber, 1);
    expect(resolved.single.metadataSeed.episodeNumber, 1);
  });

  test('treats unknown child directories as seasons of the parent series', () {
    final resolved = applyExternalDirectoryStructureInference(
      [
        _pendingItem(
          id: 'unknown-season-a',
          address: '/movies/strm/quark/示例剧/内容A/video-a.mkv.strm',
          directories: const ['strm', 'quark', '示例剧', '内容A'],
        ),
        _pendingItem(
          id: 'unknown-season-b',
          address: '/movies/strm/quark/示例剧/内容B/video-b.mkv.strm',
          directories: const ['strm', 'quark', '示例剧', '内容B'],
        ),
      ],
      source: source,
    );

    expect(resolved, hasLength(2));
    expect(
      resolved.map((item) => item.metadataSeed.itemType),
      everyElement('episode'),
    );
    expect(
      resolved.map((item) => item.metadataSeed.seasonNumber).toSet(),
      {1, 2},
    );
  });

  test('keeps direct specials and a child episode folder under one series', () {
    final resolved = applyExternalDirectoryStructureInference(
      [
        _pendingItem(
          id: 'watashi-special-before',
          address: '/movies/strm/quark/我的事说来话长/我的事说来话长.2025春SP.前篇.strm',
          directories: const ['strm', 'quark', '我的事说来话长'],
        ),
        _pendingItem(
          id: 'watashi-special-after',
          address: '/movies/strm/quark/我的事说来话长/我的事说来话长.2025春SP.后篇.strm',
          directories: const ['strm', 'quark', '我的事说来话长'],
        ),
        ...List.generate(
          10,
          (index) => _pendingItem(
            id: 'watashi-episode-${index + 1}',
            address:
                '/movies/strm/quark/我的事说来话长/剧版/${(index + 1).toString().padLeft(2, '0')}.(mkv).strm',
            directories: const ['strm', 'quark', '我的事说来话长', '剧版'],
          ),
        ),
      ],
      source: source,
    );

    expect(resolved, hasLength(12));
    expect(
      resolved.map((item) => item.metadataSeed.itemType),
      everyElement('episode'),
    );
    expect(
      resolved
          .where((item) => item.resourceId.startsWith('watashi-episode-'))
          .map((item) => item.metadataSeed.seasonNumber),
      everyElement(1),
    );
    expect(
      resolved
          .where((item) => item.resourceId.startsWith('watashi-special-'))
          .map((item) => item.metadataSeed.seasonNumber),
      everyElement(0),
    );
  });

  test('keeps the outer title across multiple nested release wrappers', () {
    final resolved = applyExternalDirectoryStructureInference(
      [
        _pendingItem(
          id: 'setouchi-1080p',
          address:
              '/movies/strm/quark/濑户内海/濑户内海（2016）日语中字/Setoutsumi.2016.BluRay.1080p.x265.10bit-MiniHD.(mkv).strm',
          directories: const [
            'strm',
            'quark',
            '濑户内海',
            '濑户内海（2016）日语中字',
          ],
        ),
        _pendingItem(
          id: 'setouchi-2160p',
          address:
              '/movies/strm/quark/濑户内海/4K.日语.外挂字幕/Setoutsumi.2016.BluRay.2160p.strm',
          directories: const [
            'strm',
            'quark',
            '濑户内海',
            '4K.日语.外挂字幕',
          ],
        ),
      ],
      source: source,
    );

    expect(resolved, hasLength(2));
    expect(
      resolved.map((item) => item.metadataSeed.itemType),
      everyElement('movie'),
    );
    expect(
      resolved.map((item) => item.metadataSeed.title),
      everyElement('濑户内海'),
    );
  });

  test('keeps episode-marked files inside quality wrappers as episodes', () {
    final resolved = applyExternalDirectoryStructureInference(
      [
        _pendingItem(
          id: 'show-1080p-s01e01',
          address: '/movies/strm/quark/示例剧/1080P.国语版/示例剧.S01E01.1080p.strm',
          directories: const ['strm', 'quark', '示例剧', '1080P.国语版'],
        ),
        _pendingItem(
          id: 'show-4k-s01e01',
          address: '/movies/strm/quark/示例剧/4K.国语版/示例剧.S01E01.2160p.strm',
          directories: const ['strm', 'quark', '示例剧', '4K.国语版'],
        ),
      ],
      source: source,
    );

    expect(
      resolved.map((item) => item.metadataSeed.itemType),
      everyElement('episode'),
    );
    expect(
      resolved.map((item) => item.metadataSeed.episodeNumber),
      everyElement(1),
    );
  });

  test('merges nested files below each movie version directory', () {
    final resolved = applyExternalDirectoryStructureInference(
      [
        _pendingItem(
          id: 'shameless-1080p-part1',
          address: '/movies/strm/quark/无耻之徒/1080P.国语版/Disc 1/part-1.strm',
          directories: const [
            'strm',
            'quark',
            '无耻之徒',
            '1080P.国语版',
            'Disc 1',
          ],
        ),
        _pendingItem(
          id: 'shameless-1080p-part2',
          address: '/movies/strm/quark/无耻之徒/1080P.国语版/Disc 1/part-2.strm',
          directories: const [
            'strm',
            'quark',
            '无耻之徒',
            '1080P.国语版',
            'Disc 1',
          ],
        ),
        _pendingItem(
          id: 'shameless-4k-part1',
          address: '/movies/strm/quark/无耻之徒/4K.国英双语/Remux/part-1.strm',
          directories: const [
            'strm',
            'quark',
            '无耻之徒',
            '4K.国英双语',
            'Remux',
          ],
        ),
        _pendingItem(
          id: 'shameless-4k-part2',
          address: '/movies/strm/quark/无耻之徒/4K.国英双语/Remux/part-2.strm',
          directories: const [
            'strm',
            'quark',
            '无耻之徒',
            '4K.国英双语',
            'Remux',
          ],
        ),
        _pendingItem(
          id: 'shameless-web-part1',
          address: '/movies/strm/quark/无耻之徒/1080P.英语.外挂字幕/WEB/part-1.strm',
          directories: const [
            'strm',
            'quark',
            '无耻之徒',
            '1080P.英语.外挂字幕',
            'WEB',
          ],
        ),
        _pendingItem(
          id: 'shameless-web-part2',
          address: '/movies/strm/quark/无耻之徒/1080P.英语.外挂字幕/WEB/part-2.strm',
          directories: const [
            'strm',
            'quark',
            '无耻之徒',
            '1080P.英语.外挂字幕',
            'WEB',
          ],
        ),
        _pendingItem(
          id: 'shameless-hdr-part1',
          address: '/movies/strm/quark/无耻之徒/4K.高码.国英双语/BDMV/part-1.strm',
          directories: const [
            'strm',
            'quark',
            '无耻之徒',
            '4K.高码.国英双语',
            'BDMV',
          ],
        ),
        _pendingItem(
          id: 'shameless-hdr-part2',
          address: '/movies/strm/quark/无耻之徒/4K.高码.国英双语/BDMV/part-2.strm',
          directories: const [
            'strm',
            'quark',
            '无耻之徒',
            '4K.高码.国英双语',
            'BDMV',
          ],
        ),
      ],
      source: source,
    );

    expect(resolved, hasLength(8));
    expect(
      resolved.map((item) => item.metadataSeed.itemType),
      everyElement('movie'),
    );
    expect(
      resolved.map((item) => item.metadataSeed.title),
      everyElement('无耻之徒'),
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
