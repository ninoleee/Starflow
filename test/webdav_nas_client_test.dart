import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  group('WebDavNasClient', () {
    test('discovers nested videos and resolves strm direct links', () async {
      final client = WebDavNasClient(
        MockClient((request) async {
          if (request.method == 'PROPFIND' &&
              request.url.toString() == 'https://nas.example.com/dav/') {
            return http.Response(_rootPropfindResponse, 207);
          }

          if (request.method == 'PROPFIND' &&
              request.url.toString() == 'https://nas.example.com/dav/Movies/') {
            return http.Response(_moviesPropfindResponse, 207);
          }

          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Movies/extrafanart/') {
            return http.Response(_extraFanartPropfindResponse, 207);
          }

          if (request.method == 'GET' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Movies/movie.nfo') {
            return http.Response.bytes(
              utf8.encode(_movieNfoResponse),
              200,
              headers: const {'content-type': 'application/xml; charset=utf-8'},
            );
          }

          if (request.method == 'GET' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/One%20Piece.strm') {
            return http.Response(
              'https://media.example.com/streams/one-piece/master.m3u8\n',
              200,
            );
          }

          return http.Response('Not Found', 404);
        }),
      );

      final items = await client.fetchLibrary(
        const MediaSourceConfig(
          id: 'nas-main',
          name: 'Home NAS',
          kind: MediaSourceKind.nas,
          endpoint: 'https://nas.example.com/dav/',
          enabled: true,
          username: 'alice',
          password: 'secret',
        ),
        limit: 20,
      );

      expect(items, hasLength(2));

      final movie = items.firstWhere((item) => item.title == '星际穿越');
      expect(
        movie.streamUrl,
        'https://nas.example.com/dav/Movies/Interstellar.mkv',
      );
      expect(movie.title, '星际穿越');
      expect(movie.overview, '一支探险队穿越虫洞寻找人类新家园。');
      expect(movie.posterUrl, 'https://nas.example.com/dav/Movies/poster.jpg');
      expect(movie.posterHeaders['Authorization'], startsWith('Basic '));
      expect(
          movie.backdropUrl, 'https://nas.example.com/dav/Movies/fanart.jpg');
      expect(movie.logoUrl, 'https://nas.example.com/dav/Movies/clearlogo.png');
      expect(movie.bannerUrl, 'https://nas.example.com/dav/Movies/banner.jpg');
      expect(
        movie.extraBackdropUrls,
        contains('https://nas.example.com/dav/Movies/extrafanart/shot1.jpg'),
      );
      expect(movie.year, 2014);
      expect(movie.durationLabel, '169分钟');
      expect(movie.genres, contains('科幻'));
      expect(movie.directors, contains('克里斯托弗·诺兰'));
      expect(movie.actors, contains('马修·麦康纳'));
      expect(movie.imdbId, 'tt0816692');
      expect(movie.container, 'mkv');
      expect(movie.videoCodec, 'hevc');
      expect(movie.audioCodec, 'truehd');
      expect(movie.width, 3840);
      expect(movie.height, 2160);
      expect(movie.bitrate, 18000000);
      expect(movie.fileSizeBytes, 0);
      expect(movie.actualAddress, '/dav/Movies/Interstellar.mkv');
      expect(movie.addedAt, DateTime.utc(2026, 4, 2, 8, 30, 0));

      final strm = items.firstWhere((item) => item.title == 'One Piece');
      expect(
        strm.streamUrl,
        'https://media.example.com/streams/one-piece/master.m3u8',
      );
      expect(strm.actualAddress, '/dav/Shows/One Piece.strm');
      expect(strm.overview, isEmpty);
      expect(strm.addedAt, DateTime.utc(2026, 4, 3, 9, 0, 0));
    });

    test('resolves strm target url from a resource path directly', () async {
      final client = WebDavNasClient(
        MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/One%20Piece.strm') {
            return http.Response('https://pan.quark.cn/s/abc123\n', 200);
          }
          return http.Response('Not Found', 404);
        }),
      );

      final resolvedUrl = await client.resolveStrmTargetUrl(
        source: const MediaSourceConfig(
          id: 'nas-main',
          name: 'Home NAS',
          kind: MediaSourceKind.nas,
          endpoint: 'https://nas.example.com/dav/',
          enabled: true,
          username: 'alice',
          password: 'secret',
        ),
        resourcePath: 'https://nas.example.com/dav/Shows/One%20Piece.strm',
      );

      expect(resolvedUrl, 'https://pan.quark.cn/s/abc123');
    });

    test('discovers iso files as playable media', () async {
      final client = WebDavNasClient(
        MockClient((request) async {
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Movies/') {
            return http.Response(
              '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Movies/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Movies</d:displayname>
        <d:getlastmodified>Fri, 10 Apr 2026 08:00:00 GMT</d:getlastmodified>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Movies/Concert%20Disc.iso</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Concert Disc.iso</d:displayname>
        <d:getcontentlength>734003200</d:getcontentlength>
        <d:getcontenttype>application/octet-stream</d:getcontenttype>
        <d:getlastmodified>Fri, 10 Apr 2026 08:30:00 GMT</d:getlastmodified>
        <d:resourcetype />
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''',
              207,
            );
          }
          return http.Response('Not Found', 404);
        }),
      );

      final items = await client.fetchLibrary(
        const MediaSourceConfig(
          id: 'nas-iso',
          name: 'ISO NAS',
          kind: MediaSourceKind.nas,
          endpoint: 'https://nas.example.com/dav/Movies/',
          enabled: true,
          webDavSidecarScrapingEnabled: false,
        ),
        limit: 20,
      );

      expect(items, hasLength(1));
      expect(items.single.title, 'Concert Disc');
      expect(
        items.single.streamUrl,
        'https://nas.example.com/dav/Movies/Concert%20Disc.iso',
      );
      expect(items.single.actualAddress, '/dav/Movies/Concert Disc.iso');
      expect(items.single.container, 'iso');
      expect(items.single.fileSizeBytes, 734003200);
    });

    test('can disable local sidecar scraping independently from structure',
        () async {
      final client = WebDavNasClient(
        MockClient((request) async {
          if (request.method == 'PROPFIND' &&
              request.url.toString() == 'https://nas.example.com/dav/') {
            return http.Response(_rootPropfindResponse, 207);
          }

          if (request.method == 'PROPFIND' &&
              request.url.toString() == 'https://nas.example.com/dav/Movies/') {
            return http.Response(_moviesPropfindResponse, 207);
          }

          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Movies/extrafanart/') {
            return http.Response(_extraFanartPropfindResponse, 207);
          }

          if (request.method == 'GET' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/One%20Piece.strm') {
            return http.Response(
              'https://media.example.com/streams/one-piece/master.m3u8\n',
              200,
            );
          }

          return http.Response('Not Found', 404);
        }),
      );

      final items = await client.fetchLibrary(
        const MediaSourceConfig(
          id: 'nas-main',
          name: 'Home NAS',
          kind: MediaSourceKind.nas,
          endpoint: 'https://nas.example.com/dav/',
          enabled: true,
          username: 'alice',
          password: 'secret',
          webDavSidecarScrapingEnabled: false,
        ),
        limit: 20,
      );

      final movie = items.firstWhere(
          (item) => item.actualAddress == '/dav/Movies/Interstellar.mkv');
      expect(movie.title, 'Interstellar');
      expect(movie.posterUrl, isEmpty);
      expect(movie.backdropUrl, isEmpty);
      expect(movie.imdbId, isEmpty);
      expect(movie.container, 'mkv');
    });

    test('tolerates malformed percent-encoding in href and path segments',
        () async {
      final client = WebDavNasClient(
        MockClient((request) async {
          if (request.method == 'PROPFIND' &&
              request.url.toString() == 'https://nas.example.com/dav/') {
            return http.Response(_malformedHrefPropfind, 207);
          }
          return http.Response('Not Found', 404);
        }),
      );

      final items = await client.fetchLibrary(
        const MediaSourceConfig(
          id: 'nas-main',
          name: 'Home NAS',
          kind: MediaSourceKind.nas,
          endpoint: 'https://nas.example.com/dav/',
          enabled: true,
          username: 'alice',
          password: 'secret',
        ),
        limit: 20,
      );

      expect(items, hasLength(1));
      expect(items.single.title, 'broken');
      expect(items.single.streamUrl, isNotEmpty);
    });

    test('treats generic child folders as seasons and root files as specials',
        () async {
      final client = WebDavNasClient(
        MockClient((request) async {
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/Lost/') {
            return http.Response(_lostRootPropfindResponse, 207);
          }
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/Lost/Arc/') {
            return http.Response(_lostArcPropfindResponse, 207);
          }
          return http.Response('Not Found', 404);
        }),
      );

      final baseSource = const MediaSourceConfig(
        id: 'nas-shows',
        name: 'Show NAS',
        kind: MediaSourceKind.nas,
        endpoint: 'https://nas.example.com/dav/Shows/Lost/',
        enabled: true,
      );

      final plainItems = await client.fetchLibrary(baseSource, limit: 20);
      expect(plainItems, hasLength(3));
      expect(
        plainItems.every((item) => item.itemType.trim().isEmpty),
        isTrue,
      );
      expect(
        plainItems.every(
          (item) => item.seasonNumber == null && item.episodeNumber == null,
        ),
        isTrue,
      );

      final inferredItems = await client.fetchLibrary(
        baseSource.copyWith(webDavStructureInferenceEnabled: true),
        limit: 20,
      );
      expect(inferredItems, hasLength(3));
      expect(inferredItems.every((item) => item.itemType == 'episode'), isTrue);

      final rootSpecial =
          inferredItems.firstWhere((item) => item.title == 'Part A');
      expect(rootSpecial.seasonNumber, 0);
      expect(rootSpecial.episodeNumber, 1);

      final arcPartB =
          inferredItems.firstWhere((item) => item.title == 'Part B');
      expect(arcPartB.seasonNumber, 1);
      expect(arcPartB.episodeNumber, 1);

      final arcPartC =
          inferredItems.firstWhere((item) => item.title == 'Part C');
      expect(arcPartC.seasonNumber, 1);
      expect(arcPartC.episodeNumber, 2);
    });

    test('treats direct episode-style files as a single implicit season',
        () async {
      final client = WebDavNasClient(
        MockClient((request) async {
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/ChenLuyu/') {
            return http.Response.bytes(
              utf8.encode(_chenLuyuRootPropfindResponse),
              207,
              headers: const {'content-type': 'application/xml; charset=utf-8'},
            );
          }
          if (request.method == 'GET' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/ChenLuyu/%E9%99%88%E9%B2%81%E8%B1%ABE01.strm') {
            return http.Response(
              'https://media.example.com/chen/e01.m3u8\n',
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/ChenLuyu/%E9%99%88%E9%B2%81%E8%B1%ABE02.strm') {
            return http.Response(
              'https://media.example.com/chen/e02.m3u8\n',
              200,
            );
          }
          return http.Response('Not Found', 404);
        }),
      );

      final items = await client.fetchLibrary(
        const MediaSourceConfig(
          id: 'nas-chen',
          name: 'Chen NAS',
          kind: MediaSourceKind.nas,
          endpoint: 'https://nas.example.com/dav/Shows/ChenLuyu/',
          enabled: true,
          webDavStructureInferenceEnabled: true,
        ),
        limit: 20,
      );

      expect(items, hasLength(2));
      expect(items.every((item) => item.itemType == 'episode'), isTrue);
      expect(items.every((item) => item.seasonNumber == 1), isTrue);
      expect(items.map((item) => item.episodeNumber), containsAll([1, 2]));
    });

    test('treats plain numeric root files as a single implicit season',
        () async {
      final client = WebDavNasClient(
        MockClient((request) async {
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/FamilyCourt/') {
            return http.Response.bytes(
              utf8.encode(_familyCourtRootPropfindResponse),
              207,
              headers: const {'content-type': 'application/xml; charset=utf-8'},
            );
          }
          if (request.method == 'GET' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/FamilyCourt/01%204K.(mp4).strm') {
            return http.Response(
              'https://media.example.com/family-court/e01.m3u8\n',
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/FamilyCourt/02%204K.(mp4).strm') {
            return http.Response(
              'https://media.example.com/family-court/e02.m3u8\n',
              200,
            );
          }
          return http.Response('Not Found', 404);
        }),
      );

      final items = await client.fetchLibrary(
        const MediaSourceConfig(
          id: 'nas-family-court',
          name: 'Family Court NAS',
          kind: MediaSourceKind.nas,
          endpoint: 'https://nas.example.com/dav/Shows/FamilyCourt/',
          enabled: true,
          webDavStructureInferenceEnabled: true,
        ),
        limit: 20,
      );

      expect(items, hasLength(2));
      expect(items.every((item) => item.itemType == 'episode'), isTrue);
      expect(items.every((item) => item.seasonNumber == 1), isTrue);
      expect(items.map((item) => item.episodeNumber), containsAll([1, 2]));
    });

    test('orders date-named implicit episodes by file date', () async {
      final client = WebDavNasClient(
        MockClient((request) async {
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/RoundTableDate/') {
            return http.Response.bytes(
              utf8.encode(_roundTableDateRootPropfindResponse),
              207,
              headers: const {'content-type': 'application/xml; charset=utf-8'},
            );
          }
          return http.Response('Not Found', 404);
        }),
      );

      final items = await client.fetchLibrary(
        const MediaSourceConfig(
          id: 'nas-round-table-date',
          name: 'Round Table Date NAS',
          kind: MediaSourceKind.nas,
          endpoint: 'https://nas.example.com/dav/Shows/RoundTableDate/',
          enabled: true,
          webDavStructureInferenceEnabled: true,
        ),
        limit: 20,
      );

      expect(items, hasLength(3));
      expect(items.every((item) => item.itemType == 'episode'), isTrue);
      expect(items.every((item) => item.seasonNumber == 1), isTrue);

      final june = items.firstWhere(
        (item) =>
            item.actualAddress ==
            '/dav/Shows/RoundTableDate/Round Table 2024.6.01.mkv',
      );
      expect(june.episodeNumber, 1);

      final august = items.firstWhere(
        (item) =>
            item.actualAddress ==
            '/dav/Shows/RoundTableDate/Round Table 2024.8.15.mkv',
      );
      expect(august.episodeNumber, 2);

      final october = items.firstWhere(
        (item) =>
            item.actualAddress ==
            '/dav/Shows/RoundTableDate/Round Table 2024.10.01.mkv',
      );
      expect(october.episodeNumber, 3);
    });

    test('treats root files as specials when sibling folders are seasons',
        () async {
      final client = WebDavNasClient(
        MockClient((request) async {
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/FoodDao/') {
            return http.Response.bytes(
              utf8.encode(_foodDaoRootPropfindResponse),
              207,
              headers: const {'content-type': 'application/xml; charset=utf-8'},
            );
          }
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/FoodDao/1.%E6%97%A5%E6%9C%AC/') {
            return http.Response.bytes(
              utf8.encode(_foodDaoJapanPropfindResponse),
              207,
              headers: const {'content-type': 'application/xml; charset=utf-8'},
            );
          }
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/FoodDao/2.%E5%B7%B4%E4%BB%A5/') {
            return http.Response.bytes(
              utf8.encode(_foodDaoMideastPropfindResponse),
              207,
              headers: const {'content-type': 'application/xml; charset=utf-8'},
            );
          }
          if (request.method == 'GET' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/FoodDao/%E5%90%B4%E5%93%A5%E7%AA%9F.strm') {
            return http.Response(
              'https://media.example.com/fooddao/special.m3u8\n',
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/FoodDao/1.%E6%97%A5%E6%9C%AC/%E8%BF%B7%E5%A4%B1%E4%B8%9C%E4%BA%AC.strm') {
            return http.Response(
              'https://media.example.com/fooddao/japan.m3u8\n',
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/FoodDao/2.%E5%B7%B4%E4%BB%A5/%E5%B7%B4%E4%BB%A5%E8%A7%82%E5%AF%9F.strm') {
            return http.Response(
              'https://media.example.com/fooddao/mideast.m3u8\n',
              200,
            );
          }
          return http.Response('Not Found', 404);
        }),
      );

      final items = await client.fetchLibrary(
        const MediaSourceConfig(
          id: 'nas-fooddao',
          name: 'FoodDao NAS',
          kind: MediaSourceKind.nas,
          endpoint: 'https://nas.example.com/dav/Shows/FoodDao/',
          enabled: true,
          webDavStructureInferenceEnabled: true,
        ),
        limit: 20,
      );

      expect(items, hasLength(3));
      final special = items.firstWhere((item) => item.title == '吴哥窟');
      expect(special.itemType, 'episode');
      expect(special.seasonNumber, 0);

      final japan = items.firstWhere((item) => item.title == '迷失东京');
      expect(japan.itemType, 'episode');
      expect(japan.seasonNumber, 1);

      final mideast = items.firstWhere((item) => item.title == '巴以观察');
      expect(mideast.itemType, 'episode');
      expect(mideast.seasonNumber, 2);
    });

    test(
        'keeps multi-file numeric season folders under parent series root seasons',
        () async {
      final client = WebDavNasClient(
        MockClient((request) async {
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/FoodDaoMulti/') {
            return http.Response.bytes(
              utf8.encode(_foodDaoMultiRootPropfindResponse),
              207,
              headers: const {'content-type': 'application/xml; charset=utf-8'},
            );
          }
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/FoodDaoMulti/2.%E5%B7%B4%E4%BB%A5/') {
            return http.Response.bytes(
              utf8.encode(_foodDaoMultiSeasonTwoPropfindResponse),
              207,
              headers: const {'content-type': 'application/xml; charset=utf-8'},
            );
          }
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/FoodDaoMulti/5.%E7%BE%8E%E5%9B%BD/') {
            return http.Response.bytes(
              utf8.encode(_foodDaoMultiSeasonFivePropfindResponse),
              207,
              headers: const {'content-type': 'application/xml; charset=utf-8'},
            );
          }
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/FoodDaoMulti/9.%E9%9F%A9%E5%9B%BD/') {
            return http.Response.bytes(
              utf8.encode(_foodDaoMultiSeasonNinePropfindResponse),
              207,
              headers: const {'content-type': 'application/xml; charset=utf-8'},
            );
          }
          if (request.method == 'GET' && request.url.path.endsWith('.strm')) {
            return http.Response(
              'https://media.example.com/fooddao/multi.m3u8\n',
              200,
            );
          }
          return http.Response('Not Found', 404);
        }),
      );

      final items = await client.fetchLibrary(
        const MediaSourceConfig(
          id: 'nas-fooddao-multi',
          name: 'FoodDao Multi NAS',
          kind: MediaSourceKind.nas,
          endpoint: 'https://nas.example.com/dav/Shows/FoodDaoMulti/',
          enabled: true,
          webDavStructureInferenceEnabled: true,
        ),
        limit: 20,
      );

      expect(items, hasLength(7));

      final special = items.firstWhere(
        (item) => item.actualAddress == '/dav/Shows/FoodDaoMulti/吴哥窟.strm',
      );
      expect(special.itemType, 'episode');
      expect(special.seasonNumber, 0);

      for (final item in items.where(
        (item) => item.actualAddress.contains('/2.巴以/'),
      )) {
        expect(item.itemType, 'episode');
        expect(item.seasonNumber, 2);
      }
      for (final item in items.where(
        (item) => item.actualAddress.contains('/5.美国/'),
      )) {
        expect(item.itemType, 'episode');
        expect(item.seasonNumber, 5);
      }
      for (final item in items.where(
        (item) => item.actualAddress.contains('/9.韩国/'),
      )) {
        expect(item.itemType, 'episode');
        expect(item.seasonNumber, 9);
      }
    });

    test('treats a single explicit season folder as series structure',
        () async {
      final client = WebDavNasClient(
        MockClient((request) async {
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/New%20Show/') {
            return http.Response.bytes(
              utf8.encode(_newShowRootPropfindResponse),
              207,
              headers: const {'content-type': 'application/xml; charset=utf-8'},
            );
          }
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/New%20Show/Season%2001/') {
            return http.Response.bytes(
              utf8.encode(_newShowSeasonOnePropfindResponse),
              207,
              headers: const {'content-type': 'application/xml; charset=utf-8'},
            );
          }
          if (request.method == 'GET' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/New%20Show/Season%2001/Episode%2001.strm') {
            return http.Response(
              'https://media.example.com/new-show/e01.m3u8\n',
              200,
            );
          }
          return http.Response('Not Found', 404);
        }),
      );

      final items = await client.fetchLibrary(
        const MediaSourceConfig(
          id: 'nas-new-show',
          name: 'New Show NAS',
          kind: MediaSourceKind.nas,
          endpoint: 'https://nas.example.com/dav/Shows/New%20Show/',
          enabled: true,
          webDavStructureInferenceEnabled: true,
        ),
        limit: 20,
      );

      expect(items, hasLength(1));
      expect(items.single.itemType, 'episode');
      expect(items.single.seasonNumber, 1);
      expect(items.single.episodeNumber, 1);
      expect(items.single.title, 'Episode 01');
    });

    test(
        'prioritizes explicit SxxEyy markers for inference and season grouping',
        () async {
      final client = WebDavNasClient(
        MockClient((request) async {
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/StrangerThings/') {
            return http.Response(_strangerThingsRootPropfindResponse, 207);
          }
          if (request.method == 'GET' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/StrangerThings/Stranger.Things.S01E01.2160p.strm') {
            return http.Response(
              'https://media.example.com/stranger/s01e01.m3u8\n',
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/StrangerThings/Stranger.Things.S02E01.2160p.strm') {
            return http.Response(
              'https://media.example.com/stranger/s02e01.m3u8\n',
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/StrangerThings/Stranger.Things.S02E02.2160p.strm') {
            return http.Response(
              'https://media.example.com/stranger/s02e02.m3u8\n',
              200,
            );
          }
          return http.Response('Not Found', 404);
        }),
      );

      final items = await client.fetchLibrary(
        const MediaSourceConfig(
          id: 'nas-shows',
          name: 'Show NAS',
          kind: MediaSourceKind.nas,
          endpoint: 'https://nas.example.com/dav/Shows/StrangerThings/',
          enabled: true,
          webDavStructureInferenceEnabled: true,
        ),
        limit: 20,
      );

      expect(items, hasLength(3));
      expect(items.every((item) => item.itemType == 'episode'), isTrue);
      expect(items.map((item) => item.seasonNumber), containsAll([1, 2]));
      expect(items.map((item) => item.episodeNumber), containsAll([1, 2]));
    });

    test('filters excluded WebDAV path keywords from collections and scan',
        () async {
      final client = WebDavNasClient(
        MockClient((request) async {
          if (request.method == 'PROPFIND' &&
              request.url.toString() == 'https://nas.example.com/dav/') {
            return http.Response(_filteredRootPropfindResponse, 207);
          }
          if (request.method == 'PROPFIND' &&
              request.url.toString() == 'https://nas.example.com/dav/Movies/') {
            return http.Response(_filteredMoviesPropfindResponse, 207);
          }
          if (request.method == 'PROPFIND' &&
              request.url.toString() == 'https://nas.example.com/dav/temp/') {
            return http.Response(_filteredTempPropfindResponse, 207);
          }
          return http.Response('Not Found', 404);
        }),
      );

      const source = MediaSourceConfig(
        id: 'nas-filtered',
        name: 'Filtered NAS',
        kind: MediaSourceKind.nas,
        endpoint: 'https://nas.example.com/dav/',
        enabled: true,
        webDavExcludedPathKeywords: ['temp', 'sample'],
      );

      final collections = await client.fetchCollections(source);
      expect(collections.map((item) => item.title), ['Movies']);

      final items = await client.fetchLibrary(source, limit: 20);
      expect(items, hasLength(1));
      expect(items.single.title, 'Main Feature');
      expect(items.single.actualAddress, '/dav/Movies/Main Feature.mkv');
    });

    test('reuses unchanged directory subtrees only when scan caches stay warm',
        () async {
      final propfindCounts = <String, int>{};
      final client = WebDavNasClient(
        MockClient((request) async {
          if (request.method == 'PROPFIND') {
            final key = request.url.toString();
            propfindCounts[key] = (propfindCounts[key] ?? 0) + 1;
          }
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/Repeatable/') {
            return http.Response(_repeatableRootPropfindResponse, 207);
          }
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/Repeatable/Season%201/') {
            return http.Response(_repeatableSeasonOnePropfindResponse, 207);
          }
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/Repeatable/Season%202/') {
            return http.Response(_repeatableSeasonTwoPropfindResponse, 207);
          }
          return http.Response('Not Found', 404);
        }),
      );

      const source = MediaSourceConfig(
        id: 'nas-repeatable',
        name: 'Repeatable NAS',
        kind: MediaSourceKind.nas,
        endpoint: 'https://nas.example.com/dav/Shows/Repeatable/',
        enabled: true,
      );

      final firstItems = await client.scanLibrary(
        source,
        limit: 20,
        resolvePlayableStreams: false,
        resetCaches: true,
      );
      final secondItems = await client.scanLibrary(
        source,
        limit: 20,
        resolvePlayableStreams: false,
        resetCaches: false,
      );

      expect(firstItems, hasLength(2));
      expect(secondItems, hasLength(2));
      expect(
        propfindCounts['https://nas.example.com/dav/Shows/Repeatable/'],
        2,
      );
      expect(
        propfindCounts[
            'https://nas.example.com/dav/Shows/Repeatable/Season%201/'],
        1,
      );
      expect(
        propfindCounts[
            'https://nas.example.com/dav/Shows/Repeatable/Season%202/'],
        1,
      );
    });

    test(
        'resetting scan caches invalidates subtree cache and sees newly added files',
        () async {
      var scanVersion = 0;
      final client = WebDavNasClient(
        MockClient((request) async {
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/Mutable/') {
            return http.Response(_mutableRootPropfindResponse, 207);
          }
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/Mutable/Season%201/') {
            return http.Response(
              scanVersion == 0
                  ? _mutableSeasonOneInitialPropfindResponse
                  : _mutableSeasonOneUpdatedPropfindResponse,
              207,
            );
          }
          return http.Response('Not Found', 404);
        }),
      );

      const source = MediaSourceConfig(
        id: 'nas-mutable',
        name: 'Mutable NAS',
        kind: MediaSourceKind.nas,
        endpoint: 'https://nas.example.com/dav/Shows/Mutable/',
        enabled: true,
      );

      final firstItems = await client.scanLibrary(
        source,
        limit: 20,
        resolvePlayableStreams: false,
        resetCaches: true,
      );
      scanVersion = 1;
      final secondItems = await client.scanLibrary(
        source,
        limit: 20,
        resolvePlayableStreams: false,
        resetCaches: true,
      );

      expect(firstItems, hasLength(1));
      expect(firstItems.single.metadataSeed.title, 'Episode 01');
      expect(secondItems, hasLength(2));
      expect(
        secondItems.map((item) => item.metadataSeed.title),
        containsAll(<String>[
          'Episode 01',
          'Episode 02',
        ]),
      );
    });

    test('scans sibling season directories concurrently', () async {
      var activeSeasonPropfinds = 0;
      var maxConcurrentSeasonPropfinds = 0;

      final client = WebDavNasClient(
        MockClient((request) async {
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/Concurrent/') {
            return http.Response(_concurrentRootPropfindResponse, 207);
          }
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/Concurrent/Season%201/') {
            activeSeasonPropfinds += 1;
            if (activeSeasonPropfinds > maxConcurrentSeasonPropfinds) {
              maxConcurrentSeasonPropfinds = activeSeasonPropfinds;
            }
            await Future<void>.delayed(const Duration(milliseconds: 30));
            activeSeasonPropfinds -= 1;
            return http.Response(_concurrentSeasonOnePropfindResponse, 207);
          }
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/Concurrent/Season%202/') {
            activeSeasonPropfinds += 1;
            if (activeSeasonPropfinds > maxConcurrentSeasonPropfinds) {
              maxConcurrentSeasonPropfinds = activeSeasonPropfinds;
            }
            await Future<void>.delayed(const Duration(milliseconds: 30));
            activeSeasonPropfinds -= 1;
            return http.Response(_concurrentSeasonTwoPropfindResponse, 207);
          }
          return http.Response('Not Found', 404);
        }),
      );

      const source = MediaSourceConfig(
        id: 'nas-concurrent',
        name: 'Concurrent NAS',
        kind: MediaSourceKind.nas,
        endpoint: 'https://nas.example.com/dav/Shows/Concurrent/',
        enabled: true,
      );

      final items = await client.fetchLibrary(source, limit: 20);

      expect(items, hasLength(2));
      expect(maxConcurrentSeasonPropfinds, greaterThan(1));
    });

    test('can defer strm target resolution during WebDAV scans', () async {
      var strmReadCount = 0;
      final client = WebDavNasClient(
        MockClient((request) async {
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/LazyStrm/') {
            return http.Response(_lazyStrmRootPropfindResponse, 207);
          }
          if (request.method == 'GET' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/LazyStrm/Episode%2001.strm') {
            strmReadCount += 1;
            return http.Response(
              'https://media.example.com/lazy/e01.m3u8\n',
              200,
            );
          }
          return http.Response('Not Found', 404);
        }),
      );

      const source = MediaSourceConfig(
        id: 'nas-lazy-strm',
        name: 'Lazy STRM NAS',
        kind: MediaSourceKind.nas,
        endpoint: 'https://nas.example.com/dav/Shows/LazyStrm/',
        enabled: true,
        username: 'alice',
        password: 'secret',
      );

      final items = await client.scanLibrary(
        source,
        limit: 20,
        resolvePlayableStreams: false,
      );

      expect(items, hasLength(1));
      expect(strmReadCount, 0);
      expect(
        items.single.streamUrl,
        'https://nas.example.com/dav/Shows/LazyStrm/Episode%2001.strm',
      );
      expect(items.single.streamHeaders['Authorization'], startsWith('Basic '));
    });

    test('resolves deferred nas strm targets before playback', () async {
      final client = WebDavNasClient(
        MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Shows/LazyStrm/Episode%2001.strm') {
            return http.Response(
              'https://media.example.com/lazy/e01.m3u8\n',
              200,
            );
          }
          return http.Response('Not Found', 404);
        }),
      );

      const source = MediaSourceConfig(
        id: 'nas-lazy-strm',
        name: 'Lazy STRM NAS',
        kind: MediaSourceKind.nas,
        endpoint: 'https://nas.example.com/dav/Shows/LazyStrm/',
        enabled: true,
        username: 'alice',
        password: 'secret',
      );

      final resolved = await client.resolvePlaybackTarget(
        source: source,
        target: const PlaybackTarget(
          title: 'Episode 01',
          sourceId: 'nas-lazy-strm',
          streamUrl:
              'https://nas.example.com/dav/Shows/LazyStrm/Episode%2001.strm',
          sourceName: 'Lazy STRM NAS',
          sourceKind: MediaSourceKind.nas,
          actualAddress: '/dav/Shows/LazyStrm/Episode 01.strm',
          container: 'strm',
        ),
      );

      expect(
        resolved.streamUrl,
        'https://media.example.com/lazy/e01.m3u8',
      );
      expect(resolved.headers, isEmpty);
    });

    test('deletes files using their direct WebDAV resource uri', () async {
      final requests = <String>[];
      final client = WebDavNasClient(
        MockClient((request) async {
          requests.add('${request.method} ${request.url}');
          if (request.method == 'DELETE' &&
              request.url.toString() ==
                  'https://nas.example.com/library/Movies/Delete%20Me.mkv') {
            return http.Response('', 204);
          }
          if (request.method == 'PROPFIND' &&
              request.url.toString() ==
                  'https://nas.example.com/library/Movies/') {
            return http.Response(
              '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/library/Movies/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Movies</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''',
              207,
            );
          }
          return http.Response('Not Found', 404);
        }),
      );

      await client.deleteResource(
        const MediaSourceConfig(
          id: 'nas-delete',
          name: 'Delete NAS',
          kind: MediaSourceKind.nas,
          endpoint: 'https://nas.example.com/dav/',
          enabled: true,
        ),
        resourcePath: 'https://nas.example.com/library/Movies/Delete%20Me.mkv',
        sectionId: 'https://nas.example.com/dav/Movies/',
      );

      expect(
        requests,
        contains(
          'DELETE https://nas.example.com/library/Movies/Delete%20Me.mkv',
        ),
      );
    });

    test('throws when WebDAV delete returns success but file still exists',
        () async {
      final client = WebDavNasClient(
        MockClient((request) async {
          if (request.method == 'DELETE' &&
              request.url.toString() ==
                  'https://nas.example.com/dav/Movies/Delete%20Me.mkv') {
            return http.Response('', 204);
          }
          if (request.method == 'PROPFIND' &&
              request.url.toString() == 'https://nas.example.com/dav/Movies/') {
            return http.Response(
              '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Movies/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Movies</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Movies/Delete%20Me.mkv</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Delete Me.mkv</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>video/x-matroska</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''',
              207,
            );
          }
          return http.Response('Not Found', 404);
        }),
      );

      await expectLater(
        () => client.deleteResource(
          const MediaSourceConfig(
            id: 'nas-delete',
            name: 'Delete NAS',
            kind: MediaSourceKind.nas,
            endpoint: 'https://nas.example.com/dav/',
            enabled: true,
          ),
          resourcePath: '/dav/Movies/Delete Me.mkv',
          sectionId: 'https://nas.example.com/dav/Movies/',
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('删除未生效'),
          ),
        ),
      );
    });
  });
}

