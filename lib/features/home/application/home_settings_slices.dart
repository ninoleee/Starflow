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

final homeFeedLoadLimitsProvider = Provider<
    ({
      int maxConcurrency,
      int initialBatchSize,
      int batchDelayMs,
    })>((ref) {
  return ref.watch(
    appSettingsProvider.select(
      (settings) => (
        maxConcurrency: settings.taskMaxConcurrency,
        initialBatchSize: settings.homeFeedInitialBatchSize,
        batchDelayMs: settings.homeFeedBatchDelayMs,
      ),
    ),
  );
});

final homeSelectableMediaSourcesProvider = Provider<List<MediaSourceConfig>>((
  ref,
) {
  return ref
      .watch(homeMediaSourcesProvider)
      .where(_isSelectableHomeMediaSource)
      .toList(growable: false);
});

final homeSelectableMediaSourceIdsProvider = Provider<Set<String>>((ref) {
  return ref
      .watch(homeSelectableMediaSourcesProvider)
      .map((source) => source.id.trim())
      .where((sourceId) => sourceId.isNotEmpty)
      .toSet();
});

bool _isSelectableHomeMediaSource(MediaSourceConfig source) {
  return source.canAppearInLibraryNavigation &&
      (source.kind == MediaSourceKind.emby ||
          source.kind == MediaSourceKind.nas ||
          source.kind == MediaSourceKind.quark);
}
