import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final settingsMediaSourcesProvider =
    Provider<List<MediaSourceConfig>>((ref) => ref.watch(
          appSettingsProvider.select((settings) => settings.mediaSources),
        ));

final settingsSearchProvidersProvider =
    Provider<List<SearchProviderConfig>>((ref) => ref.watch(
          appSettingsProvider.select((settings) => settings.searchProviders),
        ));

final settingsSearchSourceIdsProvider =
    Provider<List<String>>((ref) => ref.watch(
          appSettingsProvider.select((settings) => settings.searchSourceIds),
        ));

final settingsLibraryMatchSourceIdsProvider =
    Provider<List<String>>((ref) => ref.watch(
          appSettingsProvider
              .select((settings) => settings.libraryMatchSourceIds),
        ));

final settingsNetworkStorageProvider =
    Provider<NetworkStorageConfig>((ref) => ref.watch(
          appSettingsProvider.select((settings) => settings.networkStorage),
        ));

final settingsDetailAutoLibraryMatchEnabledProvider =
    Provider<bool>((ref) => ref.watch(
          appSettingsProvider
              .select((settings) => settings.detailAutoLibraryMatchEnabled),
        ));

final settingsHeroSliceProvider = Provider<SettingsHeroSlice>(
  (ref) => ref.watch(
    appSettingsProvider.select(
      (settings) => SettingsHeroSlice(
        sourceModuleId: settings.homeHeroSourceModuleId,
        displayMode: settings.homeHeroDisplayMode,
        style: settings.homeHeroStyle,
        logoTitleEnabled: settings.homeHeroLogoTitleEnabled,
        backgroundEnabled: settings.homeHeroBackgroundEnabled,
        translucentEffectsEnabled: settings.translucentEffectsEnabled,
        performanceStaticHomeHeroEnabled:
            settings.performanceStaticHomeHeroEnabled,
        performanceLightweightHomeHeroEnabled:
            settings.performanceLightweightHomeHeroEnabled,
      ),
    ),
  ),
);

final settingsPlaybackSliceProvider = Provider<SettingsPlaybackSlice>(
  (ref) {
    final effectiveBackgroundPlaybackEnabled = ref.watch(
      effectivePlaybackBackgroundEnabledProvider,
    );
    return ref.watch(
      appSettingsProvider.select(
        (settings) => SettingsPlaybackSlice(
          playbackEngine: settings.playbackEngine,
          playbackDecodeMode: settings.playbackDecodeMode,
          nativeAudioOutputMode: settings.nativeAudioOutputMode,
          playbackMpvQualityPreset: settings.playbackMpvQualityPreset,
          playbackMpvDoubleTapToSeekEnabled:
              settings.playbackMpvDoubleTapToSeekEnabled,
          playbackMpvSwipeToSeekEnabled: settings.playbackMpvSwipeToSeekEnabled,
          playbackMpvLongPressSpeedBoostEnabled:
              settings.playbackMpvLongPressSpeedBoostEnabled,
          playbackMpvStallAutoRecoveryEnabled:
              settings.playbackMpvStallAutoRecoveryEnabled,
          playbackOpenTimeoutSeconds: settings.playbackOpenTimeoutSeconds,
          playbackDefaultSpeed: settings.playbackDefaultSpeed,
          playbackSubtitlePreference: settings.playbackSubtitlePreference,
          playbackDefaultSubtitle: settings.playbackDefaultSubtitle,
          playbackDualSubtitlePrimaryLanguage:
              settings.playbackDualSubtitlePrimaryLanguage,
          playbackDualSubtitleSecondaryLanguage:
              settings.playbackDualSubtitleSecondaryLanguage,
          playbackSubtitleScale: settings.playbackSubtitleScale,
          playbackPrimarySubtitlePosition:
              settings.playbackPrimarySubtitlePosition,
          playbackSecondarySubtitlePosition:
              settings.playbackSecondarySubtitlePosition,
          playbackSecondarySubtitleScale:
              settings.playbackSecondarySubtitleScale,
          onlineSubtitleSources: settings.onlineSubtitleSources,
          assrtToken: settings.assrtToken,
          opensubtitlesEnabled: settings.opensubtitlesEnabled,
          opensubtitlesUsername: settings.opensubtitlesUsername,
          opensubtitlesPassword: settings.opensubtitlesPassword,
          subdlEnabled: settings.subdlEnabled,
          subdlApiKey: settings.subdlApiKey,
          subtitlePreferredLanguages: settings.subtitlePreferredLanguages,
          subtitleSearchMaxValidatedCandidates:
              settings.subtitleSearchMaxValidatedCandidates,
          configuredBackgroundPlaybackEnabled:
              settings.playbackBackgroundPlaybackEnabled,
          effectiveBackgroundPlaybackEnabled:
              effectiveBackgroundPlaybackEnabled,
        ),
      ),
    );
  },
);

