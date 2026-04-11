import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';

final searchPreferencesRepositoryProvider =
    Provider<SearchPreferencesRepository>(
  (ref) => SearchPreferencesRepository(),
);

class SearchPreferencesRepository {
  SearchPreferencesRepository({
    AppPreferencesStore? preferences,
  }) : _preferences = preferences ?? AppPreferencesStore();

  static const recentQueriesPreferenceKey = 'search.recentQueries';
  static const selectedTargetIdsPreferenceKey = 'search.selectedTargetIds';
  static const favoriteResultsPreferenceKey = 'search.favoriteResults';
  static const _maxFavoriteResults = 200;

  final AppPreferencesStore _preferences;

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
    final raw = await _preferences.getString(favoriteResultsPreferenceKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <SearchResult>[];
    }
    try {
      final decoded = jsonDecode(raw);
      final entries = decoded as List<dynamic>? ?? const <dynamic>[];
      return entries
          .map(
            (item) => SearchResult.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .where((item) => item.title.trim().isNotEmpty)
          .take(_maxFavoriteResults)
          .toList(growable: false);
    } catch (_) {
      return const <SearchResult>[];
    }
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
    final normalized = values.take(_maxFavoriteResults).toList(growable: false);
    return _preferences.setString(
      favoriteResultsPreferenceKey,
      jsonEncode(
        normalized.map((item) => item.toJson()).toList(growable: false),
      ),
    );
  }

  Future<void> clear() async {
    await _preferences.remove(recentQueriesPreferenceKey);
    await _preferences.remove(selectedTargetIdsPreferenceKey);
    await _preferences.remove(favoriteResultsPreferenceKey);
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
