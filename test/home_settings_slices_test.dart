import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/home/application/home_settings_slices.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  group('home settings slices', () {
    test('homeModulesProvider only reacts to home module changes', () {
      final settingsStateProvider = StateProvider<AppSettings>(
        (ref) => _buildSettings(),
      );
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => ref.watch(settingsStateProvider),
          ),
        ],
      );
      addTearDown(container.dispose);

      final modulesBefore = container.read(homeModulesProvider);
      expect(modulesBefore, hasLength(2));

      final notifier = container.read(settingsStateProvider.notifier);
      notifier.state = notifier.state.copyWith(
        doubanAccount: const DoubanAccountConfig(
          enabled: true,
          userId: 'slice-user-2',
        ),
      );
      final modulesAfterUnrelatedUpdate = container.read(homeModulesProvider);
      expect(identical(modulesAfterUnrelatedUpdate, modulesBefore), isTrue);

      notifier.state = notifier.state.copyWith(
        homeModules: [
          ...notifier.state.homeModules,
          const HomeModuleConfig(
            id: 'home-module-extra',
            type: HomeModuleType.recentPlayback,
            title: '最近播放',
            enabled: true,
          ),
        ],
      );
      final modulesAfterHomeUpdate = container.read(homeModulesProvider);
      expect(modulesAfterHomeUpdate, hasLength(3));
      expect(identical(modulesAfterHomeUpdate, modulesBefore), isFalse);
    });

    test('homeDoubanAccountProvider and homeMediaSourcesProvider expose slices',
        () {
      final settings = _buildSettings();
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(settings),
        ],
      );
      addTearDown(container.dispose);

      final account = container.read(homeDoubanAccountProvider);
      final sources = container.read(homeMediaSourcesProvider);

      expect(account.enabled, isTrue);
      expect(account.userId, 'slice-user');
      expect(sources, hasLength(2));
      expect(sources.first.id, 'emby-main');
      expect(sources.last.kind, MediaSourceKind.nas);
    });
  });
}

AppSettings _buildSettings() {
  return AppSettings(
    mediaSources: const [
      MediaSourceConfig(
        id: 'emby-main',
        name: 'Emby',
        kind: MediaSourceKind.emby,
        endpoint: 'https://emby.example.com',
        enabled: true,
      ),
      MediaSourceConfig(
        id: 'nas-main',
        name: 'NAS',
        kind: MediaSourceKind.nas,
        endpoint: 'https://nas.example.com',
        enabled: true,
      ),
    ],
    searchProviders: const [],
    doubanAccount: const DoubanAccountConfig(
      enabled: true,
      userId: 'slice-user',
    ),
    homeModules: const [
      HomeModuleConfig(
        id: 'home-module-1',
        type: HomeModuleType.recentlyAdded,
        title: '最近新增',
        enabled: true,
      ),
      HomeModuleConfig(
        id: 'home-module-2',
        type: HomeModuleType.doubanInterest,
        title: '豆瓣想看',
        enabled: true,
      ),
    ],
  );
}
