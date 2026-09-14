import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/search/domain/favorite_sync_document.dart';

final searchPreferencesRepositoryProvider =
    Provider<SearchPreferencesRepository>(
  (ref) {
    final repository = SearchPreferencesRepository();
    ref.onDispose(repository.dispose);
    return repository;
  },
);

class SearchPreferencesRepository {
  SearchPreferencesRepository({
    PreferencesStore? preferences,
  }) : _preferences = preferences ?? AppPreferencesStore();

  static const recentQueriesPreferenceKey = 'search.recentQueries';
  static const selectedTargetIdsPreferenceKey = 'search.selectedTargetIds';
  static const favoriteResultsPreferenceKey = 'search.favoriteResults';
  static const favoriteSyncDeviceIdPreferenceKey =
      'search.favoriteSyncDeviceId';

  final PreferencesStore _preferences;
  Future<void> _favoriteWrite = Future<void>.value();
  final _favoriteChanges = StreamController<void>.broadcast();
  Stream<void> get favoriteChanges => _favoriteChanges.stream;
  final _favoriteMembershipChanges = StreamController<void>.broadcast();
  Stream<void> get favoriteMembershipChanges =>
      _favoriteMembershipChanges.stream;

  void dispose() {
    _favoriteChanges.close();
    _favoriteMembershipChanges.close();
  }

