import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/settings/data/webdav_sync_service.dart';

void main() {
  const config = WebDavSyncConfig(
    url: 'https://example.com/dav/',
    directory: 'Starflow/我的收藏',
    username: 'user',
    password: 'secret',
  );
  final snapshot = WebDavSyncSnapshot(
    settings: SeedData.defaultSettings,
    favorites: const [],
  );

  test('encodes directory segments and preserves server base path', () {
    expect(config.fileUri.pathSegments,
        ['dav', 'Starflow', '我的收藏', 'starflow-sync.json']);
    expect(config.fileUri.toString(), contains('%E6%88%91'));
    for (final url in [
      'ftp://example.com',
      'https://u:p@example.com',
      'https://example.com/?token=secret',
      'invalid'
    ]) {
      expect(() => WebDavSyncConfig(url: url).fileUri, throwsFormatException);
    }
    expect(
        () => const WebDavSyncConfig(
                url: 'https://example.com', directory: '../escape')
            .fileUri,
        throwsFormatException);
  });

  test('connection probe is read-only, authenticated and disables redirects',
      () async {
    final service = WebDavSyncService(MockClient((request) async {
      expect(request.method, 'PROPFIND');
      expect(request.url, config.directoryUri);
      expect(request.headers['Depth'], '0');
      expect(request.headers['Authorization'],
          'Basic ${base64Encode(utf8.encode('user:secret'))}');
      expect(request.followRedirects, isFalse);
      return http.Response('', 207);
    }));
    await service.testConnection(config);
  });

  test('creates nested directories and conditionally creates snapshot',
      () async {
    final methods = <String>[];
    final service = WebDavSyncService(MockClient((request) async {
      methods.add(request.method);
      if (request.method == 'MKCOL') return http.Response('', 201);
      if (request.method == 'GET') return http.Response('', 404);
      expect(request.headers['If-None-Match'], '*');
      final decoded = WebDavSyncSnapshot.decode(request.body);
      expect(decoded.settings, isNotNull);
      expect(decoded.favorites, isEmpty);
      expect(request.body, isNot(contains('secret')));
      return http.Response('', 201);
    }));
    await service.upload(config, snapshot);
    expect(methods, ['MKCOL', 'MKCOL', 'GET', 'PUT']);
  });

  test('partial upload preserves remote settings and honors ETag conflicts',
      () async {
    const favoritesOnly = WebDavSyncConfig(
        url: 'https://example.com', directory: '', settings: false);
    final service = WebDavSyncService(MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response.bytes(
            utf8.encode(jsonEncode(snapshot.toJson())), 200,
            headers: {'etag': '"revision-1"'});
      }
      expect(request.headers['If-Match'], '"revision-1"');
      expect(WebDavSyncSnapshot.decode(request.body).settings!.toJson(),
          snapshot.settings!.toJson());
      return http.Response('', 412);
    }));
    await expectLater(
        service.upload(favoritesOnly, const WebDavSyncSnapshot(favorites: [])),
        throwsStateError);
  });

  test('download validates format, schema and selected content', () async {
    for (final body in [
      '<html>login</html>',
      jsonEncode({'format': 'starflow-sync', 'version': 99}),
      jsonEncode(const WebDavSyncSnapshot(favorites: []).toJson()),
      jsonEncode({
        ...snapshot.toJson(),
        'settings': {'schemaVersion': 2}
      }),
      jsonEncode({
        ...snapshot.toJson(),
        'favorites': [
          {'title': ''}
        ]
      }),
    ]) {
      final service = WebDavSyncService(
          MockClient((_) async => http.Response.bytes(utf8.encode(body), 200)));
      await expectLater(service.download(config), throwsA(anything));
    }
    final service = WebDavSyncService(MockClient((_) async =>
        http.Response.bytes(utf8.encode(jsonEncode(snapshot.toJson())), 200)));
    expect((await service.download(config)).favorites, isEmpty);
  });

  test('authentication and redirect failures never become snapshots', () async {
    for (final status in [401, 403, 404, 302, 500]) {
      final service =
          WebDavSyncService(MockClient((_) async => http.Response('', status)));
      await expectLater(service.download(config), throwsStateError);
    }
  });
}
