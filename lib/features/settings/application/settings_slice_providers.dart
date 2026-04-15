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
          playbackSubtitleScale: settings.playbackSubtitleScale,
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
          highPerformanceModeEnabled: settings.highPerformanceModeEnabled,
          translucentEffectsEnabled: settings.translucentEffectsEnabled,
          autoHideNavigationBarEnabled: settings.autoHideNavigationBarEnabled,
          homeHeroBackgroundEnabled: settings.homeHeroBackgroundEnabled,
          configuredLiveItemHeroOverlayEnabled:
              settings.performanceLiveItemHeroOverlayEnabled,
          effectiveLiveItemHeroOverlayEnabled:
              effectiveLiveItemHeroOverlayEnabled,
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
    required this.playbackMpvQualityPreset,
    required this.playbackMpvDoubleTapToSeekEnabled,
    required this.playbackMpvSwipeToSeekEnabled,
    required this.playbackMpvLongPressSpeedBoostEnabled,
    required this.playbackMpvStallAutoRecoveryEnabled,
    required this.playbackOpenTimeoutSeconds,
    required this.playbackDefaultSpeed,
    required this.playbackSubtitlePreference,
    required this.playbackSubtitleScale,
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
  final PlaybackMpvQualityPreset playbackMpvQualityPreset;
  final bool playbackMpvDoubleTapToSeekEnabled;
  final bool playbackMpvSwipeToSeekEnabled;
  final bool playbackMpvLongPressSpeedBoostEnabled;
  final bool playbackMpvStallAutoRecoveryEnabled;
  final int playbackOpenTimeoutSeconds;
  final double playbackDefaultSpeed;
  final PlaybackSubtitlePreference playbackSubtitlePreference;
  final double playbackSubtitleScale;
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
            other.playbackSubtitleScale == playbackSubtitleScale &&
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
          playbackMpvQualityPreset,
          playbackMpvDoubleTapToSeekEnabled,
          playbackMpvSwipeToSeekEnabled,
          playbackMpvLongPressSpeedBoostEnabled,
          playbackMpvStallAutoRecoveryEnabled,
          playbackOpenTimeoutSeconds,
          playbackDefaultSpeed,
          playbackSubtitlePreference,
          playbackSubtitleScale,
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
    required this.highPerformanceModeEnabled,
    required this.translucentEffectsEnabled,
    required this.autoHideNavigationBarEnabled,
    required this.homeHeroBackgroundEnabled,
    required this.configuredLiveItemHeroOverlayEnabled,
    required this.effectiveLiveItemHeroOverlayEnabled,
  });

  final bool highPerformanceModeEnabled;
  final bool translucentEffectsEnabled;
  final bool autoHideNavigationBarEnabled;
  final bool homeHeroBackgroundEnabled;
  final bool configuredLiveItemHeroOverlayEnabled;
  final bool effectiveLiveItemHeroOverlayEnabled;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SettingsPerformanceSlice &&
            other.highPerformanceModeEnabled == highPerformanceModeEnabled &&
            other.translucentEffectsEnabled == translucentEffectsEnabled &&
            other.autoHideNavigationBarEnabled ==
                autoHideNavigationBarEnabled &&
            other.homeHeroBackgroundEnabled == homeHeroBackgroundEnabled &&
            other.configuredLiveItemHeroOverlayEnabled ==
                configuredLiveItemHeroOverlayEnabled &&
            other.effectiveLiveItemHeroOverlayEnabled ==
                effectiveLiveItemHeroOverlayEnabled;
  }

  @override
  int get hashCode => Object.hash(
        highPerformanceModeEnabled,
        translucentEffectsEnabled,
        autoHideNavigationBarEnabled,
        homeHeroBackgroundEnabled,
        configuredLiveItemHeroOverlayEnabled,
        effectiveLiveItemHeroOverlayEnabled,
      );
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
