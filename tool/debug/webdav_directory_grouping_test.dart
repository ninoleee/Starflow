import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:starflow/features/library/application/webdav_scrape_progress.dart';
import 'package:starflow/features/library/data/nas_media_index_store.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/data/nas_media_path_policy.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/imdb_rating_client.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  final configPath = Platform.environment['STARFLOW_SETTINGS_JSON'];
  final relativeDirectory = Platform.environment['STARFLOW_CHECK_DIRECTORY'];
  test('real WebDAV title directory produces exactly one library entry',
      () async {
    final settings = AppSettings.fromJson(
      jsonDecode(await File(configPath!).readAsString())
          as Map<String, dynamic>,
    );
    final source = settings.mediaSources
        .firstWhere(
          (source) => source.kind == MediaSourceKind.nas && source.enabled,
        )
        .copyWith(webDavSidecarScrapingEnabled: false);
    final section =
        source.libraryPath.isEmpty ? source.endpoint : source.libraryPath;
    final root = Uri.parse(section.endsWith('/') ? section : '$section/');
    final target = root.resolve(relativeDirectory!);
    expect(target.origin, root.origin);
    expect(target.path.startsWith(root.path), isTrue);
    final network = http.Client();
    addTearDown(network.close);
    final scanned = await WebDavNasClient(network).scanLibrary(
      source.copyWith(webDavStructureInferenceEnabled: false),
      sectionId: target.toString(),
      limit: 1000,
      loadSidecarMetadata: false,
      resolvePlayableStreams: false,
    );
    final resolved = applyExternalDirectoryStructureInference([
      for (final item in scanned)
        ExternalScanPendingItem(
          resourceId: item.resourceId,
          fileName: item.fileName,
          actualAddress: item.actualAddress,
          sectionId: section,
          sectionName: 'library',
          streamUrl: item.streamUrl,
          streamHeaders: item.streamHeaders,
          addedAt: item.addedAt,
          modifiedAt: item.modifiedAt,
          fileSizeBytes: item.fileSizeBytes,
          metadataSeed: item.metadataSeed,
          relativeDirectories: NasMediaPathPolicy.resolvePathContext(
            resourcePath: item.resourceId,
            sectionId: section,
          ).relativeDirectories,
        ),
    ], source: source);
    final database =
        await databaseFactoryMemory.openDatabase('directory-check');
    addTearDown(database.close);
    final offline = MockClient((request) async {
      throw StateError('Metadata network access is disabled for this check');
    });
    final store =
        SembastNasMediaIndexStore(databaseOpener: () async => database);
    final indexer = NasMediaIndexer(
      store: store,
      webDavNasClient: _ScannedClient(
        resolved.map((item) => item.toScannedItem()).toList(),
      ),
      wmdbMetadataClient: WmdbMetadataClient(offline),
      tmdbMetadataClient: TmdbMetadataClient(offline),
      imdbRatingClient: ImdbRatingClient(offline),
      readSettings: () => settings.copyWith(
        wmdbMetadataMatchEnabled: false,
        tmdbMetadataMatchEnabled: false,
        imdbRatingMatchEnabled: false,
      ),
      progressController: WebDavScrapeProgressController(),
    );
    addTearDown(indexer.dispose);
    await indexer.refreshSource(source);
    final library = await indexer.loadLibrary(source);
    expect(library, hasLength(1));
    final seasons =
        await indexer.loadChildren(source, parentId: library.single.id);
    final counts = <int?, int>{};
    final variants = <int?, List<int>>{};
    for (final season in seasons) {
      final episodes =
          await indexer.loadChildren(source, parentId: season.id, limit: 1000);
      counts[season.seasonNumber] = episodes.length;
      variants[season.seasonNumber] = [
        for (final episode in episodes)
          (await indexer.loadEpisodeVariants(source, itemId: episode.id))
              .length,
      ];
    }
    if (relativeDirectory.contains('重启人生')) {
      expect(await store.loadSourceRecords(source.id), hasLength(39));
      expect(resolved, hasLength(39));
      expect(counts, {0: 9, 1: 10});
      expect(variants[1], everyElement(3));
      expect(variants[0], everyElement(1));
    }
    debugPrintSynchronously(
        'Resources: ${scanned.length}; library entries: ${library.length}; '
        'type: ${library.single.itemType}; title: ${library.single.title}; '
        'episodes by season: $counts; variants: $variants');
  }, skip: configPath == null || relativeDirectory == null);
}

class _ScannedClient extends WebDavNasClient {
  _ScannedClient(this.items)
      : super(MockClient((request) async => http.Response('', 404)));

  final List<WebDavScannedItem> items;

  @override
  Future<List<WebDavScannedItem>> scanLibrary(
    MediaSourceConfig source, {
    String? sectionId,
    String sectionName = '',
    int limit = 200,
    bool? loadSidecarMetadata,
    bool resolvePlayableStreams = true,
    bool resetCaches = true,
    bool Function()? shouldCancel,
  }) async =>
      items;
}
