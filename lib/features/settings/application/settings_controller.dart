import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/playback_trace.dart';
import 'package:starflow/core/utils/subtitle_search_trace.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/home/application/home_metadata_auto_refresh.dart';
import 'package:starflow/features/playback/application/active_playback_cleanup.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

final appSettingsProvider = Provider<AppSettings>((ref) {
  return ref.watch(settingsControllerProvider).value ??
      SeedData.defaultSettings;
});

bool? _resolveTelevisionState(AsyncValue<bool> state) {
  return state is AsyncData<bool> ? state.value : null;
}

final effectivePerformanceLiveItemHeroOverlayEnabledProvider = Provider<bool>((
  ref,
) {
  final settings = ref.watch(appSettingsProvider);
  final isTelevision = _resolveTelevisionState(ref.watch(isTelevisionProvider));
  return settings.effectivePerformanceLiveItemHeroOverlayEnabled(
    isTelevision: isTelevision,
  );
});

final effectivePlaybackBackgroundEnabledProvider = Provider<bool>((ref) {
  final settings = ref.watch(appSettingsProvider);
  final isTelevision = _resolveTelevisionState(ref.watch(isTelevisionProvider));
  return settings.effectiveBackgroundPlaybackEnabled(
    isTelevision: isTelevision,
  );
});

class SettingsController extends AsyncNotifier<AppSettings> {
  AppSettingsRepository get _repository =>
      ref.read(appSettingsRepositoryProvider);

  @override
  FutureOr<AppSettings> build() async {
    final settings = await _repository.load();
    _syncRuntimeTraceSettings(settings);
    return settings;
  }

  Future<void> toggleMediaSource(String id, bool enabled) async {
    final current = state.value ?? await _repository.load();
    final next = current.copyWith(
      mediaSources: [
        for (final source in current.mediaSources)
          source.id == id ? source.copyWith(enabled: enabled) : source,
      ],
    );
    await _persist(next);
  }

  Future<void> saveMediaSource(MediaSourceConfig config) async {
    final current = state.value ?? await _repository.load();
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

  Future<void> removeMediaSource(String id) async {
    final current = state.value ?? await _repository.load();
    final next = current.copyWith(
      mediaSources:
          current.mediaSources.where((item) => item.id != id).toList(),
    );
    await _persist(next);
  }

  Future<MediaSourceConfig> authenticateEmby({
    required MediaSourceConfig source,
    required String password,
  }) async {
    final session = await ref
        .read(embyApiClientProvider)
        .authenticate(source: source, password: password);

    final authenticatedSource = source.copyWith(
      endpoint: session.baseUri.toString(),
      username: session.username,
      accessToken: session.accessToken,
      userId: session.userId,
      serverId: session.serverId,
      deviceId: session.deviceId,
    );
    await saveMediaSource(authenticatedSource);
    return authenticatedSource;
  }

  Future<void> toggleSearchProvider(String id, bool enabled) async {
    final current = state.value ?? await _repository.load();
    final next = current.copyWith(
      searchProviders: [
        for (final provider in current.searchProviders)
          provider.id == id ? provider.copyWith(enabled: enabled) : provider,
      ],
    );
    await _persist(next);
  }

  Future<void> saveSearchProvider(SearchProviderConfig config) async {
    final current = state.value ?? await _repository.load();
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

  Future<void> removeSearchProvider(String id) async {
    final current = state.value ?? await _repository.load();
    final next = current.copyWith(
      searchProviders:
          current.searchProviders.where((item) => item.id != id).toList(),
    );
    await _persist(next);
  }

  Future<void> saveDoubanAccount(DoubanAccountConfig config) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(doubanAccount: config));
  }

