import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/logging/app_log_api.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/features/playback/application/active_playback_cleanup.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/metadata/application/metadata_prefetch_concurrency_limiter.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/home/application/home_metadata_auto_refresh.dart';
import 'package:starflow/features/home/application/home_feed_load_scheduler.dart';
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
  Future<void> _persistenceTail = Future<void>.value();

  AppSettingsRepository get _repository =>
      ref.read(appSettingsRepositoryProvider);

  @override
  FutureOr<AppSettings> build() async {
    return _repository.load();
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

  Future<void> savePlaybackSubtitlePreferences({
    required PlaybackSubtitlePreference subtitlePreference,
    required PlaybackDefaultSubtitle defaultSubtitle,
    required double subtitleScale,
    double? primarySubtitlePosition,
    double? secondarySubtitlePosition,
    double? secondarySubtitleScale,
    required List<OnlineSubtitleSource> onlineSubtitleSources,
    required String assrtToken,
    required bool opensubtitlesEnabled,
    required String opensubtitlesUsername,
    required String opensubtitlesPassword,
    required bool subdlEnabled,
    required String subdlApiKey,
    required List<String> subtitlePreferredLanguages,
    required int subtitleSearchMaxValidatedCandidates,
  }) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(
        playbackSubtitlePreference: subtitlePreference,
        playbackDefaultSubtitle: defaultSubtitle,
        playbackSubtitleScale: subtitleScale,
        playbackPrimarySubtitlePosition: primarySubtitlePosition,
        playbackSecondarySubtitlePosition: secondarySubtitlePosition,
        playbackSecondarySubtitleScale: secondarySubtitleScale,
        onlineSubtitleSources:
            onlineSubtitleSources.toSet().toList(growable: false),
        assrtToken: assrtToken.trim(),
        opensubtitlesEnabled: opensubtitlesEnabled,
        opensubtitlesUsername: opensubtitlesUsername.trim(),
        opensubtitlesPassword: opensubtitlesPassword,
        subdlEnabled: subdlEnabled,
        subdlApiKey: subdlApiKey.trim(),
        subtitlePreferredLanguages: subtitlePreferredLanguages
            .map((item) => item.trim().toLowerCase())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false),
        subtitleSearchMaxValidatedCandidates:
            clampSubtitleSearchMaxValidatedCandidates(
          subtitleSearchMaxValidatedCandidates,
        ),
      ),
    );
  }

  Future<void> savePlaybackSubtitleStylePreferences({
    required double subtitleScale,
    required double primarySubtitlePosition,
    required double secondarySubtitlePosition,
    required double secondarySubtitleScale,
  }) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(
        playbackSubtitleScale: subtitleScale,
        playbackPrimarySubtitlePosition: primarySubtitlePosition,
        playbackSecondarySubtitlePosition: secondarySubtitlePosition,
        playbackSecondarySubtitleScale: secondarySubtitleScale,
      ),
    );
  }

  Future<void> savePlaybackPreferences({
    required int openTimeoutSeconds,
    required double defaultSpeed,
    required bool backgroundPlaybackEnabled,
    required PlaybackEngine playbackEngine,
    required PlaybackDecodeMode playbackDecodeMode,
    required NativeAudioOutputMode nativeAudioOutputMode,
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
        playbackBackgroundPlaybackEnabled: backgroundPlaybackEnabled,
        playbackEngine: playbackEngine,
        playbackDecodeMode: playbackDecodeMode,
        nativeAudioOutputMode: nativeAudioOutputMode,
      ),
    );
  }

  Future<void> savePlaybackMpvPreferences({
    required bool doubleTapToSeekEnabled,
    required bool swipeToSeekEnabled,
    required bool longPressSpeedBoostEnabled,
    required bool stallAutoRecoveryEnabled,
    required bool aggressiveTuningEnabled,
  }) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(
        playbackMpvDoubleTapToSeekEnabled: doubleTapToSeekEnabled,
        playbackMpvSwipeToSeekEnabled: swipeToSeekEnabled,
        playbackMpvLongPressSpeedBoostEnabled: longPressSpeedBoostEnabled,
        playbackMpvStallAutoRecoveryEnabled: stallAutoRecoveryEnabled,
        performanceAggressivePlaybackTuningEnabled: aggressiveTuningEnabled,
      ),
    );
  }

  Future<void> savePlaybackRuntimePreferences({
    required bool backgroundPlaybackEnabled,
    required bool doubleTapToSeekEnabled,
    required bool swipeToSeekEnabled,
    required bool longPressSpeedBoostEnabled,
    required bool stallAutoRecoveryEnabled,
    required bool aggressiveTuningEnabled,
    required double subtitleScale,
    required double primarySubtitlePosition,
    required double secondarySubtitlePosition,
    required double secondarySubtitleScale,
  }) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(
        playbackBackgroundPlaybackEnabled: backgroundPlaybackEnabled,
        playbackMpvDoubleTapToSeekEnabled: doubleTapToSeekEnabled,
        playbackMpvSwipeToSeekEnabled: swipeToSeekEnabled,
        playbackMpvLongPressSpeedBoostEnabled: longPressSpeedBoostEnabled,
        playbackMpvStallAutoRecoveryEnabled: stallAutoRecoveryEnabled,
        performanceAggressivePlaybackTuningEnabled: aggressiveTuningEnabled,
        playbackSubtitleScale: subtitleScale,
        playbackPrimarySubtitlePosition: primarySubtitlePosition,
        playbackSecondarySubtitlePosition: secondarySubtitlePosition,
        playbackSecondarySubtitleScale: secondarySubtitleScale,
      ),
    );
  }

  Future<void> replaceAllSettings(AppSettings settings) async {
    await _persist(settings);
    await _applyLoggingSettings(settings);
  }

  Future<void> setLocalLoggingEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    final next = current.copyWith(localLoggingEnabled: enabled);
    await _persist(next);
    await _applyLoggingSettings(next);
    if (enabled) {
      appLogInfo('settings.logging', 'Local logging enabled');
    }
  }

  Future<void> setLocalLogMaxSizeMb(int maxSizeMb) async {
    final current = state.value ?? await _repository.load();
    final next = current.copyWith(localLogMaxSizeMb: maxSizeMb);
    await _persist(next);
    await _applyLoggingSettings(next);
    appLogInfo(
      'settings.logging',
      'Local log capacity updated',
      fields: <String, Object?>{'maxSizeMb': next.localLogMaxSizeMb},
    );
  }

  Future<void> setLocalLogRecordedLevels(Set<AppLogLevel> levels) async {
    final current = state.value ?? await _repository.load();
    final next = current.copyWith(
      localLogRecordedLevels: Set<AppLogLevel>.from(levels),
    );
    await _persist(next);
    await _applyLoggingSettings(next);
    appLogInfo(
      'settings.logging',
      'Recorded log levels updated',
      fields: <String, Object?>{
        'levels': levels.map((level) => level.name).toList(growable: false),
      },
    );
  }

  Future<void> setLocalLogVisibleLevels(Set<AppLogLevel> levels) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(
        localLogVisibleLevels: Set<AppLogLevel>.from(levels),
      ),
    );
  }

  Future<void> _applyLoggingSettings(AppSettings settings) {
    return appLogger.configure(
      enabled: settings.localLoggingEnabled,
      maxBytes: settings.localLogMaxSizeMb * 1024 * 1024,
      recordedLevels: settings.localLogRecordedLevels,
    );
  }

  Future<void> setHomeHeroDisplayMode(HomeHeroDisplayMode mode) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(homeHeroDisplayMode: mode));
  }

  Future<void> setHomeHeroEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    final heroModule = _resolveHeroModule(current).copyWith(enabled: enabled);
    await _persist(
      current.copyWith(
        homeModules: _replaceHomeHeroModule(current.homeModules, heroModule),
      ),
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

  Future<void> setHomeStartupAutoRefreshEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(homeStartupAutoRefreshEnabled: enabled));
  }

  Future<void> setHomeStartupAutoRefreshEmbyEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(homeStartupAutoRefreshEmbyEnabled: enabled),
    );
  }

  Future<void> setHomeNavigationSingleTapCleanupEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(homeNavigationSingleTapCleanupEnabled: enabled),
    );
  }

  Future<void> setSimplifiedVisualEffectsEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(
        translucentEffectsEnabled: !enabled,
        performanceReduceDecorationsEnabled: enabled,
      ),
    );
  }

  Future<void> setAutoHideNavigationBarEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(autoHideNavigationBarEnabled: enabled));
  }

  Future<void> setNavigationDestinationIds(Iterable<String> ids) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(
        navigationDestinationIds: normalizeNavigationDestinationIds(ids),
      ),
    );
  }

  Future<void> setReducedInterfaceMotionEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(
        performanceReduceMotionEnabled: enabled,
        performanceStaticNavigationEnabled: enabled,
      ),
    );
  }

  Future<void> setSimplifiedHomeHeroEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(
        performanceStaticHomeHeroEnabled: enabled,
        performanceLightweightHomeHeroEnabled: enabled,
      ),
    );
  }

  Future<void> setPerformanceLiveItemHeroOverlayEnabled(bool enabled) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(performanceLiveItemHeroOverlayEnabled: enabled),
    );
  }

  Future<void> setTaskMaxConcurrency(int maxConcurrency) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(
        taskMaxConcurrency: maxConcurrency,
      ),
    );
  }

  Future<void> setMetadataPrefetchInitialBatchSize(int batchSize) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(
        metadataPrefetchInitialBatchSize: batchSize,
      ),
    );
  }

  Future<void> setMetadataPrefetchBatchDelayMs(int delayMs) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(metadataPrefetchBatchDelayMs: delayMs),
    );
  }

  Future<void> setMetadataPrefetchForegroundResumeDelayMs(int delayMs) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(metadataPrefetchForegroundResumeDelayMs: delayMs),
    );
  }

  Future<void> setHomeFeedInitialBatchSize(int batchSize) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(homeFeedInitialBatchSize: batchSize),
    );
  }

  Future<void> setHomeFeedBatchDelayMs(int delayMs) async {
    final current = state.value ?? await _repository.load();
    await _persist(current.copyWith(homeFeedBatchDelayMs: delayMs));
  }

  Future<void> setPerformanceAggressivePlaybackTuningEnabled(
    bool enabled,
  ) async {
    final current = state.value ?? await _repository.load();
    await _persist(
      current.copyWith(performanceAggressivePlaybackTuningEnabled: enabled),
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
    if (id == HomeModuleConfig.heroModuleId) {
      await setHomeHeroEnabled(false);
      return;
    }
    final next = current.copyWith(
      homeModules: current.homeModules.where((item) => item.id != id).toList(),
    );
    await _persist(next);
  }

  Future<void> reorderHomeModules(int oldIndex, int newIndex) async {
    final current = state.value ?? await _repository.load();
    final heroModule = _resolveHeroModule(current);
    final modules = current.homeModules
        .where((module) => !_isHomeHeroModule(module))
        .toList();
    if (oldIndex < 0 || oldIndex >= modules.length) {
      return;
    }
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final moved = modules.removeAt(oldIndex);
    if (newIndex < 0) {
      newIndex = 0;
    }
    if (newIndex > modules.length) {
      newIndex = modules.length;
    }
    modules.insert(newIndex, moved);
    await _persist(current.copyWith(homeModules: [heroModule, ...modules]));
  }

  Future<void> _persist(AppSettings next) async {
    final normalized = next.copyWith(
      homeModules: _normalizeHomeModuleOrder(next.homeModules),
    );
    state = AsyncData(normalized);
    final saveFuture = _persistenceTail.then(
      (_) => _repository.save(normalized),
    );
    _persistenceTail = saveFuture.catchError(
      (Object error, StackTrace stackTrace) {
        appLogError(
          'settings.persistence',
          'Settings write failed',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
    await saveFuture;
    ref.read(metadataPrefetchConcurrencyLimiterProvider).updateLimits(
          maxConcurrency: normalized.taskMaxConcurrency,
          initialBatchSize: normalized.metadataPrefetchInitialBatchSize,
          backgroundBatchDelay: Duration(
            milliseconds: normalized.metadataPrefetchBatchDelayMs,
          ),
        );
    ref.read(homeFeedLoadSchedulerProvider).updateLimits(
          maxConcurrency: normalized.taskMaxConcurrency,
          initialBatchSize: normalized.homeFeedInitialBatchSize,
          backgroundBatchDelay: Duration(
            milliseconds: normalized.homeFeedBatchDelayMs,
          ),
        );
    ref.read(homeMetadataAutoRefreshRevisionProvider.notifier).state += 1;
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

bool _isHomeHeroModule(HomeModuleConfig module) {
  return module.type == HomeModuleType.hero ||
      module.id == HomeModuleConfig.heroModuleId;
}

List<HomeModuleConfig> _replaceHomeHeroModule(
  List<HomeModuleConfig> modules,
  HomeModuleConfig heroModule,
) {
  return [
    heroModule.copyWith(
      id: HomeModuleConfig.heroModuleId,
      type: HomeModuleType.hero,
    ),
    for (final module in modules)
      if (!_isHomeHeroModule(module)) module,
  ];
}

List<HomeModuleConfig> _normalizeHomeModuleOrder(
  List<HomeModuleConfig> modules,
) {
  HomeModuleConfig? heroModule;
  final sortableModules = <HomeModuleConfig>[];
  for (final module in modules) {
    if (_isHomeHeroModule(module)) {
      heroModule ??= module.copyWith(
        id: HomeModuleConfig.heroModuleId,
        type: HomeModuleType.hero,
      );
      continue;
    }
    sortableModules.add(module);
  }
  return [
    heroModule ?? HomeModuleConfig.hero(),
    ...sortableModules,
  ];
}
