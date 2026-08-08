import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/library/application/emby_refresh_progress.dart';
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
  Future<void>? _activeBackgroundEmbyRefresh;
  int _backgroundEmbyRefreshGeneration = 0;

  Future<void> cancelBackgroundTasks() async {
    _backgroundEmbyRefreshGeneration += 1;
    _ref.read(embyRefreshProgressProvider.notifier).clear();
    await _ref.read(mediaRepositoryProvider).cancelActiveWebDavRefreshes(
          includeForceFull: true,
        );
  }

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

  Future<bool> startBackgroundEmbyRefresh({
    required List<String> sourceIds,
  }) async {
    final sources = _enabledRefreshableEmbySources(sourceIds);
    if (sources.isEmpty) {
      return false;
    }
    if (_activeBackgroundEmbyRefresh != null) {
      return false;
    }

    final progressController = _ref.read(embyRefreshProgressProvider.notifier);
    progressController.startTask(sources);
    final refreshGeneration = ++_backgroundEmbyRefreshGeneration;
    final refreshFuture = _runBackgroundEmbyRefresh(
      sources,
      progressController: progressController,
      refreshGeneration: refreshGeneration,
    );
    _activeBackgroundEmbyRefresh = refreshFuture;
    unawaited(
      refreshFuture.whenComplete(() {
        if (identical(_activeBackgroundEmbyRefresh, refreshFuture)) {
          _activeBackgroundEmbyRefresh = null;
        }
      }),
    );
    return true;
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

    _afterRefreshCompleted();
  }

  Future<void> _runBackgroundEmbyRefresh(
    List<MediaSourceConfig> sources, {
    required EmbyRefreshProgressController progressController,
    required int refreshGeneration,
  }) async {
    final repository = _ref.read(mediaRepositoryProvider);
    var refreshedSourceCount = 0;
    final failedSourceNames = <String>[];
    Object? lastError;

    for (var index = 0; index < sources.length; index += 1) {
      if (refreshGeneration != _backgroundEmbyRefreshGeneration) {
        return;
      }
      final source = sources[index];
      progressController.activateSource(sourceIndex: index);
      try {
        await repository.refreshSource(sourceId: source.id);
        if (refreshGeneration != _backgroundEmbyRefreshGeneration) {
          return;
        }
        refreshedSourceCount += 1;
        progressController.completeSource(sourceIndex: index);
      } catch (error) {
        if (refreshGeneration != _backgroundEmbyRefreshGeneration) {
          return;
        }
        lastError = error;
        failedSourceNames.add(
          source.name.trim().isEmpty ? source.id : source.name,
        );
      }
    }

    if (refreshGeneration != _backgroundEmbyRefreshGeneration) {
      return;
    }

    if (refreshedSourceCount > 0) {
      _afterRefreshCompleted();
    }

    if (failedSourceNames.isEmpty) {
      progressController.completeTask(
        _embyRefreshCompletedMessage(refreshedSourceCount),
      );
      return;
    }

    if (refreshedSourceCount > 0) {
      progressController.completeTask(
        '已完成 $refreshedSourceCount 个 Emby 媒体源更新，'
        '${failedSourceNames.length} 个失败',
      );
      return;
    }

    progressController.failTask(
      'Emby 后台更新失败：${lastError ?? failedSourceNames.join('、')}',
    );
  }

  List<MediaSourceConfig> _enabledRefreshableEmbySources(
    List<String> sourceIds,
  ) {
    final normalizedIds = sourceIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (normalizedIds.isEmpty) {
      return const <MediaSourceConfig>[];
    }

    return _ref
        .read(appSettingsProvider)
        .mediaSources
        .where(
          (source) =>
              source.enabled &&
              source.kind == MediaSourceKind.emby &&
              source.hasActiveSession &&
              normalizedIds.contains(source.id.trim()),
        )
        .toList(growable: false);
  }

  String _embyRefreshCompletedMessage(int sourceCount) {
    return sourceCount == 1 ? '已完成 Emby 更新' : '已完成 $sourceCount 个 Emby 媒体源更新';
  }

  void _afterRefreshCompleted() {
    _ref.read(libraryRefreshRevisionProvider.notifier).state++;
    _ref.invalidate(homeRecentItemsProvider);
    _ref.invalidate(homeCarouselItemsProvider);
    _ref.invalidate(homeSectionProvider);
    _ref.invalidate(homeSectionsProvider);
    primeHomeModules(_ref);
  }
}
