import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final homeModulesProvider = Provider<List<HomeModuleConfig>>((ref) {
  return ref.watch(
    appSettingsProvider.select((settings) => settings.homeModules),
  );
});

final homeDoubanAccountProvider = Provider<DoubanAccountConfig>((ref) {
  return ref.watch(
    appSettingsProvider.select((settings) => settings.doubanAccount),
  );
});

final homeMediaSourcesProvider = Provider<List<MediaSourceConfig>>((ref) {
  return ref.watch(
    appSettingsProvider.select((settings) => settings.mediaSources),
  );
});