final settingsPerformanceSliceProvider = Provider<SettingsPerformanceSlice>(
  (ref) {
    final effectiveLiveItemHeroOverlayEnabled = ref.watch(
      effectivePerformanceLiveItemHeroOverlayEnabledProvider,
    );
    return ref.watch(
      appSettingsProvider.select(
        (settings) => SettingsPerformanceSlice(
          translucentEffectsEnabled: settings.translucentEffectsEnabled,
          autoHideNavigationBarEnabled: settings.autoHideNavigationBarEnabled,
          homeHeroBackgroundEnabled: settings.homeHeroBackgroundEnabled,
          reduceDecorationsEnabled:
              settings.performanceReduceDecorationsEnabled,
          reduceMotionEnabled: settings.performanceReduceMotionEnabled,
          staticNavigationEnabled: settings.performanceStaticNavigationEnabled,
          staticHomeHeroEnabled: settings.performanceStaticHomeHeroEnabled,
          lightweightHomeHeroEnabled:
              settings.performanceLightweightHomeHeroEnabled,
          configuredLiveItemHeroOverlayEnabled:
              settings.performanceLiveItemHeroOverlayEnabled,
          effectiveLiveItemHeroOverlayEnabled:
              effectiveLiveItemHeroOverlayEnabled,
          aggressivePlaybackTuningEnabled:
              settings.performanceAggressivePlaybackTuningEnabled,
          taskMaxConcurrency: settings.taskMaxConcurrency,
          metadataPrefetchInitialBatchSize:
              settings.metadataPrefetchInitialBatchSize,
          metadataPrefetchBatchDelayMs: settings.metadataPrefetchBatchDelayMs,
          metadataPrefetchForegroundResumeDelayMs:
              settings.metadataPrefetchForegroundResumeDelayMs,
          homeFeedInitialBatchSize: settings.homeFeedInitialBatchSize,
          homeFeedBatchDelayMs: settings.homeFeedBatchDelayMs,
        ),
      ),
    );
  },
);

final settingsMetadataMatchSliceProvider = Provider<SettingsMetadataMatchSlice>(
  (ref) => ref.watch(
    appSettingsProvider.select(
      (settings) => SettingsMetadataMatchSlice(
        detailAutoLibraryMatchEnabled: settings.detailAutoLibraryMatchEnabled,
        metadataMatchPriority: settings.metadataMatchPriority,
        tmdbMetadataMatchEnabled: settings.tmdbMetadataMatchEnabled,
        tmdbReadAccessToken: settings.tmdbReadAccessToken,
        wmdbMetadataMatchEnabled: settings.wmdbMetadataMatchEnabled,
        imdbRatingMatchEnabled: settings.imdbRatingMatchEnabled,
      ),
    ),
  ),
);

@immutable
class SettingsHeroSlice {
  const SettingsHeroSlice({
    required this.sourceModuleId,
    required this.displayMode,
    required this.style,
    required this.logoTitleEnabled,
    required this.backgroundEnabled,
    required this.translucentEffectsEnabled,
    required this.performanceStaticHomeHeroEnabled,
    required this.performanceLightweightHomeHeroEnabled,
  });

  final String sourceModuleId;
  final HomeHeroDisplayMode displayMode;
  final HomeHeroStyle style;
  final bool logoTitleEnabled;
  final bool backgroundEnabled;
  final bool translucentEffectsEnabled;
  final bool performanceStaticHomeHeroEnabled;
  final bool performanceLightweightHomeHeroEnabled;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SettingsHeroSlice &&
            other.sourceModuleId == sourceModuleId &&
            other.displayMode == displayMode &&
            other.style == style &&
            other.logoTitleEnabled == logoTitleEnabled &&
            other.backgroundEnabled == backgroundEnabled &&
            other.translucentEffectsEnabled == translucentEffectsEnabled &&
            other.performanceStaticHomeHeroEnabled ==
                performanceStaticHomeHeroEnabled &&
            other.performanceLightweightHomeHeroEnabled ==
                performanceLightweightHomeHeroEnabled;
  }

  @override
  int get hashCode => Object.hash(
        sourceModuleId,
        displayMode,
        style,
        logoTitleEnabled,
        backgroundEnabled,
        translucentEffectsEnabled,
        performanceStaticHomeHeroEnabled,
        performanceLightweightHomeHeroEnabled,
      );
}

