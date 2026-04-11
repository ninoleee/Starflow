import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sembast/sembast_io.dart';
import 'package:starflow/features/library/application/webdav_scrape_progress.dart';
import 'package:starflow/features/library/data/nas_media_index_store.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/imdb_rating_client.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('debug current Windows NAS grouping logs', () async {
    debugPrint = debugPrintSynchronously;

    const sharedPrefsPath =
        r'C:\Users\ninol\AppData\Roaming\com.example\starflow\shared_preferences.json';
    const dbPath =
        r'C:\Users\ninol\AppData\Roaming\com.example\starflow\starflow-db\nas_metadata_index.db';

    final outer = jsonDecode(await File(sharedPrefsPath).readAsString())
        as Map<String, dynamic>;
    final settings = AppSettings.fromJson(
      jsonDecode(outer['flutter.starflow.settings.v1'] as String)
          as Map<String, dynamic>,
    );

    final source = settings.mediaSources.firstWhere(
      (item) => item.kind == MediaSourceKind.nas,
    );
    final collectionId = source.featuredSectionIds.isEmpty
        ? 'https://webdav.nux.ink/movies/'
        : source.featuredSectionIds.first;
    const collectionTitle = 'movies';
    final scopedCollections = <MediaCollection>[
      MediaCollection(
        id: collectionId,
        title: collectionTitle,
        sourceId: source.id,
        sourceName: source.name,
        sourceKind: source.kind,
      ),
    ];

    Database? database;
    final store = SembastNasMediaIndexStore(
      databaseOpener: () async {
        database ??= await databaseFactoryIo.openDatabase(dbPath);
        return database!;
      },
    );

    final indexer = NasMediaIndexer(
      store: store,
      webDavNasClient: WebDavNasClient(http.Client()),
      wmdbMetadataClient: WmdbMetadataClient(http.Client()),
      tmdbMetadataClient: TmdbMetadataClient(http.Client()),
      imdbRatingClient: ImdbRatingClient(http.Client()),
      readSettings: () => settings,
      progressController: WebDavScrapeProgressController(),
    );

    final items = await indexer.loadLibrary(
      source,
      sectionId: collectionId,
      scopedCollections: scopedCollections,
      limit: 5000,
    );

    final matched = items.where((item) {
      return item.title.contains('十三邀') ||
          item.actualAddress.contains('十三邀');
    }).toList(growable: false);

    for (final item in matched) {
      print(
        '[DebugItem] title=${item.title} | id=${item.id} | type=${item.itemType} | address=${item.actualAddress}',
      );
    }

    expect(items, isNotEmpty);
  });
}
