import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  test('rapid setting changes persist in user action order', () async {
    final repository = _OutOfOrderSettingsRepository(
      SeedData.defaultSettings.copyWith(
        homeStartupAutoRefreshEnabled: true,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);

    final first = controller.setHomeStartupAutoRefreshEnabled(false);
    final second = controller.setHomeStartupAutoRefreshEnabled(true);
    await Future.wait(<Future<void>>[first, second]);

    expect(repository.settings.homeStartupAutoRefreshEnabled, isTrue);
    expect(
      repository.savedValues,
      <bool>[false, true],
    );
  });

  test('home feed load limits persist through the settings controller',
      () async {
    final repository = _OutOfOrderSettingsRepository(SeedData.defaultSettings);
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);

    await controller.setTaskMaxConcurrency(4);
    await controller.setHomeFeedInitialBatchSize(3);
    await controller.setHomeFeedBatchDelayMs(250);
    await controller.setMetadataPrefetchBatchDelayMs(300);
    await controller.setMetadataPrefetchForegroundResumeDelayMs(400);
    await controller.setSimplifiedVisualEffectsEnabled(true);
    await controller.setReducedInterfaceMotionEnabled(true);
    await controller.setSimplifiedHomeHeroEnabled(true);

    expect(repository.settings.taskMaxConcurrency, 4);
    expect(repository.settings.homeFeedInitialBatchSize, 3);
    expect(repository.settings.homeFeedBatchDelayMs, 250);
    expect(repository.settings.metadataPrefetchBatchDelayMs, 300);
    expect(repository.settings.metadataPrefetchForegroundResumeDelayMs, 400);
    expect(repository.settings.translucentEffectsEnabled, isFalse);
    expect(repository.settings.performanceReduceDecorationsEnabled, isTrue);
    expect(repository.settings.performanceReduceMotionEnabled, isTrue);
    expect(repository.settings.performanceStaticNavigationEnabled, isTrue);
    expect(repository.settings.performanceStaticHomeHeroEnabled, isTrue);
    expect(repository.settings.performanceLightweightHomeHeroEnabled, isTrue);
    expect(
      container.read(appSettingsProvider).taskMaxConcurrency,
      4,
    );
    expect(
      container.read(appSettingsProvider).homeFeedInitialBatchSize,
      3,
    );
  });

  test('subtitle preferences persist without replacing other playback fields',
      () async {
    final initial = SeedData.defaultSettings.copyWith(
      playbackOpenTimeoutSeconds: 90,
      playbackDefaultSpeed: 1.5,
    );
    final repository = _OutOfOrderSettingsRepository(initial);
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);

    await container
        .read(settingsControllerProvider.notifier)
        .savePlaybackSubtitlePreferences(
          subtitlePreference: PlaybackSubtitlePreference.off,
          defaultSubtitle: PlaybackDefaultSubtitle.dual,
          subtitleScale: 40,
          primarySubtitlePosition: 75,
          secondarySubtitlePosition: 90,
          secondarySubtitleScale: 70,
          onlineSubtitleSources: const [OnlineSubtitleSource.assrt],
          assrtToken: ' token ',
          opensubtitlesEnabled: true,
          opensubtitlesUsername: ' user ',
          opensubtitlesPassword: 'password',
          subdlEnabled: true,
          subdlApiKey: ' key ',
          subtitlePreferredLanguages: const ['ZH-CN', 'en'],
          subtitleSearchMaxValidatedCandidates: 8,
        );

    expect(repository.settings.playbackSubtitlePreference,
        PlaybackSubtitlePreference.off);
    expect(
      repository.settings.playbackDefaultSubtitle,
      PlaybackDefaultSubtitle.dual,
    );
    expect(repository.settings.playbackSubtitleScale, 40);
    expect(repository.settings.playbackPrimarySubtitlePosition, 75);
    expect(repository.settings.playbackSecondarySubtitlePosition, 90);
    expect(repository.settings.playbackSecondarySubtitleScale, 70);
    expect(repository.settings.onlineSubtitleSources,
        const [OnlineSubtitleSource.assrt]);
    expect(repository.settings.assrtToken, 'token');
    expect(repository.settings.opensubtitlesUsername, 'user');
    expect(repository.settings.subdlApiKey, 'key');
    expect(repository.settings.subtitlePreferredLanguages, ['zh-cn', 'en']);
    expect(repository.settings.subtitleSearchMaxValidatedCandidates, 8);
    expect(repository.settings.playbackOpenTimeoutSeconds, 90);
    expect(repository.settings.playbackDefaultSpeed, 1.5);
  });

  test('subtitle style saves globally without replacing subtitle services',
      () async {
    final initial = SeedData.defaultSettings.copyWith(
      assrtToken: 'keep-token',
      playbackDefaultSpeed: 1.5,
    );
    final repository = _OutOfOrderSettingsRepository(initial);
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);

    await container
        .read(settingsControllerProvider.notifier)
        .savePlaybackSubtitleStylePreferences(
          subtitleScale: 38,
          primarySubtitlePosition: 75,
          secondarySubtitlePosition: 85,
          secondarySubtitleScale: 55,
        );

    expect(repository.settings.playbackSubtitleScale, 38);
    expect(repository.settings.playbackPrimarySubtitlePosition, 75);
    expect(repository.settings.playbackSecondarySubtitlePosition, 85);
    expect(repository.settings.playbackSecondarySubtitleScale, 55);
    expect(repository.settings.assrtToken, 'keep-token');
    expect(repository.settings.playbackDefaultSpeed, 1.5);
    expect(
      container.read(appSettingsProvider).playbackSecondarySubtitleScale,
      55,
    );
  });
}

class _OutOfOrderSettingsRepository implements AppSettingsRepository {
  _OutOfOrderSettingsRepository(this.settings);

  AppSettings settings;
  final List<bool> savedValues = <bool>[];

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings settings) async {
    final enabled = settings.homeStartupAutoRefreshEnabled;
    await Future<void>.delayed(
      enabled
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 40),
    );
    savedValues.add(enabled);
    this.settings = settings;
  }
}
