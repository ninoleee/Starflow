import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';

void main() {
  const source = MediaSourceConfig(
    id: 'nas',
    name: 'NAS',
    kind: MediaSourceKind.nas,
    endpoint: 'https://nas.test/dav/strm/115/',
    enabled: true,
    webDavExcludedPathKeywords: ['Example Show'],
  );
  for (final outcome in ['removed', 'still-exists', 'unreadable', 'empty']) {
    for (final suffix in ['', '/']) {
      test(
          'directory deletion verifies unfiltered remote state: $outcome$suffix',
          () async {
        final requests = <http.Request>[];
        final client = WebDavNasClient(MockClient((request) async {
          requests.add(request);
          if (request.method == 'DELETE') {
            expect(request.url.path, '/dav/strm/115/Example%20Show$suffix');
            return http.Response('', 204);
          }
          expect(request.method, 'PROPFIND');
          expect(request.url.path, '/dav/strm/115/');
          if (outcome == 'unreadable') return http.Response('', 503);
          if (outcome == 'empty') return http.Response('', 207);
          return http.Response('''<d:multistatus xmlns:d="DAV:">
<d:response><d:href>/dav/strm/115/</d:href><d:propstat><d:prop>
<d:resourcetype><d:collection/></d:resourcetype>
</d:prop></d:propstat></d:response>
${outcome == 'still-exists' ? '''<d:response>
<d:href>/dav/strm/115/Example%20Show/</d:href><d:propstat><d:prop>
<d:resourcetype><d:collection/></d:resourcetype>
</d:prop></d:propstat></d:response>''' : ''}
</d:multistatus>''', 207);
        }));
        final result = client.deleteResource(
          source,
          resourcePath: '/dav/strm/115/Example Show$suffix',
        );
        if (outcome == 'removed') {
          await result;
        } else {
          await expectLater(result, throwsA(isA<Exception>()));
        }
        expect(
            requests.map((request) => request.method), ['DELETE', 'PROPFIND']);
      });
    }
  }
}
