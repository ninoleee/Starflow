import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sembast/sembast.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/features/library/data/nas_media_index_models.dart';
import 'package:starflow/features/library/data/nas_media_index_store_impl_stub.dart'
    if (dart.library.html) 'package:starflow/features/library/data/nas_media_index_store_impl_web.dart'
    if (dart.library.io) 'package:starflow/features/library/data/nas_media_index_store_impl_io.dart'
    as impl;

final nasMediaIndexStoreProvider = Provider<NasMediaIndexStore>((ref) {
  return SembastNasMediaIndexStore(
      databaseOpener: impl.openNasMediaIndexDatabase);
});

abstract class NasMediaIndexStore {
  Future<List<NasMediaIndexRecord>> loadSourceRecords(String sourceId);

  Future<NasMediaIndexSourceState?> loadSourceState(String sourceId);

  Future<void> replaceSourceRecords({
    required String sourceId,
    required List<NasMediaIndexRecord> records,
    required NasMediaIndexSourceState state,
  });

  Future<void> upsertSourceRecords({
    required String sourceId,
    required List<NasMediaIndexRecord> records,
    required NasMediaIndexSourceState state,
    bool clearMissingRecords = false,
  });

  Future<LocalStorageCacheSummary> inspectSummary();

  Future<void> clearAll();

  Future<void> clearSource(String sourceId);
}

class SembastNasMediaIndexStore implements NasMediaIndexStore {
  SembastNasMediaIndexStore({
    required Future<Database> Function() databaseOpener,
  }) : _databaseOpener = databaseOpener;

  final Future<Database> Function() _databaseOpener;
  final StoreRef<String, Map<String, dynamic>> _recordStore =
      stringMapStoreFactory.store('nas_media_index_records');
  final StoreRef<String, Map<String, dynamic>> _sourceStore =
      stringMapStoreFactory.store('nas_media_index_sources');

  Future<Database>? _databaseFuture;

  Future<Database> _database() {
    return _databaseFuture ??= _databaseOpener();
  }

  @override
  Future<void> clearAll() async {
    final database = await _database();
    await database.transaction((transaction) async {
      await _recordStore.delete(transaction);
      await _sourceStore.delete(transaction);
    });
  }

  @override
  Future<void> clearSource(String sourceId) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return;
    }
    final database = await _database();
    await database.transaction((transaction) async {
      final snapshot = await _recordStore.find(
        transaction,
        finder: Finder(
          filter: Filter.equals('sourceId', normalizedSourceId),
        ),
      );
      for (final record in snapshot) {
        await _recordStore.record(record.key).delete(transaction);
      }
      await _sourceStore.record(normalizedSourceId).delete(transaction);
    });
  }

  @override
  Future<List<NasMediaIndexRecord>> loadSourceRecords(String sourceId) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return const [];
    }
    final database = await _database();
    final snapshot = await _recordStore.find(
      database,
      finder: Finder(
        filter: Filter.equals('sourceId', normalizedSourceId),
      ),
    );
    final records = snapshot
        .map((entry) => NasMediaIndexRecord.fromJson(entry.value))
        .toList(growable: false);
    records.sort(
      (left, right) => right.item.addedAt.compareTo(left.item.addedAt),
    );
    return records;
  }

  @override
  Future<NasMediaIndexSourceState?> loadSourceState(String sourceId) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return null;
    }
    final database = await _database();
    final raw = await _sourceStore.record(normalizedSourceId).get(database);
    if (raw == null) {
      return null;
    }
    return NasMediaIndexSourceState.fromJson(raw);
  }

  @override
  Future<void> replaceSourceRecords({
    required String sourceId,
    required List<NasMediaIndexRecord> records,
    required NasMediaIndexSourceState state,
  }) async {
    await upsertSourceRecords(
      sourceId: sourceId,
      records: records,
      state: state,
      clearMissingRecords: true,
    );
  }

  @override
  Future<void> upsertSourceRecords({
    required String sourceId,
    required List<NasMediaIndexRecord> records,
    required NasMediaIndexSourceState state,
    bool clearMissingRecords = false,
  }) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return;
    }
    final database = await _database();
    await database.transaction((transaction) async {
      if (clearMissingRecords) {
        final toDelete = await _recordStore.find(
          transaction,
          finder: Finder(
            filter: Filter.equals('sourceId', normalizedSourceId),
          ),
        );
        for (final record in toDelete) {
          await _recordStore.record(record.key).delete(transaction);
        }
      }
      for (final record in records) {
        await _recordStore.record(record.id).put(transaction, record.toJson());
      }
      await _sourceStore.record(normalizedSourceId).put(
            transaction,
            state.toJson(),
          );
    });
  }

  @override
  Future<LocalStorageCacheSummary> inspectSummary() async {
    final database = await _database();
    final records = await _recordStore.find(database);
    final states = await _sourceStore.find(database);
    final totalBytes = utf8
            .encode(jsonEncode(records.map((item) => item.value).toList()))
            .length +
        utf8
            .encode(jsonEncode(states.map((item) => item.value).toList()))
            .length;
    return LocalStorageCacheSummary(
      type: LocalStorageCacheType.nasMetadataIndex,
      entryCount: records.length,
      totalBytes: totalBytes,
    );
  }
}
