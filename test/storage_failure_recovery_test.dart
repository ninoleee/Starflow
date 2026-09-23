import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/data/native_playback_memory_preferences.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const settingsKey = 'starflow.settings.v3';
  const cookieKey = 'starflow.local-credentials.cloud115-cookie.v1';
  const manifestKey = 'starflow.local_storage.emby_library_cache.manifest.v2';

  test('credential read failure preserves valid settings and credential',
      () async {
    final store = _FailingStore();
    final repository = LocalAppSettingsRepository(preferences: store);
    await repository.save(SeedData.defaultSettings.copyWith(
      networkStorage: const NetworkStorageConfig(cloud115Cookie: 'synthetic'),
    ));
    final before = Map<String, Object>.from(store.values);
    store.failRead = cookieKey;
    await expectLater(repository.load(), throwsStateError);
    expect(store.values, before);
    expect(
        (await repository.load()).networkStorage.cloud115Cookie, 'synthetic');
  });

  test('reconciliation save failure does not replace settings with defaults',
      () async {
    final store = _FailingStore();
    final repository = LocalAppSettingsRepository(preferences: store);
    await repository.save(SeedData.defaultSettings.copyWith(
      mediaSources: const [],
      libraryMatchSourceIds: const ['deleted'],
      networkStorage: const NetworkStorageConfig(cloud115Cookie: 'synthetic'),
    ));
    final before = Map<String, Object>.from(store.values);
    store.failWrite = settingsKey;
    await expectLater(repository.load(), throwsStateError);
    expect(store.values, before);
  });

  test('malformed settings remain available for recovery without losing cookie',
      () async {
    final store = _FailingStore()
      ..values[settingsKey] = '{invalid'
      ..values[cookieKey] = 'synthetic';
    await LocalAppSettingsRepository(preferences: store).load();
    expect(store.values[settingsKey], '{invalid');
    expect(store.values[cookieKey], 'synthetic');
  });

  test('failed final manifest commit leaves shards discoverable by clear',
      () async {
    final store = _FailingStore()..failWrite = manifestKey;
    final repository = LocalStorageCacheRepository(preferences: store);
    await expectLater(
        repository.saveEmbyLibrarySnapshot(
          sourceId: 'test',
          refreshedAt: DateTime.utc(2026, 9, 20),
          collections: const [],
          fallbackItems: const [],
          itemsBySection: const {},
        ),
        throwsStateError);
    expect(store.values.keys.any((k) => k.contains('.shard.v2.')), isTrue);
    final reloaded = LocalStorageCacheRepository(preferences: store);
    await reloaded.clearAllEmbyLibrarySnapshots();
    expect(store.values.keys.any((k) => k.contains('emby_library_cache')),
        isFalse);
  });

  test('corrupt manifest can still clear recorded shards by prefix', () async {
    SharedPreferences.setMockInitialValues({
      manifestKey: '{invalid',
      'starflow.local_storage.emby_library_cache.shard.v2.b2xk.fallback': '[]',
      'unrelated': 'keep',
    });
    final preferences = await SharedPreferences.getInstance();
    await LocalStorageCacheRepository(sharedPreferences: preferences)
        .clearAllEmbyLibrarySnapshots();
    expect(preferences.getKeys(), {'unrelated'});
  });

  test('native snapshot conflict retries against current data, not stale cache',
      () async {
    const channel = MethodChannel('starflow/test-memory');
    String? raw;
    var conflict = true;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'readPlaybackMemory') return raw;
      final args = Map<String, dynamic>.from(call.arguments as Map);
      if (conflict) {
        conflict = false;
        raw = jsonEncode({
          'items': {},
          'series': {},
          'skipPreferences': {
            'native': {
              'seriesKey': 'native',
              'seriesTitle': 'Native',
              'enabled': true,
              'introDurationMs': 10000,
              'outroDurationMs': 0,
              'updatedAt': '2026-09-20T00:00:00.000Z'
            },
          }
        });
        return false;
      }
      if (args['expected'] != raw) return false;
      raw = args['value'] as String?;
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final repository = PlaybackMemoryRepository(
      preferences: NativePlaybackMemoryPreferences(channel: channel),
    );
    await repository.saveProgress(
        target: const PlaybackTarget(
          title: 'Test',
          sourceId: 'source',
          sourceName: 'Source',
          sourceKind: MediaSourceKind.nas,
          itemId: 'movie',
          streamUrl: 'https://example.test/v',
        ),
        position: const Duration(seconds: 20),
        duration: const Duration(seconds: 100));
    final saved = jsonDecode(raw!) as Map;
    expect((saved['items'] as Map).length, 1);
    expect(saved['skipPreferences'], contains('native'));
    await repository.clearAll();
    expect(raw, isNull);
  });
}

class _FailingStore implements PreferencesStore {
  final values = <String, Object>{};
  String? failRead;
  String? failWrite;
  @override
  Future<String?> getString(String key) async {
    if (key == failRead) {
      failRead = null;
      throw StateError('synthetic read');
    }
    return values[key] as String?;
  }

  @override
  Future<List<String>?> getStringList(String key) async =>
      values[key] as List<String>?;
  @override
  Future<void> setString(String key, String value) async {
    if (key == failWrite) {
      failWrite = null;
      throw StateError('synthetic write');
    }
    values[key] = value;
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}