const _rootPropfindResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>dav</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
        <d:getlastmodified>Fri, 04 Apr 2026 08:00:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Movies/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Movies</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
        <d:getlastmodified>Fri, 04 Apr 2026 08:15:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/One%20Piece.strm</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>One Piece.strm</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/plain</d:getcontenttype>
        <d:getlastmodified>Fri, 03 Apr 2026 09:00:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _malformedHrefPropfind = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>dav</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/broken%ZZ.mkv</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>broken.mkv</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>video/x-matroska</d:getcontenttype>
        <d:getlastmodified>Fri, 04 Apr 2026 10:00:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _moviesPropfindResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Movies/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Movies</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
        <d:getlastmodified>Fri, 04 Apr 2026 08:15:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Movies/Interstellar.mkv</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Interstellar.mkv</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>application/octet-stream</d:getcontenttype>
        <d:getlastmodified>Thu, 02 Apr 2026 08:30:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Movies/movie.nfo</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>movie.nfo</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/xml</d:getcontenttype>
        <d:getlastmodified>Thu, 02 Apr 2026 08:31:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Movies/poster.jpg</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>poster.jpg</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>image/jpeg</d:getcontenttype>
        <d:getlastmodified>Thu, 02 Apr 2026 08:31:30 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Movies/fanart.jpg</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>fanart.jpg</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>image/jpeg</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Movies/clearlogo.png</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>clearlogo.png</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>image/png</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Movies/banner.jpg</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>banner.jpg</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>image/jpeg</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Movies/extrafanart/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>extrafanart</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _extraFanartPropfindResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Movies/extrafanart/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>extrafanart</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Movies/extrafanart/shot1.jpg</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>shot1.jpg</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>image/jpeg</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Movies/extrafanart/shot2.jpg</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>shot2.jpg</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>image/jpeg</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _movieNfoResponse =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<movie>
  <title>星际穿越</title>
  <plot>一支探险队穿越虫洞寻找人类新家园。</plot>
  <year>2014</year>
  <runtime>169</runtime>
  <genre>科幻</genre>
  <genre>冒险</genre>
  <director>克里斯托弗·诺兰</director>
  <actor>
    <name>马修·麦康纳</name>
  </actor>
  <art>
    <fanart>fanart.jpg</fanart>
    <clearlogo>clearlogo.png</clearlogo>
    <banner>banner.jpg</banner>
  </art>
  <fanart>
    <thumb>extrafanart/shot1.jpg</thumb>
    <thumb>extrafanart/shot2.jpg</thumb>
  </fanart>
  <fileinfo>
    <streamdetails>
      <video>
        <codec>hevc</codec>
        <width>3840</width>
        <height>2160</height>
        <bitrate>18000000</bitrate>
      </video>
      <audio>
        <codec>truehd</codec>
      </audio>
    </streamdetails>
    <container>mkv</container>
  </fileinfo>
  <uniqueid type="imdb">tt0816692</uniqueid>
  <uniqueid type="tmdb">157336</uniqueid>
