import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/settings/domain/webdav_sync_config.dart';
import 'package:starflow/features/update/domain/update_source.dart';
import 'package:starflow/features/update/domain/app_update.dart';
import 'package:starflow/features/update/data/update_manifest_client.dart';
import 'package:starflow/features/update/data/update_package_downloader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = UpdateSource.fromSync(const WebDavSyncConfig(
      url: 'https://dav.example/dav',
      directory: 'Starflow',
      username: 'reader',
      password: 'secret'));
  final authorization = 'Basic ${base64Encode(utf8.encode('reader:secret'))}';
  test('uses sync base and directory with bounded credential scope', () {
    expect(source.manifestUri.toString(),
        'https://dav.example/dav/Starflow/releases/latest.json');
    expect(
        source.headersFor(source.manifestUri)['Authorization'], authorization);
    final unicode = UpdateSource.fromSync(const WebDavSyncConfig(
        url: 'https://dav.example/dav/', directory: '我的同步/Starflow'));
    expect(unicode.manifestUri.pathSegments, contains('我的同步'));
    expect(unicode.headersFor(unicode.manifestUri), isEmpty);
  });
  for (final target in [
    'https://cdn.example/file.apk',
    'https://dav.example:8443/dav/Starflow/releases/a',
    'http://dav.example/dav/Starflow/releases/a',
    'https://dav.example/dav/Starflow/starflow-sync.json',
    'https://dav.example/dav/Starflow/releases-other/a',
    'https://dav.example/dav/Starflow/releases/%2e%2e/a',
    'https://dav.example/dav/Starflow/releases/%252e%252e/a',
    'https://dav.example/dav/Starflow/releases/a%2fb',
  ]) {
    test('rejects credential scope escape $target', () {
      expect(() => source.headersFor(Uri.parse(target)),
          throwsA(isA<UpdateFailure>()));
    });
  }
  for (final url in [
    'http://dav.example',
    'https://@dav.example',
    'https://dav.example/#x'
  ]) {
    test('invalid sync URL is rejected $url', () {
      expect(() => UpdateSource.fromSync(WebDavSyncConfig(url: url)),
          throwsA(isA<UpdateFailure>()));
    });
  }

  test('plain JSON manifest and APK both use sync credentials', () async {
    final bytes = [80, 75, 3, 4];
    final artifactUrl = source.directory.resolve('200/starflow-tv-1.9.1.apk');
    final payload = utf8.encode(jsonEncode({
      'schemaVersion': 1,
      'appId': 'com.example.starflow',
      'channel': 'stable',
      'version': '1.9.1',
      'versionCode': 200,
      'publishedAt': '2026-09-26T00:00:00Z',
      'releaseNotes': ['Fix'],
      'artifacts': [
        {
          'platform': 'android',
          'variant': 'tv',
          'fileName': 'starflow-tv-1.9.1.apk',
          'url': artifactUrl.toString(),
          'size': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
          'minSdk': 23,
          'certificateSha256': 'a' * 64,
        }
      ],
    }));
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], authorization);
      expect(request.followRedirects, isFalse);
      if (request.url == source.manifestUri) {
        return http.Response.bytes(payload, 200);
      }
      expect(request.url, artifactUrl);
      return http.Response.bytes(bytes, 200);
    });
    final manifest = UpdateManifestClient(client: client);
    final release = await manifest.fetch(source.manifestUri, source: source);
    final root = await Directory.systemTemp.createTemp('sync-update-');
    final downloader = UpdatePackageDownloader(client: client, directory: root);
    try {
      final path = await downloader.download(release.artifacts.single,
          source: source, onProgress: (_) {}, onVerifying: () {});
      expect(await File(path).readAsBytes(), bytes);
    } finally {
      manifest.close();
      await downloader.dispose();
      await root.delete(recursive: true);
    }
  });

  for (final status in [401, 403, 404]) {
    test('WebDAV status $status has an actionable safe error', () async {
      final client =
          MockClient((_) async => http.Response('private server body', status));
      final manifest = UpdateManifestClient(client: client);
      try {
        await expectLater(
            manifest.fetch(source.manifestUri, source: source),
            throwsA(isA<UpdateFailure>().having((e) => e.code, 'code',
                status == 404 ? 'updateNotPublished' : 'updateUnauthorized')));
      } finally {
        manifest.close();
        client.close();
      }
    });
  }

  for (final location in [
    'https://other.example/package',
    '/dav/Starflow/starflow-sync.json'
  ]) {
    test('manifest and APK reject redirected credential escape $location',
        () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        expect(request.headers['Authorization'], authorization);
        return http.Response('', 302, headers: {'location': location});
      });
      final manifest = UpdateManifestClient(client: client);
      await expectLater(manifest.fetch(source.manifestUri, source: source),
          throwsA(isA<UpdateFailure>()));
      expect(requests, 1);
      manifest.close();
      final root = await Directory.systemTemp.createTemp('sync-redirect-');
      final downloader =
          UpdatePackageDownloader(client: client, directory: root);
      try {
        await expectLater(
            downloader.download(
                UpdateArtifact(
                    platform: 'android',
                    variant: 'tv',
                    url: source.directory.resolve('200/starflow-tv-1.9.1.apk'),
                    fileName: 'starflow-tv-1.9.1.apk',
                    size: 4,
                    sha256: 'a' * 64,
                    minSdk: 23,
                    certificateSha256: 'b' * 64),
                source: source,
                onProgress: (_) {},
                onVerifying: () {}),
            throwsA(isA<UpdateFailure>()));
        expect(requests, 2);
      } finally {
        await downloader.dispose();
        await root.delete(recursive: true);
      }
    });
  }
}