@immutable
class SettingsPlaybackSlice {
  const SettingsPlaybackSlice({
    required this.playbackEngine,
    required this.playbackDecodeMode,
    required this.nativeAudioOutputMode,
    required this.playbackMpvQualityPreset,
    required this.playbackMpvDoubleTapToSeekEnabled,
    required this.playbackMpvSwipeToSeekEnabled,
    required this.playbackMpvLongPressSpeedBoostEnabled,
    required this.playbackMpvStallAutoRecoveryEnabled,
    required this.playbackOpenTimeoutSeconds,
    required this.playbackDefaultSpeed,
    required this.playbackSubtitlePreference,
    this.playbackDefaultSubtitle = PlaybackDefaultSubtitle.systemLanguage,
    this.playbackDualSubtitlePrimaryLanguage =
        PlaybackSubtitleLanguage.simplifiedChinese,
    this.playbackDualSubtitleSecondaryLanguage =
        PlaybackSubtitleLanguage.english,
    required this.playbackSubtitleScale,
    this.playbackPrimarySubtitlePosition =
        kPlaybackPrimarySubtitlePositionDefault,
    this.playbackSecondarySubtitlePosition =
        kPlaybackSecondarySubtitlePositionDefault,
    this.playbackSecondarySubtitleScale =
        kPlaybackSecondarySubtitleScaleDefault,
    required this.onlineSubtitleSources,
    required this.assrtToken,
    required this.opensubtitlesEnabled,
    required this.opensubtitlesUsername,
    required this.opensubtitlesPassword,
    required this.subdlEnabled,
    required this.subdlApiKey,
    required this.subtitlePreferredLanguages,
    required this.subtitleSearchMaxValidatedCandidates,
    required this.configuredBackgroundPlaybackEnabled,
    required this.effectiveBackgroundPlaybackEnabled,
  });

