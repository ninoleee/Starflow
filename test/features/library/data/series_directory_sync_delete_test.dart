import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/library/application/webdav_scrape_progress.dart';
import 'package:starflow/features/library/data/media_repository.dart';
import 'package:starflow/features/library/data/nas_media_index_store.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/imdb_rating_client.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:xml/xml.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final deleteKind in ['series', 'season', 'episode']) {
    test('both remotes delete exactly the $deleteKind scope including sidecars',
        () async {
      SharedPreferences.setMockInitialValues({});
      const root = '/dav/strm/115/';
      const show = '不良执念清除师';
      const seriesPath = '$root$show';
      const seasonPath = '$seriesPath/Season 1';
      const source = MediaSourceConfig(
        id: 'nas-115',
        name: 'NAS',
        kind: MediaSourceKind.nas,
        endpoint: 'https://nas.test/dav/strm/',
        libraryPath: 'https://nas.test/dav/strm/',
        enabled: true,
        webDavStructureInferenceEnabled: true,
        webDavSidecarScrapingEnabled: false,
        webDavSeriesTitleFilterKeywords: ['115', 'strm'],
      );
      final webDavDirectories = <String>{
        '/dav/strm/',
        root,
        '$seriesPath/',
        '$seasonPath/',
        if (deleteKind == 'season') '$seriesPath/Season 2/',
        '$root$show(1)/',
        '$root$show(1)/Season 1/',
      };
      final webDavFiles = <String>{
        '$seriesPath/banner.png',
        '$seriesPath/clearlogo.png',
        '$seriesPath/season01-poster.jpg',
        '$seriesPath/tvshow.nfo',
        '$seasonPath/S01E01.strm',
        '$seasonPath/S01E01.jpg',
        '$seasonPath/S01E01.srt',
        '$seasonPath/S01E02.strm',
        if (deleteKind == 'season') '$seriesPath/Season 2/S02E01.strm',
        '$root$show(1)/Season 1/S01E01.strm',
      };
      final operations = <String>[];
      String decodedPath(Uri uri) => '/${uri.pathSegments.join('/')}';
      final webDav = WebDavNasClient(MockClient((request) async {
        final path = decodedPath(request.url);
        operations.add('webdav ${request.method} $path');
        if (request.method == 'DELETE') {
          webDavFiles.removeWhere(
              (entry) => entry == path || entry.startsWith('$path/'));
          webDavDirectories.removeWhere(
              (entry) => entry == '$path/' || entry.startsWith('$path/'));
          return http.Response('', 204);
        }
        expect(request.method, 'PROPFIND');
        final directory = path.endsWith('/') ? path : '$path/';
        if (!webDavDirectories.contains(directory)) {
          return http.Response('', 404);
        }
        bool isChild(String entry) {
          if (!entry.startsWith(directory)) return false;
          final relative = entry.substring(directory.length);
          final name = relative.endsWith('/')
              ? relative.substring(0, relative.length - 1)
              : relative;
          return name.isNotEmpty && !name.contains('/');
        }

        return http.Response(
          _directoryXml([
            directory,
            ...webDavDirectories.where(isChild),
            ...webDavFiles.where(isChild),
          ]),
          207,
          headers: {'content-type': 'application/xml; charset=utf-8'},
        );
      }));
      final driveEntries = <String, List<Map<String, String>>>{
        '10': [
          {'cid': '20', 'n': show},
          {'cid': '21', 'n': '$show(1)'},
        ],
        '20': [
          {'cid': '30', 'n': 'Season 1'},
          if (deleteKind == 'season') {'cid': '31', 'n': 'Season 2'},
          {'fid': '40', 'n': 'banner.png'},
          {'fid': '41', 'n': 'clearlogo.png'},
          {'fid': '42', 'n': 'season01-poster.jpg'},
          {'fid': '43', 'n': 'tvshow.nfo'},
        ],
        '30': [
          {'fid': '50', 'n': 'S01E01.mkv'},
          {'fid': '51', 'n': 'S01E02.mkv'},
          {'fid': '52', 'n': 'S01E01.jpg'},
          {'fid': '53', 'n': 'S01E01.srt'},
        ],
        '21': [
          {'fid': '60', 'n': 'S01E01.mkv'},
        ],
        if (deleteKind == 'season')
          '31': [
            {'fid': '61', 'n': 'S02E01.mkv'},
          ],
      };
      void removeDriveEntry(String id) {
        final children = driveEntries.remove(id);
        if (children == null) return;
        for (final child in children) {
          if (child['cid'] != null) removeDriveEntry(child['cid']!);
        }
      }

      final drive = Cloud115SaveClient(MockClient((request) async {
        operations.add('115 ${request.method} ${request.url.path}');
        if (request.method == 'POST') {
          expect(request.url.path, '/rb/delete');
          final body = Uri.splitQueryString(request.body);
          final (parentId, id) = switch (deleteKind) {
            'series' => ('10', '20'),
            'season' => ('20', '30'),
            _ => ('30', '50'),
          };
          expect(body, {'pid': parentId, 'fid[0]': id});
          driveEntries[parentId]!
              .removeWhere((entry) => (entry['fid'] ?? entry['cid']) == id);
          removeDriveEntry(id);
          return http.Response('{"state":true}', 200);
        }
        final entries = driveEntries[request.url.queryParameters['cid']];
        expect(entries, isNotNull);
        return http.Response(
            jsonEncode(
                {'state': true, 'count': entries!.length, 'data': entries}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }));
      final settings = SeedData.defaultSettings.copyWith(
        mediaSources: [source],
        wmdbMetadataMatchEnabled: false,
        tmdbMetadataMatchEnabled: false,
        imdbRatingMatchEnabled: false,
        networkStorage: const NetworkStorageConfig(
          cloud115Cookie: 'cookie',
          cloud115SaveFolderId: '10',
          cloud115SaveFolderPath: '/movies',
          syncDelete115Enabled: true,
          syncDelete115WebDavDirectories: [
            NetworkStorageWebDavDirectory(
                sourceId: 'nas-115', directoryId: 'https://nas.test$root'),
          ],
        ),
      );
      final database = await databaseFactoryMemory.openDatabase(deleteKind);
      addTearDown(database.close);
      final noMetadata = MockClient((_) async => fail('No metadata expected'));
      final indexer = NasMediaIndexer(
        store: SembastNasMediaIndexStore(databaseOpener: () async => database),
        webDavNasClient: webDav,
        wmdbMetadataClient: WmdbMetadataClient(noMetadata),
        tmdbMetadataClient: TmdbMetadataClient(noMetadata),
        imdbRatingClient: ImdbRatingClient(noMetadata),
        readSettings: () => settings,
        progressController: WebDavScrapeProgressController(),
      );
      addTearDown(indexer.dispose);
      final container = ProviderContainer(overrides: [
        appSettingsProvider.overrideWithValue(settings),
        webDavNasClientProvider.overrideWithValue(webDav),
        cloud115SaveClientProvider.overrideWithValue(drive),
        nasMediaIndexerProvider.overrideWithValue(indexer),
      ]);
      addTearDown(container.dispose);

      await indexer.refreshSource(source);
      final series = (await indexer.loadLibrary(source)).singleWhere((item) =>
          !decodedPath(Uri.parse(item.actualAddress)).contains('(1)'));
      final seasons = await indexer.loadChildren(source, parentId: series.id);
      final season = seasons.firstWhere((item) => item.seasonNumber == 1);
      final episodes = await indexer.loadChildren(source, parentId: season.id);
      expect(decodedPath(Uri.parse(series.actualAddress)), seriesPath);
      expect(decodedPath(Uri.parse(season.actualAddress)), seasonPath);
      final target = switch (deleteKind) {
        'series' => series,
        'season' => season,
        _ => episodes.first,
      };
      final resourcePath =
          deleteKind == 'episode' ? target.id : target.actualAddress;
      operations.clear();
      await container.read(mediaRepositoryProvider).deleteResource(
            sourceId: source.id,
            resourcePath: resourcePath,
            sectionId: target.sectionId,
          );

      final webDavWrite =
          operations.indexWhere((op) => op.startsWith('webdav DELETE'));
      final driveWrite = operations.indexOf('115 POST /rb/delete');
      expect(webDavWrite, greaterThanOrEqualTo(0));
      expect(driveWrite, greaterThan(webDavWrite + 1));
      expect(operations.last, '115 GET /files');
      expect(webDavFiles, contains('$root$show(1)/Season 1/S01E01.strm'));
      expect(driveEntries['21'], isNotEmpty);
      final records = await indexer.loadSourceRecords(source.id);
      expect(records.length, deleteKind == 'series' ? 1 : 2);
      if (deleteKind == 'series') {
        expect(webDavDirectories, isNot(contains('$seriesPath/')));
        expect(webDavFiles.any((path) => path.startsWith('$seriesPath/')),
            isFalse);
        expect(driveEntries.containsKey('20'), isFalse);
        expect(driveEntries.containsKey('30'), isFalse);
      } else {
        expect(webDavFiles, contains('$seriesPath/banner.png'));
        expect(driveEntries.containsKey('20'), isTrue);
        if (deleteKind == 'season') {
          expect(webDavDirectories, isNot(contains('$seasonPath/')));
          expect(driveEntries.containsKey('30'), isFalse);
          expect(webDavFiles, contains('$seriesPath/Season 2/S02E01.strm'));
          expect(driveEntries['31'], isNotEmpty);
        } else {
          expect(webDavFiles, contains('$seasonPath/S01E02.strm'));
          expect(
              driveEntries['30']!.any((entry) => entry['fid'] == '51'), isTrue);
        }
      }
    });
  }
}

String _directoryXml(List<String> paths) {
  final builder = XmlBuilder();
  builder.element('d:multistatus', attributes: {'xmlns:d': 'DAV:'}, nest: () {
    for (final path in paths) {
      builder.element('d:response', nest: () {
        builder.element('d:href', nest: Uri(path: path).toString());
        builder.element('d:propstat', nest: () {
          builder.element('d:prop', nest: () {
            builder.element('d:resourcetype', nest: () {
              if (path.endsWith('/')) builder.element('d:collection');
            });
          });
          builder.element('d:status', nest: 'HTTP/1.1 200 OK');
        });
      });
    }
  });
  return builder.buildDocument().toXmlString();
}
