import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:starflow/features/library/data/webdav_directory_cache_store.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';

void main() {
  test('reuses an unchanged WebDAV subtree after the client is recreated',
      () async {
    final database = await databaseFactoryMemory.openDatabase(
      'webdav-cache-${DateTime.now().microsecondsSinceEpoch}',
    );
    final store = WebDavDirectoryCacheStore(
      databaseOpener: () async => database,
    );
    var rootRequests = 0;
    var childRequests = 0;
    final httpClient = MockClient((request) async {
      if (request.url.path == '/dav/') {
        rootRequests += 1;
        return http.Response(_rootResponse, 207);
      }
      if (request.url.path == '/dav/Shows/') {
        childRequests += 1;
        return http.Response(_childResponse, 207);
      }
      return http.Response('not found', 404);
    });
    const source = MediaSourceConfig(
      id: 'persistent-webdav-cache',
      name: 'Persistent cache',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/',
      enabled: true,
    );

    final first = WebDavNasClient(
      httpClient,
      directoryCacheStore: store,
    );
    expect(
      await first.scanLibrary(source, resolvePlayableStreams: false),
      hasLength(1),
    );
    for (var index = 0; index < 8; index++) {
      await Future<void>.delayed(Duration.zero);
    }

    final second = WebDavNasClient(
      httpClient,
      directoryCacheStore: store,
    );
    expect(
      await second.scanLibrary(source, resolvePlayableStreams: false),
      hasLength(1),
    );
    expect(rootRequests, 2);
    expect(childRequests, 1);
    await database.close();
  });
}

const _rootResponse = '''
<d:multistatus xmlns:d="DAV:">
  <d:response><d:href>/dav/</d:href><d:propstat><d:prop>
    <d:resourcetype><d:collection/></d:resourcetype>
  </d:prop></d:propstat></d:response>
  <d:response><d:href>/dav/Shows/</d:href><d:propstat><d:prop>
    <d:displayname>Shows</d:displayname>
    <d:resourcetype><d:collection/></d:resourcetype>
    <d:getetag>"shows-v1"</d:getetag>
  </d:prop></d:propstat></d:response>
</d:multistatus>
''';

const _childResponse = '''
<d:multistatus xmlns:d="DAV:">
  <d:response><d:href>/dav/Shows/</d:href><d:propstat><d:prop>
    <d:resourcetype><d:collection/></d:resourcetype>
  </d:prop></d:propstat></d:response>
  <d:response><d:href>/dav/Shows/Episode01.mkv</d:href><d:propstat><d:prop>
    <d:displayname>Episode01.mkv</d:displayname>
    <d:resourcetype/>
    <d:getcontentlength>1024</d:getcontentlength>
  </d:prop></d:propstat></d:response>
</d:multistatus>
''';