  final PlaybackEngine playbackEngine;
  final PlaybackDecodeMode playbackDecodeMode;
  final NativeAudioOutputMode nativeAudioOutputMode;
  final PlaybackMpvQualityPreset playbackMpvQualityPreset;
  final bool playbackMpvDoubleTapToSeekEnabled;
  final bool playbackMpvSwipeToSeekEnabled;
  final bool playbackMpvLongPressSpeedBoostEnabled;
  final bool playbackMpvStallAutoRecoveryEnabled;
  final int playbackOpenTimeoutSeconds;
  final double playbackDefaultSpeed;
  final PlaybackSubtitlePreference playbackSubtitlePreference;
  final PlaybackDefaultSubtitle playbackDefaultSubtitle;
  final PlaybackSubtitleLanguage playbackDualSubtitlePrimaryLanguage;
  final PlaybackSubtitleLanguage playbackDualSubtitleSecondaryLanguage;
  final double playbackSubtitleScale;
  final double playbackPrimarySubtitlePosition;
  final double playbackSecondarySubtitlePosition;
  final double playbackSecondarySubtitleScale;
  final List<OnlineSubtitleSource> onlineSubtitleSources;
  final String assrtToken;
  final bool opensubtitlesEnabled;
  final String opensubtitlesUsername;
  final String opensubtitlesPassword;
  final bool subdlEnabled;
  final String subdlApiKey;
  final List<String> subtitlePreferredLanguages;
  final int subtitleSearchMaxValidatedCandidates;
  final bool configuredBackgroundPlaybackEnabled;
  final bool effectiveBackgroundPlaybackEnabled;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SettingsPlaybackSlice &&
            other.playbackEngine == playbackEngine &&
            other.playbackDecodeMode == playbackDecodeMode &&
            other.nativeAudioOutputMode == nativeAudioOutputMode &&
            other.playbackMpvQualityPreset == playbackMpvQualityPreset &&
            other.playbackMpvDoubleTapToSeekEnabled ==
                playbackMpvDoubleTapToSeekEnabled &&
            other.playbackMpvSwipeToSeekEnabled ==
                playbackMpvSwipeToSeekEnabled &&
            other.playbackMpvLongPressSpeedBoostEnabled ==
                playbackMpvLongPressSpeedBoostEnabled &&
            other.playbackMpvStallAutoRecoveryEnabled ==
                playbackMpvStallAutoRecoveryEnabled &&
            other.playbackOpenTimeoutSeconds == playbackOpenTimeoutSeconds &&
            other.playbackDefaultSpeed == playbackDefaultSpeed &&
            other.playbackSubtitlePreference == playbackSubtitlePreference &&
            other.playbackDefaultSubtitle == playbackDefaultSubtitle &&
            other.playbackDualSubtitlePrimaryLanguage ==
                playbackDualSubtitlePrimaryLanguage &&
            other.playbackDualSubtitleSecondaryLanguage ==
                playbackDualSubtitleSecondaryLanguage &&
            other.playbackSubtitleScale == playbackSubtitleScale &&
            other.playbackPrimarySubtitlePosition ==
                playbackPrimarySubtitlePosition &&
            other.playbackSecondarySubtitlePosition ==
                playbackSecondarySubtitlePosition &&
            other.playbackSecondarySubtitleScale ==
                playbackSecondarySubtitleScale &&
            listEquals(
              other.onlineSubtitleSources,
              onlineSubtitleSources,
            ) &&
            other.assrtToken == assrtToken &&
            other.opensubtitlesEnabled == opensubtitlesEnabled &&
            other.opensubtitlesUsername == opensubtitlesUsername &&
            other.opensubtitlesPassword == opensubtitlesPassword &&
            other.subdlEnabled == subdlEnabled &&
            other.subdlApiKey == subdlApiKey &&
            listEquals(
              other.subtitlePreferredLanguages,
              subtitlePreferredLanguages,
            ) &&
            other.subtitleSearchMaxValidatedCandidates ==
                subtitleSearchMaxValidatedCandidates &&
            other.configuredBackgroundPlaybackEnabled ==
                configuredBackgroundPlaybackEnabled &&
            other.effectiveBackgroundPlaybackEnabled ==
                effectiveBackgroundPlaybackEnabled;
  }

  @override
  int get hashCode => Object.hash(
        Object.hash(
          playbackEngine,
          playbackDecodeMode,
          nativeAudioOutputMode,
          playbackMpvQualityPreset,
          playbackMpvDoubleTapToSeekEnabled,
          playbackMpvSwipeToSeekEnabled,
          playbackMpvLongPressSpeedBoostEnabled,
          playbackMpvStallAutoRecoveryEnabled,
          playbackOpenTimeoutSeconds,
          playbackDefaultSpeed,
          playbackSubtitlePreference,
          playbackDefaultSubtitle,
          playbackDualSubtitlePrimaryLanguage,
          playbackDualSubtitleSecondaryLanguage,
          playbackSubtitleScale,
          playbackPrimarySubtitlePosition,
          playbackSecondarySubtitlePosition,
          playbackSecondarySubtitleScale,
        ),
        Object.hash(
          Object.hashAll(onlineSubtitleSources),
          assrtToken,
          opensubtitlesEnabled,
          opensubtitlesUsername,
          opensubtitlesPassword,
          subdlEnabled,
          subdlApiKey,
          Object.hashAll(subtitlePreferredLanguages),
          subtitleSearchMaxValidatedCandidates,
          configuredBackgroundPlaybackEnabled,
          effectiveBackgroundPlaybackEnabled,
        ),
      );
}

@immutable
class SettingsPerformanceSlice {
  const SettingsPerformanceSlice({
    required this.translucentEffectsEnabled,
    required this.autoHideNavigationBarEnabled,
    required this.homeHeroBackgroundEnabled,
    required this.reduceDecorationsEnabled,
    required this.reduceMotionEnabled,
    required this.staticNavigationEnabled,
    required this.staticHomeHeroEnabled,
    required this.lightweightHomeHeroEnabled,
    required this.configuredLiveItemHeroOverlayEnabled,
    required this.effectiveLiveItemHeroOverlayEnabled,
    required this.aggressivePlaybackTuningEnabled,
    required this.taskMaxConcurrency,
    required this.metadataPrefetchInitialBatchSize,
    required this.metadataPrefetchBatchDelayMs,
    required this.metadataPrefetchForegroundResumeDelayMs,
    required this.homeFeedInitialBatchSize,
    required this.homeFeedBatchDelayMs,
  });

