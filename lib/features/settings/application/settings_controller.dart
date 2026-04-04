import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
      SettingsController.new,
    );

final appSettingsProvider = Provider<AppSettings>((ref) {
  return ref.watch(settingsControllerProvider).valueOrNull ??
      SeedData.defaultSettings;
});

class SettingsController extends AsyncNotifier<AppSettings> {
  AppSettingsRepository get _repository => ref.read(appSettingsRepositoryProvider);

  @override
  FutureOr<AppSettings> build() async {
    return _repository.load();
  }

  Future<void> toggleMediaSource(String id, bool enabled) async {
    final current = state.valueOrNull ?? await _repository.load();
    final next = current.copyWith(
      mediaSources: [
        for (final source in current.mediaSources)
          source.id == id ? source.copyWith(enabled: enabled) : source,
      ],
    );
    await _persist(next);
  }

  Future<void> saveMediaSource(MediaSourceConfig config) async {
    final current = state.valueOrNull ?? await _repository.load();
    final exists = current.mediaSources.any((item) => item.id == config.id);
    final next = current.copyWith(
      mediaSources: exists
          ? [
              for (final source in current.mediaSources)
                source.id == config.id ? config : source,
            ]
          : [...current.mediaSources, config],
    );
    await _persist(next);
  }

  Future<void> toggleSearchProvider(String id, bool enabled) async {
    final current = state.valueOrNull ?? await _repository.load();
    final next = current.copyWith(
      searchProviders: [
        for (final provider in current.searchProviders)
          provider.id == id ? provider.copyWith(enabled: enabled) : provider,
      ],
    );
    await _persist(next);
  }

  Future<void> saveSearchProvider(SearchProviderConfig config) async {
    final current = state.valueOrNull ?? await _repository.load();
    final exists = current.searchProviders.any((item) => item.id == config.id);
    final next = current.copyWith(
      searchProviders: exists
          ? [
              for (final provider in current.searchProviders)
                provider.id == config.id ? config : provider,
            ]
          : [...current.searchProviders, config],
    );
    await _persist(next);
  }

  Future<void> saveDoubanAccount(DoubanAccountConfig config) async {
    final current = state.valueOrNull ?? await _repository.load();
    await _persist(current.copyWith(doubanAccount: config));
  }

  Future<void> toggleHomeModule(String id, bool enabled) async {
    final current = state.valueOrNull ?? await _repository.load();
    final next = current.copyWith(
      homeModules: [
        for (final module in current.homeModules)
          module.id == id ? module.copyWith(enabled: enabled) : module,
      ],
    );
    await _persist(next);
  }

  Future<void> reorderHomeModules(int oldIndex, int newIndex) async {
    final current = state.valueOrNull ?? await _repository.load();
    final modules = [...current.homeModules];
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final moved = modules.removeAt(oldIndex);
    modules.insert(newIndex, moved);
    await _persist(current.copyWith(homeModules: modules));
  }

  Future<void> _persist(AppSettings next) async {
    state = AsyncData(next);
    await _repository.save(next);
  }
}
