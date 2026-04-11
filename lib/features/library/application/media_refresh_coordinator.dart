import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/library/application/library_refresh_revision.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_session.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

final mediaRefreshCoordinatorProvider =
    Provider<MediaRefreshCoordinator>((ref) {
  return MediaRefreshCoordinator(ref);
});

List<String> resolveRefreshSourceIdsForQuarkSave({
  required List<MediaSourceConfig> mediaSources,
  required Iterable<String> configuredRefreshSourceIds,
  bool includeConfiguredSources = true,
}) {
  final resolved = <String>{};

  if (includeConfiguredSources) {
    resolved.addAll(
      configuredRefreshSourceIds
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty),
    );
  }

  resolved.addAll(
    mediaSources
        .where(
          (source) =>
              source.enabled &&
              source.kind == MediaSourceKind.quark &&
              source.hasConfiguredQuarkFolder,
        )
        .map((source) => source.id.trim())
        .where((item) => item.isNotEmpty),
  );

  return resolved.toList(growable: false);
}

class MediaRefreshCoordinator {
  MediaRefreshCoordinator(this._ref);

  final Ref _ref;

  Future<void> refreshSelectedSources({
    required List<String> sourceIds,
    int delaySeconds = 0,
  }) async {
    await _runRefresh(
      sourceIds: sourceIds,
      delaySeconds: delaySeconds,
      forceFullRescan: false,
    );
  }

  Future<void> rebuildSelectedSources({
    required List<String> sourceIds,
  }) async {
    await _runRefresh(
      sourceIds: sourceIds,
      delaySeconds: 0,
      forceFullRescan: true,
    );
  }

  Future<void> _runRefresh({
    required List<String> sourceIds,
    required int delaySeconds,
    required bool forceFullRescan,
  }) async {
    final normalizedIds = sourceIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedIds.isEmpty) {
      return;
    }

    final enabledRefreshableIds = _ref
        .read(appSettingsProvider)
        .mediaSources
        .where(
          (source) =>
              source.enabled &&
              (source.kind == MediaSourceKind.emby ||
                  source.kind == MediaSourceKind.nas ||
                  (source.kind == MediaSourceKind.quark &&
                      source.hasConfiguredQuarkFolder)),
        )
        .map((source) => source.id)
        .toSet();
    final scopedIds = normalizedIds
        .where(enabledRefreshableIds.contains)
        .toList(growable: false);
    if (scopedIds.isEmpty) {
      return;
    }

    if (_ref.read(playbackPerformanceModeProvider)) {
      await _ref.read(mediaRepositoryProvider).cancelActiveWebDavRefreshes(
            includeForceFull: false,
          );
      return;
    }

    if (delaySeconds > 0) {
      await Future<void>.delayed(Duration(seconds: delaySeconds));
      if (_ref.read(playbackPerformanceModeProvider)) {
        await _ref.read(mediaRepositoryProvider).cancelActiveWebDavRefreshes(
              includeForceFull: false,
            );
        return;
      }
    }

    final repository = _ref.read(mediaRepositoryProvider);
    await repository.cancelActiveWebDavRefreshes(includeForceFull: true);
    await Future.wait(
      scopedIds.map(
        (sourceId) async {
          try {
            await repository.refreshSource(
              sourceId: sourceId,
              forceFullRescan: forceFullRescan,
            );
          } catch (_) {
            // Best-effort refresh to avoid interrupting save flow.
          }
        },
      ),
    );

    _ref.read(libraryRefreshRevisionProvider.notifier).state++;
    _ref.invalidate(homeRecentItemsProvider);
    _ref.invalidate(homeCarouselItemsProvider);
    _ref.invalidate(homeSectionProvider);
    _ref.invalidate(homeSectionsProvider);
    primeHomeModules(_ref);
  }
}