  Future<void> saveNetworkStorage(NetworkStorageConfig config) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(networkStorage: config));
  }

  Future<void> setTmdbMetadataMatchEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(tmdbMetadataMatchEnabled: enabled));
  }

  Future<void> setWmdbMetadataMatchEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(wmdbMetadataMatchEnabled: enabled));
  }

  Future<void> setMetadataMatchPriority(MetadataMatchProvider provider) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(metadataMatchPriority: provider));
  }

  Future<void> setImdbRatingMatchEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(imdbRatingMatchEnabled: enabled));
  }

  Future<void> setDetailAutoLibraryMatchEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(detailAutoLibraryMatchEnabled: enabled));
  }

  Future<void> setLibraryMatchSourceIds(List<String> sourceIds) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(
        libraryMatchSourceIds: sourceIds
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false),
      ),
    );
  }

  Future<void> setSearchSourceIds(List<String> sourceIds) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(
        searchSourceIds: sourceIds
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false),
      ),
    );
  }

  Future<void> setTmdbReadAccessToken(String token) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(tmdbReadAccessToken: token.trim()));
  }

  Future<void> setPlaybackOpenTimeoutSeconds(int seconds) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(playbackOpenTimeoutSeconds: seconds.clamp(1, 600)),
    );
  }

  Future<void> setPlaybackEngine(PlaybackEngine playbackEngine) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(playbackEngine: playbackEngine));
  }

  Future<void> setPlaybackSubtitleScale(
    PlaybackSubtitleScale subtitleScale,
  ) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(playbackSubtitleScale: subtitleScale));
  }

  Future<void> savePlaybackPreferences({
    required int openTimeoutSeconds,
    required double defaultSpeed,
    required PlaybackSubtitlePreference subtitlePreference,
    required PlaybackSubtitleScale subtitleScale,
    required List<OnlineSubtitleSource> onlineSubtitleSources,
    required bool backgroundPlaybackEnabled,
    required PlaybackEngine playbackEngine,
    required PlaybackDecodeMode playbackDecodeMode,
    bool? playbackMpvDoubleTapToSeekEnabled,
    bool? playbackMpvSwipeToSeekEnabled,
    bool? playbackMpvLongPressSpeedBoostEnabled,
    bool? playbackMpvStallAutoRecoveryEnabled,
  }) async {
    final current = state.value ?? await _repository.load();
    if (current.playbackBackgroundPlaybackEnabled &&
        !backgroundPlaybackEnabled) {
      await ActivePlaybackCleanupCoordinator.cleanupAll(
        reason: 'background-playback-disabled',
      );
    }
    await _persist(
      current.copyWith(
        playbackOpenTimeoutSeconds: openTimeoutSeconds.clamp(1, 600),
        playbackDefaultSpeed: defaultSpeed.clamp(0.75, 2.0),
        playbackSubtitlePreference: subtitlePreference,
        playbackSubtitleScale: subtitleScale,
        onlineSubtitleSources:
            onlineSubtitleSources.toSet().toList(growable: false),
        playbackBackgroundPlaybackEnabled: backgroundPlaybackEnabled,
        playbackEngine: playbackEngine,
        playbackDecodeMode: playbackDecodeMode,
        playbackMpvQualityPreset: PlaybackMpvQualityPreset.performanceFirst,
        playbackMpvDoubleTapToSeekEnabled: playbackMpvDoubleTapToSeekEnabled ??
            current.playbackMpvDoubleTapToSeekEnabled,
        playbackMpvSwipeToSeekEnabled: playbackMpvSwipeToSeekEnabled ??
            current.playbackMpvSwipeToSeekEnabled,
        playbackMpvLongPressSpeedBoostEnabled:
            playbackMpvLongPressSpeedBoostEnabled ??
                current.playbackMpvLongPressSpeedBoostEnabled,
        playbackMpvStallAutoRecoveryEnabled:
            playbackMpvStallAutoRecoveryEnabled ??
                current.playbackMpvStallAutoRecoveryEnabled,
        playbackTraceEnabled: false,
        subtitleSearchTraceEnabled: false,
      ),
    );
  }

  Future<void> replaceAllSettings(AppSettings settings) async {
    await _persist(settings);
  }

  Future<void> setHomeHeroDisplayMode(HomeHeroDisplayMode mode) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(homeHeroDisplayMode: mode));
  }

  Future<void> setHomeHeroEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await saveHomeModule(
      _resolveHeroModule(current).copyWith(enabled: enabled),
    );
  }

  Future<void> setHomeHeroSourceModuleId(String moduleId) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(homeHeroSourceModuleId: moduleId.trim()));
  }

  Future<void> setHomeHeroBackgroundEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(homeHeroBackgroundEnabled: enabled));
  }

  Future<void> setHomeHeroLogoTitleEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(homeHeroLogoTitleEnabled: enabled));
  }

  Future<void> setTranslucentEffectsEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(translucentEffectsEnabled: enabled));
  }

  Future<void> setAutoHideNavigationBarEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(autoHideNavigationBarEnabled: enabled));
  }

  Future<void> setHighPerformanceModeEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    final next = enabled
        ? current.applyHighPerformancePreset()
        : current.clearHighPerformancePresetMarker();
    await _persist(next);
  }

  Future<void> setPerformanceReduceDecorationsEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(performanceReduceDecorationsEnabled: enabled),
    );
  }

  Future<void> setPerformanceReduceMotionEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(performanceReduceMotionEnabled: enabled));
  }

  Future<void> setPerformanceStaticNavigationEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(performanceStaticNavigationEnabled: enabled),
    );
  }

  Future<void> setPerformanceLightweightTvFocusEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(performanceLightweightTvFocusEnabled: enabled),
    );
  }

  Future<void> setPerformanceStaticHomeHeroEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(performanceStaticHomeHeroEnabled: enabled));
  }

  Future<void> setPerformanceLightweightHomeHeroEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(performanceLightweightHomeHeroEnabled: enabled),
    );
  }

  Future<void> setPerformanceLiveItemHeroOverlayEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(performanceLiveItemHeroOverlayEnabled: enabled),
    );
  }

  Future<void> setPerformanceSlimDetailHeroEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(performanceSlimDetailHeroEnabled: enabled));
  }

  Future<void> setPerformanceLeanPlaybackUiEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(performanceLeanPlaybackUiEnabled: enabled));
  }

  Future<void> setPerformanceAggressivePlaybackTuningEnabled(
    bool enabled,
  ) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(performanceAggressivePlaybackTuningEnabled: enabled),
    );
  }

  Future<void> setPerformanceAutoDowngradeHeavyPlaybackEnabled(
    bool enabled,
  ) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(
        performanceAutoDowngradeHeavyPlaybackEnabled: enabled,
      ),
    );
  }

  Future<void> toggleHomeModule(String id, bool enabled) async {
    final current = state.value ?? await _repository.load();
    final next = current.copyWith(
      homeModules: [
        for (final module in current.homeModules)
          module.id == id ? module.copyWith(enabled: enabled) : module,
      ],
    );
    await _persist(next);
  }

  Future<void> saveHomeModule(HomeModuleConfig config) async {
    final current = state.value ?? await _repository.load();
    final exists = current.homeModules.any((item) => item.id == config.id);
    final next = current.copyWith(
      homeModules: exists
          ? [
              for (final module in current.homeModules)
                module.id == config.id ? config : module,
            ]
          : [...current.homeModules, config],
    );
    await _persist(next);
  }

  Future<void> removeHomeModule(String id) async {
    final current = state.value ?? await _repository.load();
    final next = current.copyWith(
      homeModules: current.homeModules.where((item) => item.id != id).toList(),
    );
    await _persist(next);
  }

  Future<void> reorderHomeModules(int oldIndex, int newIndex) async {
    final current = state.value ?? await _repository.load();
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
    _syncRuntimeTraceSettings(next);
    await _repository.save(next);
    ref.read(homeMetadataAutoRefreshRevisionProvider.notifier).state += 1;
  }

  void _syncRuntimeTraceSettings(AppSettings settings) {
    setPlaybackTraceEnabled(false);
    setSubtitleSearchTraceEnabled(false);
  }

  HomeModuleConfig _resolveHeroModule(AppSettings settings) {
    for (final module in settings.homeModules) {
      if (module.type == HomeModuleType.hero ||
          module.id == HomeModuleConfig.heroModuleId) {
        return module.copyWith(
          id: HomeModuleConfig.heroModuleId,
          type: HomeModuleType.hero,
        );
      }
    }
    return HomeModuleConfig.hero();
  }
}
