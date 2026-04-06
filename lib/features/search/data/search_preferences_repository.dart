import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/storage/local_storage_models.dart';

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

  Future<void> clear() async {
    await _preferences.remove(recentQueriesPreferenceKey);
    await _preferences.remove(selectedTargetIdsPreferenceKey);
  }

  Future<LocalStorageCacheSummary> inspectSummary() async {
    final recentQueries =
        await _preferences.getStringList(recentQueriesPreferenceKey) ??
            const <String>[];
    final selectedTargetIds =
        await _preferences.getStringList(selectedTargetIdsPreferenceKey) ??
            const <String>[];
    final totalBytes = utf8.encode(jsonEncode(recentQueries)).length +
        utf8.encode(jsonEncode(selectedTargetIds)).length;
    return LocalStorageCacheSummary(
      type: LocalStorageCacheType.televisionSearchPreferences,
      entryCount: recentQueries.length + selectedTargetIds.length,
      totalBytes: totalBytes,
    );
  }
}