  final bool translucentEffectsEnabled;
  final bool autoHideNavigationBarEnabled;
  final bool homeHeroBackgroundEnabled;
  final bool reduceDecorationsEnabled;
  final bool reduceMotionEnabled;
  final bool staticNavigationEnabled;
  final bool staticHomeHeroEnabled;
  final bool lightweightHomeHeroEnabled;
  final bool configuredLiveItemHeroOverlayEnabled;
  final bool effectiveLiveItemHeroOverlayEnabled;
  final bool aggressivePlaybackTuningEnabled;
  final int taskMaxConcurrency;
  final int metadataPrefetchInitialBatchSize;
  final int metadataPrefetchBatchDelayMs;
  final int metadataPrefetchForegroundResumeDelayMs;
  final int homeFeedInitialBatchSize;
  final int homeFeedBatchDelayMs;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SettingsPerformanceSlice &&
            other.translucentEffectsEnabled == translucentEffectsEnabled &&
            other.autoHideNavigationBarEnabled ==
                autoHideNavigationBarEnabled &&
            other.homeHeroBackgroundEnabled == homeHeroBackgroundEnabled &&
            other.reduceDecorationsEnabled == reduceDecorationsEnabled &&
            other.reduceMotionEnabled == reduceMotionEnabled &&
            other.staticNavigationEnabled == staticNavigationEnabled &&
            other.staticHomeHeroEnabled == staticHomeHeroEnabled &&
            other.lightweightHomeHeroEnabled == lightweightHomeHeroEnabled &&
            other.configuredLiveItemHeroOverlayEnabled ==
                configuredLiveItemHeroOverlayEnabled &&
            other.effectiveLiveItemHeroOverlayEnabled ==
                effectiveLiveItemHeroOverlayEnabled &&
            other.aggressivePlaybackTuningEnabled ==
                aggressivePlaybackTuningEnabled &&
            other.taskMaxConcurrency == taskMaxConcurrency &&
            other.metadataPrefetchInitialBatchSize ==
                metadataPrefetchInitialBatchSize &&
            other.metadataPrefetchBatchDelayMs ==
                metadataPrefetchBatchDelayMs &&
            other.metadataPrefetchForegroundResumeDelayMs ==
                metadataPrefetchForegroundResumeDelayMs &&
            other.homeFeedInitialBatchSize == homeFeedInitialBatchSize &&
            other.homeFeedBatchDelayMs == homeFeedBatchDelayMs;
  }

  @override
  int get hashCode => Object.hashAll([
        translucentEffectsEnabled,
        autoHideNavigationBarEnabled,
        homeHeroBackgroundEnabled,
        reduceDecorationsEnabled,
        reduceMotionEnabled,
        staticNavigationEnabled,
        staticHomeHeroEnabled,
        lightweightHomeHeroEnabled,
        configuredLiveItemHeroOverlayEnabled,
        effectiveLiveItemHeroOverlayEnabled,
        aggressivePlaybackTuningEnabled,
        taskMaxConcurrency,
        metadataPrefetchInitialBatchSize,
        metadataPrefetchBatchDelayMs,
        metadataPrefetchForegroundResumeDelayMs,
        homeFeedInitialBatchSize,
        homeFeedBatchDelayMs,
      ]);
}

@immutable
class SettingsMetadataMatchSlice {
  const SettingsMetadataMatchSlice({
    required this.detailAutoLibraryMatchEnabled,
    required this.metadataMatchPriority,
    required this.tmdbMetadataMatchEnabled,
    required this.tmdbReadAccessToken,
    required this.wmdbMetadataMatchEnabled,
    required this.imdbRatingMatchEnabled,
  });

  final bool detailAutoLibraryMatchEnabled;
  final MetadataMatchProvider metadataMatchPriority;
  final bool tmdbMetadataMatchEnabled;
  final String tmdbReadAccessToken;
  final bool wmdbMetadataMatchEnabled;
  final bool imdbRatingMatchEnabled;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SettingsMetadataMatchSlice &&
            other.detailAutoLibraryMatchEnabled ==
                detailAutoLibraryMatchEnabled &&
            other.metadataMatchPriority == metadataMatchPriority &&
            other.tmdbMetadataMatchEnabled == tmdbMetadataMatchEnabled &&
            other.tmdbReadAccessToken == tmdbReadAccessToken &&
            other.wmdbMetadataMatchEnabled == wmdbMetadataMatchEnabled &&
            other.imdbRatingMatchEnabled == imdbRatingMatchEnabled;
  }

  @override
  int get hashCode => Object.hash(
        detailAutoLibraryMatchEnabled,
        metadataMatchPriority,
        tmdbMetadataMatchEnabled,
        tmdbReadAccessToken,
        wmdbMetadataMatchEnabled,
        imdbRatingMatchEnabled,
      );
}
