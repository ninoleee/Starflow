import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/application/settings_slice_providers.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  test('hero slice reflects hero-related app settings', () {
    final settings = AppSettings.fromJson({
      'homeHeroSourceModuleId': 'module-hero',
      'homeHeroDisplayMode': 'borderless',
      'homeHeroStyle': 'poster',
      'homeHeroLogoTitleEnabled': true,
      'homeHeroBackgroundEnabled': false,
      'translucentEffectsEnabled': false,
      'performanceStaticHomeHeroEnabled': true,
      'performanceLightweightHomeHeroEnabled': false,
    });
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWithValue(settings),
        isTelevisionProvider.overrideWith((ref) => false),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(settingsHeroSliceProvider),
      const SettingsHeroSlice(
        sourceModuleId: 'module-hero',
        displayMode: HomeHeroDisplayMode.borderless,
        style: HomeHeroStyle.poster,
        logoTitleEnabled: true,
        backgroundEnabled: false,
        translucentEffectsEnabled: false,
        performanceStaticHomeHeroEnabled: true,
        performanceLightweightHomeHeroEnabled: false,
      ),
    );
  });

  test('playback slice mirrors playback configuration', () {
    final settings = AppSettings.fromJson({
      'playbackEngine': 'nativeContainer',
      'playbackDecodeMode': 'hardwarePreferred',
      'playbackMpvQualityPreset': 'performanceFirst',
      'playbackOpenTimeoutSeconds': 60,
      'playbackDefaultSpeed': 1.5,
      'playbackSubtitlePreference': 'off',
      'playbackSubtitleScale': 'large',
      'onlineSubtitleSources': ['assrt', 'subhd'],
      'playbackBackgroundPlaybackEnabled': false,
    });
    final container = ProviderContainer(
      overrides: [appSettingsProvider.overrideWithValue(settings)],
    );
    addTearDown(container.dispose);

    expect(
      container.read(settingsPlaybackSliceProvider),
      const SettingsPlaybackSlice(
        playbackEngine: PlaybackEngine.nativeContainer,
        playbackDecodeMode: PlaybackDecodeMode.hardwarePreferred,
        playbackMpvQualityPreset: PlaybackMpvQualityPreset.performanceFirst,
        playbackMpvDoubleTapToSeekEnabled: true,
        playbackMpvSwipeToSeekEnabled: true,
        playbackMpvLongPressSpeedBoostEnabled: true,
        playbackMpvStallAutoRecoveryEnabled: true,
        playbackOpenTimeoutSeconds: 60,
        playbackDefaultSpeed: 1.5,
        playbackSubtitlePreference: PlaybackSubtitlePreference.off,
        playbackSubtitleScale: PlaybackSubtitleScale.large,
        onlineSubtitleSources: [
          OnlineSubtitleSource.assrt,
          OnlineSubtitleSource.subhd,
        ],
        configuredBackgroundPlaybackEnabled: false,
        effectiveBackgroundPlaybackEnabled: false,
      ),
    );
  });

  test('playback slice falls back to performance mpv preset for unknown value',
      () {
    final settings = AppSettings.fromJson({
      'playbackMpvQualityPreset': 'unknown-preset',
    });
    final container = ProviderContainer(
      overrides: [appSettingsProvider.overrideWithValue(settings)],
    );
    addTearDown(container.dispose);

    expect(
      container.read(settingsPlaybackSliceProvider).playbackMpvQualityPreset,
      PlaybackMpvQualityPreset.performanceFirst,
    );
  });

  test('performance slice respects performance toggles', () {
    final settings = AppSettings.fromJson({
      'highPerformanceModeEnabled': true,
      'translucentEffectsEnabled': false,
      'autoHideNavigationBarEnabled': false,
      'homeHeroBackgroundEnabled': false,
      'performanceLiveItemHeroOverlayEnabled': false,
    });
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWithValue(settings),
        isTelevisionProvider.overrideWith((ref) => false),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(settingsPerformanceSliceProvider),
      const SettingsPerformanceSlice(
        highPerformanceModeEnabled: true,
        translucentEffectsEnabled: false,
        autoHideNavigationBarEnabled: false,
        homeHeroBackgroundEnabled: false,
        configuredLiveItemHeroOverlayEnabled: false,
        effectiveLiveItemHeroOverlayEnabled: false,
      ),
    );
  });

  test('runtime item hero overlay is forced off on television', () async {
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWithValue(
          const AppSettings(
            mediaSources: [],
            searchProviders: [],
            doubanAccount: DoubanAccountConfig(enabled: false),
            homeModules: [],
            performanceLiveItemHeroOverlayEnabled: true,
          ),
        ),
        isTelevisionProvider.overrideWith((ref) => true),
      ],
    );
    addTearDown(container.dispose);

    await container.read(isTelevisionProvider.future);

    expect(
      container.read(effectivePerformanceLiveItemHeroOverlayEnabledProvider),
      isFalse,
    );
  });

  test(
      'playback slice keeps configured background playback but forces effect off on television',
      () async {
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWithValue(
          const AppSettings(
            mediaSources: [],
            searchProviders: [],
            doubanAccount: DoubanAccountConfig(enabled: false),
            homeModules: [],
            playbackBackgroundPlaybackEnabled: true,
          ),
        ),
        isTelevisionProvider.overrideWith((ref) => true),
      ],
    );
    addTearDown(container.dispose);

    await container.read(isTelevisionProvider.future);

    expect(
      container.read(settingsPlaybackSliceProvider),
      const SettingsPlaybackSlice(
        playbackEngine: PlaybackEngine.embeddedMpv,
        playbackDecodeMode: PlaybackDecodeMode.auto,
        playbackMpvQualityPreset: PlaybackMpvQualityPreset.performanceFirst,
        playbackMpvDoubleTapToSeekEnabled: true,
        playbackMpvSwipeToSeekEnabled: true,
        playbackMpvLongPressSpeedBoostEnabled: true,
        playbackMpvStallAutoRecoveryEnabled: true,
        playbackOpenTimeoutSeconds: 20,
        playbackDefaultSpeed: 1.0,
        playbackSubtitlePreference: PlaybackSubtitlePreference.auto,
        playbackSubtitleScale: PlaybackSubtitleScale.standard,
        onlineSubtitleSources: [OnlineSubtitleSource.assrt],
        configuredBackgroundPlaybackEnabled: true,
        effectiveBackgroundPlaybackEnabled: false,
      ),
    );
    expect(container.read(effectivePlaybackBackgroundEnabledProvider), isFalse);
  });

  test(
      'playback slice keeps both configured and effective background playback on non-tv',
      () async {
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWithValue(
          const AppSettings(
            mediaSources: [],
            searchProviders: [],
            doubanAccount: DoubanAccountConfig(enabled: false),
            homeModules: [],
            playbackBackgroundPlaybackEnabled: true,
          ),
        ),
        isTelevisionProvider.overrideWith((ref) => false),
      ],
    );
    addTearDown(container.dispose);

    await container.read(isTelevisionProvider.future);

    final slice = container.read(settingsPlaybackSliceProvider);
    expect(slice.configuredBackgroundPlaybackEnabled, isTrue);
    expect(slice.effectiveBackgroundPlaybackEnabled, isTrue);
    expect(container.read(effectivePlaybackBackgroundEnabledProvider), isTrue);
  });
}
