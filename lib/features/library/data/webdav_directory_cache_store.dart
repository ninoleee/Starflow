import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sembast/sembast.dart';
import 'package:starflow/features/library/data/nas_media_index_store_impl_stub.dart'
    if (dart.library.html) 'package:starflow/features/library/data/nas_media_index_store_impl_web.dart'
    if (dart.library.io) 'package:starflow/features/library/data/nas_media_index_store_impl_io.dart'
    as impl;

final webDavDirectoryCacheStoreProvider =
    Provider<WebDavDirectoryCacheStore>((ref) {
  return WebDavDirectoryCacheStore(
      databaseOpener: impl.openNasMediaIndexDatabase);
});

class WebDavDirectoryCacheStore {
  WebDavDirectoryCacheStore({
    required Future<Database> Function() databaseOpener,
  }) : _databaseOpener = databaseOpener;

  final Future<Database> Function() _databaseOpener;
  final StoreRef<String, Map<String, dynamic>> _store =
      stringMapStoreFactory.store('webdav_directory_subtrees');
  Future<Database>? _databaseFuture;

  Future<Database> _database() => _databaseFuture ??= _databaseOpener();

  Future<Map<String, dynamic>?> load(String key) async {
    final database = await _database();
    return _store.record(key).get(database);
  }

  Future<void> save(String key, Map<String, dynamic> value) async {
    final database = await _database();
    await _store.record(key).put(database, value);
  }

  Future<void> removeSource(String sourceId) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return;
    }
    final database = await _database();
    await _store.delete(
      database,
      finder: Finder(filter: Filter.equals('sourceId', normalizedSourceId)),
    );
  }
}
