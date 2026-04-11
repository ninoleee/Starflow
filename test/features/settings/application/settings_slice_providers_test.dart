import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      overrides: [appSettingsProvider.overrideWithValue(settings)],
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
        playbackOpenTimeoutSeconds: 60,
        playbackDefaultSpeed: 1.5,
        playbackSubtitlePreference: PlaybackSubtitlePreference.off,
        playbackSubtitleScale: PlaybackSubtitleScale.large,
        onlineSubtitleSources: [
          OnlineSubtitleSource.assrt,
          OnlineSubtitleSource.subhd,
        ],
        playbackBackgroundPlaybackEnabled: false,
      ),
    );
  });

  test('performance slice respects performance toggles', () {
    final settings = AppSettings.fromJson({
      'highPerformanceModeEnabled': true,
      'translucentEffectsEnabled': false,
      'autoHideNavigationBarEnabled': false,
      'homeHeroBackgroundEnabled': false,
    });
    final container = ProviderContainer(
      overrides: [appSettingsProvider.overrideWithValue(settings)],
    );
    addTearDown(container.dispose);

    expect(
      container.read(settingsPerformanceSliceProvider),
      const SettingsPerformanceSlice(
        highPerformanceModeEnabled: true,
        translucentEffectsEnabled: false,
        autoHideNavigationBarEnabled: false,
        homeHeroBackgroundEnabled: false,
      ),
    );
  });
}
