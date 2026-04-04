import 'package:flutter_test/flutter_test.dart';
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

      final movie = items.firstWhere((item) => item.title == 'Interstellar');
      expect(
        movie.streamUrl,
        'https://nas.example.com/dav/Movies/Interstellar.mkv',
      );
      expect(movie.addedAt, DateTime.utc(2026, 4, 2, 8, 30, 0));

      final strm = items.firstWhere((item) => item.title == 'One Piece');
      expect(
        strm.streamUrl,
        'https://media.example.com/streams/one-piece/master.m3u8',
      );
      expect(strm.overview, strm.streamUrl);
      expect(strm.addedAt, DateTime.utc(2026, 4, 3, 9, 0, 0));
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
</d:multistatus>''';
