import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/search/domain/favorite_sync_document.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/data/settings_transfer_service_io.dart';
import 'package:starflow/features/settings/data/webdav_sync_service.dart';

String directoryResponse(String href,
        {bool collection = true, int propertyStatus = 200}) =>
    '''<d:multistatus xmlns:d="DAV:"><d:response>
<d:href>${htmlEscape.convert(href)}</d:href><d:propstat><d:prop>
<d:resourcetype>${collection ? '<d:collection/>' : ''}</d:resourcetype>
</d:prop><d:status>HTTP/1.1 $propertyStatus Status</d:status></d:propstat>
</d:response></d:multistatus>''';

String deviceListing(Uri directory, Iterable<String> hrefs,
    {int status = 200, bool collection = false}) {
  final files = hrefs.map((href) => '''<d:response>
<d:href>${htmlEscape.convert(href)}</d:href><d:propstat><d:prop>
<d:resourcetype>${collection ? '<d:collection/>' : ''}</d:resourcetype>
</d:prop><d:status>HTTP/1.1 $status Status</d:status></d:propstat>
</d:response>''').join();
  return directoryResponse(directory.path)
      .replaceFirst('</d:multistatus>', '$files</d:multistatus>');
}

FavoriteSyncDocument favoriteDocument(String id) {
  final result = SearchResult(
      id: id,
      title: id,
      posterUrl: '',
      providerId: 'test',
      providerName: 'Test',
      quality: '',
      sizeLabel: '',
      seeders: 0,
      summary: '',
      resourceUrl: 'https://example.com/$id');
  return FavoriteSyncDocument()
      .setFavorite(searchResultFavoriteKey(result), result);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  const deviceId = '0123456789abcdef0123456789abcdef';
  const otherId = 'abcdef0123456789abcdef0123456789';
  final ownUri = config.favoriteDeviceFileUri(deviceId);
  final otherUri = config.favoriteDeviceFileUri(otherId);

  for (final header in [
    null,
    'unquoted-version',
    'W/"weak-version"',
    '"strong"'
  ]) {
    test('device files sync independently of ETag $header', () async {
      final original = favoriteDocument('own');
      final other = favoriteDocument('other');
      final legacy = favoriteDocument('legacy');
      final files = {
        ownUri: original,
        otherUri: other,
        config.favoritesFileUri: legacy
      };
      final requests = <String>[];
      final service = WebDavSyncService(MockClient((request) async {
        requests.add(request.method);
        expect(request.followRedirects, isFalse);
        expect(request.headers['Authorization'],
            'Basic ${base64Encode(utf8.encode('user:secret'))}');
        if (request.method == 'PROPFIND') {
          expect(request.url, config.directoryUri);
          expect(request.headers['Depth'], '1');
          expect(request.headers['Cache-Control'], 'no-cache');
          return http.Response(
              deviceListing(config.directoryUri,
                  [ownUri.toString(), otherUri.path, otherUri.path]),
              207);
        }
        if (request.method == 'GET') {
          expect(request.headers['Cache-Control'], 'no-cache');
          return http.Response(files[request.url]!.encode(), 200,
              headers: {if (header != null) 'etag': header});
        }
        expect(request.method, 'PUT');
        expect(request.url, ownUri);
        expect(request.headers.containsKey('If-Match'), isFalse);
        expect(request.headers.containsKey('If-None-Match'), isFalse);
        files[ownUri] = FavoriteSyncDocument.decode(request.body);
        return http.Response('', 204);
      }));
      final remote = await service.readFavorites(config, deviceId: deviceId);
      expect(remote.deviceDocument!.encode(), original.encode());
      expect(remote.deviceNeedsCompaction, isTrue);
      expect(remote.deviceCount, 2);
      final merged = FavoriteSyncDocument().mergeAll(remote.documents);
      expect(merged.favorites.map((e) => e.id).toSet(),
          {'own', 'other', 'legacy'});
      await service.writeFavorites(config, merged, deviceId: deviceId);
      await service.verifyFavoritesWrite(config, merged, deviceId: deviceId);
      expect(files[otherUri]!.encode(), other.encode());
      expect(files[config.favoritesFileUri]!.encode(), legacy.encode());
      expect(requests, ['PROPFIND', 'GET', 'GET', 'GET', 'PUT', 'GET']);
    });
  }

  test('directory discovery ignores foreign paths and unrelated files',
      () async {
    final gets = <Uri>[];
    final service = WebDavSyncService(MockClient((request) async {
      if (request.method == 'PROPFIND') {
        return http.Response(
            deviceListing(config.directoryUri, [
              otherUri.path,
              otherUri.replace(host: 'other.example.com').toString(),
              otherUri.replace(query: 'token=secret').toString(),
              otherUri.replace(fragment: 'fragment').toString(),
              otherUri.replace(userInfo: 'user:pass').toString(),
              '/outside/${otherUri.pathSegments.last}',
              '${config.directoryUri.path}sub/${otherUri.pathSegments.last}',
              '${config.directoryUri.path}starflow-sync.json',
              '${config.directoryUri.path}starflow-favorites-invalid.json',
            ]),
            207);
      }
      expect(request.method, 'GET');
      gets.add(request.url);
      return request.url == otherUri
          ? http.Response(favoriteDocument('other').encode(), 200)
          : http.Response('', 404);
    }));
    final remote = await service.readFavorites(config, deviceId: deviceId);
    expect(remote.documents.single.favorites.single.id, 'other');
    expect(remote.deviceDocument, isNull);
    expect(remote.deviceNeedsCompaction, isFalse);
    expect(gets, [config.favoritesFileUri, ownUri, otherUri]);
  });

  test('own device file is loaded even when missing from cached listing',
      () async {
    final service = WebDavSyncService(MockClient((request) async {
      if (request.method == 'PROPFIND') {
        return http.Response(deviceListing(config.directoryUri, []), 207);
      }
      return request.url == ownUri
          ? http.Response(favoriteDocument('own').encode(), 200)
          : http.Response('', 404);
    }));
    final remote = await service.readFavorites(config, deviceId: deviceId);
    expect(remote.deviceDocument!.favorites.single.id, 'own');
    expect(remote.deviceCount, 1);
  });

  test('missing sync directory stays read only until there are changes',
      () async {
    final requests = <String>[];
    final service = WebDavSyncService(MockClient((request) async {
      requests.add(request.method);
      return http.Response('', 404);
    }));
    final remote = await service.readFavorites(config, deviceId: deviceId);
    expect(remote.documents, isEmpty);
    expect(remote.deviceDocument, isNull);
    expect(requests, ['PROPFIND']);
  });

  test(
      'invalid or unauthorized device discovery does not proceed to file writes',
      () async {
    for (final response in [
      http.Response('', 401),
      http.Response('', 403),
      http.Response('', 302),
      http.Response('', 405),
      http.Response('', 500),
      http.Response('', 207),
      http.Response('<broken', 207),
      http.Response('<html>login</html>', 200),
      http.Response(
          deviceListing(config.directoryUri, [otherUri.path], status: 403),
          207),
      http.Response(
          deviceListing(config.directoryUri, [otherUri.path], collection: true),
          207),
      http.Response(
          deviceListing(config.directoryUri, []).replaceAll('DAV:', 'wrong'),
          207),
    ]) {
      final requests = <String>[];
      final service = WebDavSyncService(MockClient((request) async {
        requests.add(request.method);
        return response;
      }));
      await expectLater(service.readFavorites(config, deviceId: deviceId),
          throwsA(anyOf(isA<StateError>(), isA<FormatException>())));
      expect(requests, ['PROPFIND']);
    }
  });

  test('listed device cannot silently disappear or become invalid', () async {
    for (final response in [
      http.Response('', 404),
      http.Response('', 403),
      http.Response('{broken', 200)
    ]) {
      final service = WebDavSyncService(MockClient((request) async {
        if (request.method == 'PROPFIND') {
          return http.Response(
              deviceListing(config.directoryUri, [otherUri.path]), 207);
        }
        return request.url == otherUri ? response : http.Response('', 404);
      }));
      await expectLater(service.readFavorites(config, deviceId: deviceId),
          throwsA(anyOf(isA<StateError>(), isA<FormatException>())));
    }
  });

  test('device discovery bounds file counts before downloading', () async {
    var requests = 0;
    final service = WebDavSyncService(MockClient((request) async {
      requests++;
      return http.Response(
          deviceListing(
              config.directoryUri,
              List.generate(
                  101,
                  (i) => config
                      .favoriteDeviceFileUri(
                          i.toRadixString(16).padLeft(32, '0'))
                      .path)),
          207);
    }));
    await expectLater(
        service.readFavorites(config, deviceId: deviceId), throwsStateError);
    expect(requests, 1);
  });

  test('invalid device ID is rejected before network access', () async {
    final service = WebDavSyncService(
        MockClient((request) async => throw StateError('unexpected request')));
    for (final id in ['', '../escape', '$deviceId\n', '$deviceId/child']) {
      await expectLater(
          service.readFavorites(config, deviceId: id), throwsFormatException);
      await expectLater(
          service.writeFavorites(config, FavoriteSyncDocument(), deviceId: id),
          throwsFormatException);
    }
  });

  test('readback accepts sent changes plus newer additions or deletions',
      () async {
    final sent = favoriteDocument('sent');
    for (final received in [
      sent,
      sent.merge(favoriteDocument('concurrent')),
      sent.setFavorite(sent.entries.keys.single, null),
    ]) {
      final service = WebDavSyncService(MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url, ownUri);
        expect(request.headers['Cache-Control'], 'no-cache');
        return http.Response(received.encode(), 200);
      }));
      expect(
          (await service.verifyFavoritesWrite(config, sent, deviceId: deviceId))
              .encode(),
          received.encode());
    }
  });

  test('compact write and readback ignore missing presentation fields',
      () async {
    final original = favoriteDocument('one');
    final key = original.entries.keys.single;
    final sent = original.setFavorite(
        key,
        original.favorites.single.copyWith(
            posterUrl: 'https://images.example.com/one.jpg',
            posterHeaders: {'Authorization': 'image-only-secret'}));
    String? stored;
    final service = WebDavSyncService(MockClient((request) async {
      if (request.method == 'PUT') {
        stored = request.body;
        expect(stored, sent.encodeForSync());
        expect(stored, isNot(contains('posterUrl')));
        expect(stored, isNot(contains('image-only-secret')));
        return http.Response('', 204);
      }
      if (request.method == 'PROPFIND') {
        return http.Response(
            deviceListing(config.directoryUri, [ownUri.path]), 207);
      }
      expect(request.method, 'GET');
      return request.url == ownUri
          ? http.Response(stored!, 200)
          : http.Response('', 404);
    }));
    await service.writeFavorites(config, sent, deviceId: deviceId);
    final verified =
        await service.verifyFavoritesWrite(config, sent, deviceId: deviceId);
    expect(verified.encodeForSync(), sent.encodeForSync());
    expect(verified.favorites.single.posterUrl, isEmpty);
    final remote = await service.readFavorites(config, deviceId: deviceId);
    expect(remote.deviceNeedsCompaction, isFalse);
    expect(remote.deviceDocument!.encodeForSync(), sent.encodeForSync());
  });

  test('readback rejects dropped additions and missing deletion records',
      () async {
    final original = favoriteDocument('original');
    for (final sent in [
      original.merge(favoriteDocument('local')),
      original.setFavorite(original.entries.keys.single, null),
    ]) {
      final service = WebDavSyncService(
          MockClient((request) async => http.Response(original.encode(), 200)));
      await expectLater(
          service.verifyFavoritesWrite(config, sent, deviceId: deviceId),
          throwsA(isA<StateError>().having(
              (error) => error.message, 'message', contains('未通过读回验证'))));
    }
  });

  test('readback rejects missing, unauthorized or malformed uploaded files',
      () async {
    for (final response in [
      http.Response('', 404),
      http.Response('private-server-error', 403),
      http.Response('{broken', 200),
    ]) {
      final service =
          WebDavSyncService(MockClient((request) async => response));
      await expectLater(
          service.verifyFavoritesWrite(config, favoriteDocument('sent'),
              deviceId: deviceId),
          throwsA(anyOf(isA<StateError>(), isA<FormatException>())));
    }
  });

  test('file export and import preserve all network sync settings', () async {
    final directory =
        await Directory.systemTemp.createTemp('starflow-sync-export-');
    addTearDown(() => directory.delete(recursive: true));
    final service = createSettingsTransferService();
    final settings = SeedData.defaultSettings.copyWith(webDavSync: config);
    final result = await service.exportSettings(
        settings: settings, targetPath: '${directory.path}/settings.json');
    final imported = await service.importSettings(result.path);
    expect(imported.webDavSync!.toJson(), config.toJson());
    final snapshot = WebDavSyncSnapshot(settings: imported);
    expect(
        WebDavSyncSnapshot.decode(jsonEncode(snapshot.toJson()))
            .settings!
            .webDavSync!
            .toJson(),
        config.toJson());
  });

  test('legacy standalone sync settings migrate into exported app settings',
      () async {
    SharedPreferences.setMockInitialValues({
      'starflow.settings.v2': jsonEncode(SeedData.defaultSettings.toJson()),
      'starflow.webdavSync.v1': jsonEncode(config.toJson()),
    });
    final store = SharedPreferencesStore(await SharedPreferences.getInstance());
    final repository = LocalAppSettingsRepository(preferences: store);
    final migrated = await repository.load();
    expect(migrated.webDavSync!.toJson(), config.toJson());
    expect(
        jsonDecode(
            (await store.getString('starflow.settings.v2'))!)['webDavSync'],
        config.toJson());
    await repository
        .save(migrated.copyWith(webDavSync: const WebDavSyncConfig()));
    expect((await repository.load()).webDavSync!.url, isEmpty);
  });

  test('invalid legacy connection cannot discard otherwise valid app settings',
      () async {
    SharedPreferences.setMockInitialValues({
      'starflow.settings.v2': jsonEncode(SeedData.defaultSettings
          .copyWith(playbackDefaultSpeed: 1.5)
          .toJson()),
      'starflow.webdavSync.v1': '{broken',
    });
    final store = SharedPreferencesStore(await SharedPreferences.getInstance());
    final restored =
        await LocalAppSettingsRepository(preferences: store).load();
    expect(restored.playbackDefaultSpeed, 1.5);
    expect(restored.webDavSync, isNull);
    expect(await store.getString('starflow.webdavSync.v1'), '{broken');
  });

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
    expect(await service.testConnection(config),
        WebDavConnectionTestResult.directoryAvailable);
  });

  test('missing sync directory probes base without creating or uploading',
      () async {
    final paths = <Uri>[];
    final service = WebDavSyncService(MockClient((request) async {
      expect(request.method, 'PROPFIND');
      expect(request.headers['Depth'], '0');
      expect(request.followRedirects, isFalse);
      expect(request.headers['Authorization'],
          'Basic ${base64Encode(utf8.encode('user:secret'))}');
      paths.add(request.url);
      return http.Response('', request.url == config.directoryUri ? 404 : 207);
    }));
    final result = await service.testConnection(config);
    expect(result, WebDavConnectionTestResult.directoryMissing);
    expect(result.message, contains('写入权限尚未验证'));
    expect(paths, [config.directoryUri, config.baseUri]);
  });

  test('missing WebDAV base address is reported separately', () async {
    final service = WebDavSyncService(MockClient((request) async {
      expect(request.method, 'PROPFIND');
      return http.Response('', 404);
    }));
    await expectLater(
        service.testConnection(config),
        throwsA(
          isA<StateError>()
              .having((error) => error.message, 'message', contains('基础地址不存在')),
        ));
  });

  test('empty directory does not probe the same missing base twice', () async {
    var requests = 0;
    final service = WebDavSyncService(MockClient((request) async {
      requests++;
      return http.Response('', 404);
    }));
    await expectLater(
        service.testConnection(const WebDavSyncConfig(
          url: 'https://example.com/dav/',
          directory: '',
        )),
        throwsStateError);
    expect(requests, 1);
  });

  test(
      'authorization and server failures are not treated as missing directories',
      () async {
    for (final status in [401, 403, 302, 405, 500]) {
      var requests = 0;
      final service = WebDavSyncService(MockClient((request) async {
        requests++;
        return http.Response('', status);
      }));
      await expectLater(service.testConnection(config), throwsStateError);
      expect(requests, 1);
    }
  });

  test('base probe errors do not turn a missing directory into success',
      () async {
    for (final status in [401, 403, 302, 405, 500]) {
      final service = WebDavSyncService(MockClient((request) async =>
          http.Response(
              '', request.url == config.directoryUri ? 404 : status)));
      await expectLater(service.testConnection(config), throwsStateError);
    }
  });

  test('creates nested directories and conditionally creates snapshot',
      () async {
    final requests = <String>[];
    final service = WebDavSyncService(MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method == 'MKCOL') return http.Response('', 201);
      if (request.method == 'PROPFIND') {
        expect(request.headers['Depth'], '0');
        expect(request.headers['Cache-Control'], 'no-cache');
        return http.Response(directoryResponse(request.url.path), 207);
      }
      if (request.method == 'GET') return http.Response('', 404);
      expect(request.method, 'PUT');
      expect(request.headers['If-None-Match'], '*');
      final decoded = WebDavSyncSnapshot.decode(request.body);
      expect(decoded.settings, isNotNull);
      expect(decoded.favorites, isEmpty);
      expect(request.body, isNot(contains('secret')));
      return http.Response('', 201);
    }));
    await service.upload(config, snapshot);
    final child = config.directoryUri.path;
    expect(requests, [
      'MKCOL /dav/Starflow/',
      'PROPFIND /dav/Starflow/',
      'MKCOL $child',
      'PROPFIND $child',
      'GET ${config.fileUri.path}',
      'PUT ${config.fileUri.path}',
    ]);
  });

  for (final status in [200, 201, 204, 405]) {
    test('MKCOL $status cannot continue when the directory is still missing',
        () async {
      final requests = <String>[];
      final service = WebDavSyncService(MockClient((request) async {
        requests.add(request.method);
        expect(request.followRedirects, isFalse);
        expect(request.headers['Authorization'],
            'Basic ${base64Encode(utf8.encode('user:secret'))}');
        return http.Response('', request.method == 'MKCOL' ? status : 404);
      }));
      await expectLater(
          service.upload(config, snapshot),
          throwsA(isA<StateError>()
              .having(
                  (e) => e.message, 'message', contains('MKCOL HTTP $status'))
              .having(
                  (e) => e.message, 'message', contains('PROPFIND HTTP 404'))));
      expect(requests, ['MKCOL', 'PROPFIND']);
    });
  }

  test('existing directory after MKCOL 405 allows upload', () async {
    final requests = <String>[];
    final service = WebDavSyncService(MockClient((request) async {
      requests.add(request.method);
      if (request.method == 'MKCOL') return http.Response('', 405);
      if (request.method == 'PROPFIND') {
        // Servers may return an absolute href without the trailing slash.
        final href = request.url.toString();
        return http.Response(
            directoryResponse(href.substring(0, href.length - 1)), 207);
      }
      if (request.method == 'GET') return http.Response('', 404);
      expect(request.method, 'PUT');
      return http.Response('', 201);
    }));
    await service.upload(config, snapshot);
    expect(requests, ['MKCOL', 'PROPFIND', 'MKCOL', 'PROPFIND', 'GET', 'PUT']);
  });

  test('directory creation failures report the phase and stop before upload',
      () async {
    for (final status in [401, 403, 404, 409, 500, 302]) {
      final requests = <String>[];
      final service = WebDavSyncService(MockClient((request) async {
        requests.add(request.method);
        return http.Response('private-server-error', status);
      }));
      await expectLater(
          service.upload(config, snapshot),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message',
                  contains('创建同步目录失败（HTTP $status）'))
              .having((e) => e.message, 'message',
                  isNot(contains('private-server-error')))));
      expect(requests, ['MKCOL']);
    }
  });

  test('directory verification rejects failed probes without uploading',
      () async {
    for (final status in [401, 403, 405, 500, 302]) {
      final requests = <String>[];
      final service = WebDavSyncService(MockClient((request) async {
        requests.add(request.method);
        return http.Response('', request.method == 'MKCOL' ? 201 : status);
      }));
      await expectLater(
          service.upload(config, snapshot),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              contains('验证同步目录失败（HTTP $status）'))));
      expect(requests, ['MKCOL', 'PROPFIND']);
    }
  });

  test('directory verification requires matching successful DAV collection',
      () async {
    for (final body in [
      '',
      '<html>login</html>',
      '<broken',
      directoryResponse('/dav/Starflow/', collection: false),
      directoryResponse('/dav/Starflow/', propertyStatus: 404),
      directoryResponse('/dav/Starflow-other/'),
      directoryResponse('https://other.example/dav/Starflow/'),
      directoryResponse('/dav/Starflow/').replaceAll('DAV:', 'urn:not-dav'),
    ]) {
      for (final status in [200, 207]) {
        final requests = <String>[];
        final service = WebDavSyncService(MockClient((request) async {
          requests.add(request.method);
          return request.method == 'MKCOL'
              ? http.Response('', 405)
              : http.Response(body, status);
        }));
        await expectLater(
            service.upload(config, snapshot),
            throwsA(isA<StateError>().having(
                (e) => e.message, 'message', contains('服务器未确认目标路径为目录'))));
        expect(requests, ['MKCOL', 'PROPFIND']);
      }
    }
  });

  test('PUT 404 reports upload phase after verified directory', () async {
    final requests = <String>[];
    final service = WebDavSyncService(MockClient((request) async {
      requests.add(request.method);
      if (request.method == 'MKCOL') return http.Response('', 201);
      if (request.method == 'PROPFIND') {
        return http.Response(directoryResponse(request.url.path), 207);
      }
      return http.Response('', 404);
    }));
    await expectLater(
        service.upload(config, snapshot),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('上传同步文件失败（HTTP 404）'))));
    expect(requests.last, 'PUT');
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