  Future<List<String>> loadRecentQueries() async {
    return (await _preferences.getStringList(recentQueriesPreferenceKey) ??
            const <String>[])
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<String>> loadSelectedTargetIds() async {
    return (await _preferences.getStringList(selectedTargetIdsPreferenceKey) ??
            const <String>[])
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<SearchResult>> loadFavoriteResults() async {
    try {
      return (await loadFavoriteSyncDocument()).favorites;
    } catch (_) {
      // Browsing remains available; sync and all mutations use the strict reader.
      return const [];
    }
  }

  Future<FavoriteSyncDocument> loadFavoriteSyncDocument() async {
    final raw = await _preferences.getString(favoriteResultsPreferenceKey);
    if (raw == null || raw.trim().isEmpty) {
      return FavoriteSyncDocument();
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Invalid favorite sync document');
    }
    return FavoriteSyncDocument.decode(raw);
  }

  Future<String> loadFavoriteSyncDeviceId() async {
    late String deviceId;
    await _queueFavoriteWrite(() async {
      final saved =
          await _preferences.getString(favoriteSyncDeviceIdPreferenceKey);
      if (saved != null &&
          RegExp(r'^[a-f0-9]{32}$').stringMatch(saved) == saved) {
        deviceId = saved;
        return;
      }
      final random = Random.secure();
      deviceId = List.generate(
              16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join();
      // Installation identity is local-only, never part of exported settings.
      await _preferences.setString(favoriteSyncDeviceIdPreferenceKey, deviceId);
    });
    return deviceId;
  }

  Future<void> saveRecentQueries(List<String> values) {
    return _preferences.setStringList(
      recentQueriesPreferenceKey,
      values.map((item) => item.trim()).where((item) => item.isNotEmpty).toList(
            growable: false,
          ),
    );
  }

  Future<void> saveSelectedTargetIds(List<String> values) {
    return _preferences.setStringList(
      selectedTargetIdsPreferenceKey,
      values.map((item) => item.trim()).where((item) => item.isNotEmpty).toList(
            growable: false,
          ),
    );
  }

  Future<void> saveFavoriteResults(List<SearchResult> values) {
    return _queueFavoriteWrite(() => _writeFavoriteResults(values));
  }

  Future<void> setFavorite(String key, SearchResult? result) {
    return _queueFavoriteWrite(() async {
      final current = await loadFavoriteSyncDocument();
      final next = current.setFavorite(key, result);
      if (next.encode() == current.encode()) return;
      await _storeDocument(next,
          membershipChanged: _membershipChanged(current, next));
    });
  }

  Future<void> mergeFavoriteSyncDocument(FavoriteSyncDocument remote,
      {bool Function()? shouldApply}) {
    return _queueFavoriteWrite(() async {
      final current = await loadFavoriteSyncDocument();
      if (shouldApply != null && !shouldApply()) return;
      final merged = current.merge(remote).withLocalPresentation(current);
      if (merged.encode() != current.encode()) await _storeDocument(merged);
    });
  }

  Future<void> updateFavoritePoster(SearchResult enriched) {
    return _queueFavoriteWrite(() async {
      if (enriched.posterUrl.trim().isEmpty) {
        return;
      }
      final latest = await loadFavoriteResults();
      final key = searchResultFavoriteKey(enriched);
      final index = latest.indexWhere(
        (item) => searchResultFavoriteKey(item) == key,
      );
      if (index < 0 || latest[index].posterUrl.trim().isNotEmpty) {
        return;
      }
      latest[index] = latest[index].copyWith(
        posterUrl: enriched.posterUrl,
        posterHeaders: enriched.posterHeaders,
      );
      await _writeFavoriteResults(latest);
    });
  }

  Future<void> _queueFavoriteWrite(Future<void> Function() write) {
    final next = _favoriteWrite.then((_) => write());
    _favoriteWrite =
        next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> _writeFavoriteResults(List<SearchResult> values) async {
    if (values.length > maxFavoriteResults) {
      throw StateError('收藏不能超过 200 条');
    }
    final current = await loadFavoriteSyncDocument();
    var document = current;
    final keys = values.map(searchResultFavoriteKey).toSet();
    for (final entry in document.entries.values.toList()) {
      if (!keys.contains(entry.key)) {
        document = document.setFavorite(entry.key, null);
      }
    }
    for (final result in values.reversed) {
      document = document.setFavorite(searchResultFavoriteKey(result), result);
    }
    if (document.encode() == current.encode()) return;
    await _storeDocument(document,
        membershipChanged: _membershipChanged(current, document));
  }

  bool _membershipChanged(
      FavoriteSyncDocument before, FavoriteSyncDocument after) {
    final previousKeys = before.favorites.map(searchResultFavoriteKey).toSet();
    final nextKeys = after.favorites.map(searchResultFavoriteKey).toSet();
    return previousKeys.length != nextKeys.length ||
        !previousKeys.containsAll(nextKeys);
  }

  Future<void> _storeDocument(FavoriteSyncDocument document,
      {bool membershipChanged = false}) async {
    // One preference write commits both the visible list and its deletion history.
    await _preferences.setString(
        favoriteResultsPreferenceKey, document.encode());
    if (!_favoriteChanges.isClosed) _favoriteChanges.add(null);
    if (membershipChanged && !_favoriteMembershipChanges.isClosed) {
      _favoriteMembershipChanges.add(null);
    }
  }

  Future<void> clear() async {
    await _preferences.remove(recentQueriesPreferenceKey);
    await _preferences.remove(selectedTargetIdsPreferenceKey);
    await _queueFavoriteWrite(
      () => _writeFavoriteResults([]),
    );
  }

  Future<LocalStorageCacheSummary> inspectSummary() async {
    final recentQueries =
        await _preferences.getStringList(recentQueriesPreferenceKey) ??
            const <String>[];
    final selectedTargetIds =
        await _preferences.getStringList(selectedTargetIdsPreferenceKey) ??
            const <String>[];
    final favoriteResults =
        await _preferences.getString(favoriteResultsPreferenceKey) ?? '[]';
    final favoriteCount = (await loadFavoriteResults()).length;
    final totalBytes = utf8.encode(jsonEncode(recentQueries)).length +
        utf8.encode(jsonEncode(selectedTargetIds)).length +
        utf8.encode(favoriteResults).length;
    return LocalStorageCacheSummary(
      type: LocalStorageCacheType.televisionSearchPreferences,
      entryCount:
          recentQueries.length + selectedTargetIds.length + favoriteCount,
      totalBytes: totalBytes,
    );
  }
}
