import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';

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
      expect(movie.year, 2014);
      expect(movie.durationLabel, '169分钟');
      expect(movie.genres, contains('科幻'));
      expect(movie.directors, contains('克里斯托弗·诺兰'));
      expect(movie.actors, contains('马修·麦康纳'));
      expect(movie.imdbId, 'tt0816692');
      expect(movie.tmdbId, '157336');
      expect(movie.actualAddress, 'Movies/Interstellar.mkv');
      expect(movie.addedAt, DateTime.utc(2026, 4, 2, 8, 30, 0));

      final strm = items.firstWhere((item) => item.title == 'One Piece');
      expect(
        strm.streamUrl,
        'https://media.example.com/streams/one-piece/master.m3u8',
      );
      expect(strm.actualAddress, 'Shows/One Piece.strm');
      expect(strm.overview, isEmpty);
      expect(strm.addedAt, DateTime.utc(2026, 4, 3, 9, 0, 0));
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

    test('optionally infers episode grouping from directory structure',
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

      final directEpisode = inferredItems.firstWhere(
        (item) => item.title == 'Part A',
      );
      expect(directEpisode.itemType, 'episode');
      expect(directEpisode.seasonNumber, 1);
      expect(directEpisode.episodeNumber, 1);

      final arcEpisodes = inferredItems
          .where((item) => item.actualAddress.startsWith('Arc/'))
          .toList(growable: false)
        ..sort((left, right) => left.title.compareTo(right.title));
      expect(arcEpisodes, hasLength(2));
      expect(arcEpisodes.every((item) => item.itemType == 'episode'), isTrue);
      expect(arcEpisodes.every((item) => item.seasonNumber == 2), isTrue);
      expect(arcEpisodes[0].episodeNumber, 1);
      expect(arcEpisodes[1].episodeNumber, 2);
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
