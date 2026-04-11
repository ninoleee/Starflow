import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/home/application/home_settings_slices.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('home settings slices stay stable under repeated reads and updates', () {
    final settingsStateProvider = StateProvider<AppSettings>(
      (ref) => _buildLargeSettings(moduleCount: 120, sourceCount: 24),
    );
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWith(
          (ref) => ref.watch(settingsStateProvider),
        ),
      ],
    );
    addTearDown(container.dispose);

    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < 800; i += 1) {
      final modules = container.read(homeModulesProvider);
      final account = container.read(homeDoubanAccountProvider);
      final sources = container.read(homeMediaSourcesProvider);
      expect(modules, hasLength(120));
      expect(account.enabled, isTrue);
      expect(sources, hasLength(24));
    }

    final notifier = container.read(settingsStateProvider.notifier);
    for (var i = 0; i < 32; i += 1) {
      final current = notifier.state;
      notifier.state = current.copyWith(
        doubanAccount: DoubanAccountConfig(
          enabled: true,
          userId: 'perf-user-$i',
        ),
      );
      expect(container.read(homeModulesProvider), hasLength(120));
      expect(
        container.read(homeDoubanAccountProvider).userId,
        'perf-user-$i',
      );
    }
    stopwatch.stop();

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
  });
}

AppSettings _buildLargeSettings({
  required int moduleCount,
  required int sourceCount,
}) {
  final homeModules = List<HomeModuleConfig>.generate(moduleCount, (index) {
    return HomeModuleConfig(
      id: 'home-module-$index',
      type: index.isEven
          ? HomeModuleType.recentlyAdded
          : HomeModuleType.doubanInterest,
      title: '模块 $index',
      enabled: true,
    );
  }, growable: false);

  final mediaSources = List<MediaSourceConfig>.generate(sourceCount, (index) {
    return MediaSourceConfig(
      id: 'source-$index',
      name: 'Source $index',
      kind: index.isEven ? MediaSourceKind.emby : MediaSourceKind.nas,
      endpoint: 'https://example.com/$index',
      enabled: true,
    );
  }, growable: false);

  return AppSettings(
    mediaSources: mediaSources,
    searchProviders: const [],
    doubanAccount: const DoubanAccountConfig(
      enabled: true,
      userId: 'perf-user-initial',
    ),
    homeModules: homeModules,
  );
}