</movie>''';

const _lostRootPropfindResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/Lost/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Lost</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/Lost/Part%20A.mkv</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Part A.mkv</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>video/x-matroska</d:getcontenttype>
        <d:getlastmodified>Sun, 05 Apr 2026 08:00:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/Lost/Arc/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Arc</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _lostArcPropfindResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/Lost/Arc/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Arc</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/Lost/Arc/Part%20B.mkv</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Part B.mkv</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>video/x-matroska</d:getcontenttype>
        <d:getlastmodified>Sun, 05 Apr 2026 08:10:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/Lost/Arc/Part%20C.mkv</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Part C.mkv</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>video/x-matroska</d:getcontenttype>
        <d:getlastmodified>Sun, 05 Apr 2026 08:20:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _chenLuyuRootPropfindResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/ChenLuyu/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>ChenLuyu</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/ChenLuyu/%E9%99%88%E9%B2%81%E8%B1%ABE01.strm</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>陈鲁豫E01.strm</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/plain</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/ChenLuyu/%E9%99%88%E9%B2%81%E8%B1%ABE02.strm</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>陈鲁豫E02.strm</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/plain</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _familyCourtRootPropfindResponse =
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/FamilyCourt/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>FamilyCourt</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/FamilyCourt/01%204K.(mp4).strm</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>01 4K.(mp4).strm</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/plain</d:getcontenttype>
        <d:getcontentlength>128</d:getcontentlength>
        <d:getlastmodified>Sun, 05 Apr 2026 10:01:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/FamilyCourt/02%204K.(mp4).strm</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>02 4K.(mp4).strm</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/plain</d:getcontenttype>
        <d:getcontentlength>128</d:getcontentlength>
        <d:getlastmodified>Sun, 05 Apr 2026 10:02:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _roundTableDateRootPropfindResponse =
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/RoundTableDate/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>RoundTableDate</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/RoundTableDate/Round%20Table%202024.10.01.mkv</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Round Table 2024.10.01.mkv</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>video/x-matroska</d:getcontenttype>
        <d:getlastmodified>Tue, 01 Oct 2024 08:00:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/RoundTableDate/Round%20Table%202024.6.01.mkv</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Round Table 2024.6.01.mkv</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>video/x-matroska</d:getcontenttype>
        <d:getlastmodified>Sat, 01 Jun 2024 08:00:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/RoundTableDate/Round%20Table%202024.8.15.mkv</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Round Table 2024.8.15.mkv</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>video/x-matroska</d:getcontenttype>
        <d:getlastmodified>Thu, 15 Aug 2024 08:00:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _foodDaoRootPropfindResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/FoodDao/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>FoodDao</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/FoodDao/%E5%90%B4%E5%93%A5%E7%AA%9F.strm</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>吴哥窟.strm</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/plain</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/FoodDao/1.%E6%97%A5%E6%9C%AC/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>1.日本</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/FoodDao/2.%E5%B7%B4%E4%BB%A5/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>2.巴以</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _foodDaoJapanPropfindResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/FoodDao/1.%E6%97%A5%E6%9C%AC/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>1.日本</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/FoodDao/1.%E6%97%A5%E6%9C%AC/%E8%BF%B7%E5%A4%B1%E4%B8%9C%E4%BA%AC.strm</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>迷失东京.strm</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/plain</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _foodDaoMideastPropfindResponse =
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/FoodDao/2.%E5%B7%B4%E4%BB%A5/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>2.巴以</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/FoodDao/2.%E5%B7%B4%E4%BB%A5/%E5%B7%B4%E4%BB%A5%E8%A7%82%E5%AF%9F.strm</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>巴以观察.strm</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/plain</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _foodDaoMultiRootPropfindResponse =
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/FoodDaoMulti/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>FoodDaoMulti</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/FoodDaoMulti/%E5%90%B4%E5%93%A5%E7%AA%9F.strm</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>吴哥窟.strm</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/plain</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/FoodDaoMulti/2.%E5%B7%B4%E4%BB%A5/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>2.巴以</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/FoodDaoMulti/5.%E7%BE%8E%E5%9B%BD/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>5.美国</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/FoodDaoMulti/9.%E9%9F%A9%E5%9B%BD/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>9.韩国</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _foodDaoMultiSeasonTwoPropfindResponse =
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/FoodDaoMulti/2.%E5%B7%B4%E4%BB%A5/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>2.巴以</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/FoodDaoMulti/2.%E5%B7%B4%E4%BB%A5/mideast-a.strm</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>mideast-a.strm</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/plain</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/FoodDaoMulti/2.%E5%B7%B4%E4%BB%A5/mideast-b.strm</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>mideast-b.strm</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/plain</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _foodDaoMultiSeasonFivePropfindResponse =
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/FoodDaoMulti/5.%E7%BE%8E%E5%9B%BD/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>5.美国</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/FoodDaoMulti/5.%E7%BE%8E%E5%9B%BD/america-a.strm</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>america-a.strm</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/plain</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/FoodDaoMulti/5.%E7%BE%8E%E5%9B%BD/america-b.strm</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>america-b.strm</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/plain</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _foodDaoMultiSeasonNinePropfindResponse =
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/FoodDaoMulti/9.%E9%9F%A9%E5%9B%BD/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>9.韩国</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/FoodDaoMulti/9.%E9%9F%A9%E5%9B%BD/korea-a.strm</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>korea-a.strm</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/plain</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/FoodDaoMulti/9.%E9%9F%A9%E5%9B%BD/korea-b.strm</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>korea-b.strm</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/plain</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _strangerThingsRootPropfindResponse =
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/StrangerThings/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>StrangerThings</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/StrangerThings/Stranger.Things.S01E01.2160p.strm</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Stranger.Things.S01E01.2160p.strm</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/plain</d:getcontenttype>
        <d:getlastmodified>Sun, 05 Apr 2026 08:00:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/StrangerThings/Stranger.Things.S02E01.2160p.strm</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Stranger.Things.S02E01.2160p.strm</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/plain</d:getcontenttype>
        <d:getlastmodified>Sun, 05 Apr 2026 08:01:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/StrangerThings/Stranger.Things.S02E02.2160p.strm</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Stranger.Things.S02E02.2160p.strm</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/plain</d:getcontenttype>
        <d:getlastmodified>Sun, 05 Apr 2026 08:02:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _filteredRootPropfindResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>dav</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Movies/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Movies</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/temp/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>temp</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _filteredMoviesPropfindResponse =
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Movies/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Movies</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Movies/Main%20Feature.mkv</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Main Feature.mkv</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>video/x-matroska</d:getcontenttype>
        <d:getlastmodified>Sun, 05 Apr 2026 09:00:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Movies/sample-trailer.mkv</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>sample-trailer.mkv</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>video/x-matroska</d:getcontenttype>
        <d:getlastmodified>Sun, 05 Apr 2026 09:01:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _filteredTempPropfindResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/temp/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>temp</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/temp/Hidden%20Movie.mkv</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Hidden Movie.mkv</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>video/x-matroska</d:getcontenttype>
        <d:getlastmodified>Sun, 05 Apr 2026 09:02:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _repeatableRootPropfindResponse =
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/Repeatable/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Repeatable</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/Repeatable/Season%201/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Season 1</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
        <d:getlastmodified>Sun, 05 Apr 2026 08:00:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/Repeatable/Season%202/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Season 2</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
        <d:getlastmodified>Sun, 05 Apr 2026 08:05:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _repeatableSeasonOnePropfindResponse =
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/Repeatable/Season%201/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Season 1</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/Repeatable/Season%201/Episode%2001.mkv</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Episode 01.mkv</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>video/x-matroska</d:getcontenttype>
        <d:getlastmodified>Sun, 05 Apr 2026 08:01:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _repeatableSeasonTwoPropfindResponse =
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/Repeatable/Season%202/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Season 2</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/Repeatable/Season%202/Episode%2002.mkv</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Episode 02.mkv</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>video/x-matroska</d:getcontenttype>
        <d:getlastmodified>Sun, 05 Apr 2026 08:06:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _mutableRootPropfindResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/Mutable/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Mutable</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/Mutable/Season%201/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Season 1</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
        <d:getlastmodified>Sun, 05 Apr 2026 08:00:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _mutableSeasonOneInitialPropfindResponse =
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/Mutable/Season%201/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Season 1</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/Mutable/Season%201/Episode%2001.mkv</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Episode 01.mkv</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>video/x-matroska</d:getcontenttype>
        <d:getlastmodified>Sun, 05 Apr 2026 08:01:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _mutableSeasonOneUpdatedPropfindResponse =
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/Mutable/Season%201/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Season 1</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/Mutable/Season%201/Episode%2001.mkv</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Episode 01.mkv</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>video/x-matroska</d:getcontenttype>
        <d:getlastmodified>Sun, 05 Apr 2026 08:01:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/Mutable/Season%201/Episode%2002.mkv</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Episode 02.mkv</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>video/x-matroska</d:getcontenttype>
        <d:getlastmodified>Sun, 05 Apr 2026 08:02:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _concurrentRootPropfindResponse =
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/Concurrent/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Concurrent</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/Concurrent/Season%201/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Season 1</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/Concurrent/Season%202/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Season 2</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _concurrentSeasonOnePropfindResponse =
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/Concurrent/Season%201/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Season 1</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/Concurrent/Season%201/Episode%2001.mkv</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Episode 01.mkv</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>video/x-matroska</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _concurrentSeasonTwoPropfindResponse =
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/Concurrent/Season%202/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Season 2</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/Concurrent/Season%202/Episode%2002.mkv</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Episode 02.mkv</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>video/x-matroska</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _lazyStrmRootPropfindResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/LazyStrm/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>LazyStrm</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/LazyStrm/Episode%2001.strm</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Episode 01.strm</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/plain</d:getcontenttype>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _newShowRootPropfindResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/New%20Show/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>New Show</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
        <d:getlastmodified>Sun, 05 Apr 2026 10:00:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/New%20Show/Season%2001/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Season 01</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
        <d:getlastmodified>Sun, 05 Apr 2026 10:00:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _newShowSeasonOnePropfindResponse =
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Shows/New%20Show/Season%2001/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Season 01</d:displayname>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Shows/New%20Show/Season%2001/Episode%2001.strm</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Episode 01.strm</d:displayname>
        <d:resourcetype />
        <d:getcontenttype>text/plain</d:getcontenttype>
        <d:getcontentlength>128</d:getcontentlength>
        <d:getlastmodified>Sun, 05 Apr 2026 10:01:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';
