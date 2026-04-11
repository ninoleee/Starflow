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
  (ref) => ref.watch(
    appSettingsProvider.select(
      (settings) => SettingsPlaybackSlice(
        playbackEngine: settings.playbackEngine,
        playbackDecodeMode: settings.playbackDecodeMode,
        playbackMpvQualityPreset: settings.playbackMpvQualityPreset,
        playbackOpenTimeoutSeconds: settings.playbackOpenTimeoutSeconds,
        playbackDefaultSpeed: settings.playbackDefaultSpeed,
        playbackSubtitlePreference: settings.playbackSubtitlePreference,
        playbackSubtitleScale: settings.playbackSubtitleScale,
        onlineSubtitleSources: settings.onlineSubtitleSources,
        playbackBackgroundPlaybackEnabled:
            settings.playbackBackgroundPlaybackEnabled,
      ),
    ),
  ),
);

final settingsPerformanceSliceProvider = Provider<SettingsPerformanceSlice>(
  (ref) => ref.watch(
    appSettingsProvider.select(
      (settings) => SettingsPerformanceSlice(
        highPerformanceModeEnabled: settings.highPerformanceModeEnabled,
        translucentEffectsEnabled: settings.translucentEffectsEnabled,
        autoHideNavigationBarEnabled: settings.autoHideNavigationBarEnabled,
        homeHeroBackgroundEnabled: settings.homeHeroBackgroundEnabled,
      ),
    ),
  ),
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
    required this.playbackOpenTimeoutSeconds,
    required this.playbackDefaultSpeed,
    required this.playbackSubtitlePreference,
    required this.playbackSubtitleScale,
    required this.onlineSubtitleSources,
    required this.playbackBackgroundPlaybackEnabled,
  });

  final PlaybackEngine playbackEngine;
  final PlaybackDecodeMode playbackDecodeMode;
  final PlaybackMpvQualityPreset playbackMpvQualityPreset;
  final int playbackOpenTimeoutSeconds;
  final double playbackDefaultSpeed;
  final PlaybackSubtitlePreference playbackSubtitlePreference;
  final PlaybackSubtitleScale playbackSubtitleScale;
  final List<OnlineSubtitleSource> onlineSubtitleSources;
  final bool playbackBackgroundPlaybackEnabled;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SettingsPlaybackSlice &&
            other.playbackEngine == playbackEngine &&
            other.playbackDecodeMode == playbackDecodeMode &&
            other.playbackMpvQualityPreset == playbackMpvQualityPreset &&
            other.playbackOpenTimeoutSeconds == playbackOpenTimeoutSeconds &&
            other.playbackDefaultSpeed == playbackDefaultSpeed &&
            other.playbackSubtitlePreference == playbackSubtitlePreference &&
            other.playbackSubtitleScale == playbackSubtitleScale &&
            listEquals(
              other.onlineSubtitleSources,
              onlineSubtitleSources,
            ) &&
            other.playbackBackgroundPlaybackEnabled ==
                playbackBackgroundPlaybackEnabled;
  }

  @override
  int get hashCode => Object.hash(
        playbackEngine,
        playbackDecodeMode,
        playbackMpvQualityPreset,
        playbackOpenTimeoutSeconds,
        playbackDefaultSpeed,
        playbackSubtitlePreference,
        playbackSubtitleScale,
        Object.hashAll(onlineSubtitleSources),
        playbackBackgroundPlaybackEnabled,
      );
}

@immutable
class SettingsPerformanceSlice {
  const SettingsPerformanceSlice({
    required this.highPerformanceModeEnabled,
    required this.translucentEffectsEnabled,
    required this.autoHideNavigationBarEnabled,
    required this.homeHeroBackgroundEnabled,
  });

  final bool highPerformanceModeEnabled;
  final bool translucentEffectsEnabled;
  final bool autoHideNavigationBarEnabled;
  final bool homeHeroBackgroundEnabled;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SettingsPerformanceSlice &&
            other.highPerformanceModeEnabled == highPerformanceModeEnabled &&
            other.translucentEffectsEnabled == translucentEffectsEnabled &&
            other.autoHideNavigationBarEnabled ==
                autoHideNavigationBarEnabled &&
            other.homeHeroBackgroundEnabled == homeHeroBackgroundEnabled;
  }

  @override
  int get hashCode => Object.hash(
        highPerformanceModeEnabled,
        translucentEffectsEnabled,
        autoHideNavigationBarEnabled,
        homeHeroBackgroundEnabled,
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
