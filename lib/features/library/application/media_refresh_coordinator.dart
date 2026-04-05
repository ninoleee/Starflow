import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

final mediaRefreshCoordinatorProvider =
    Provider<MediaRefreshCoordinator>((ref) {
  return MediaRefreshCoordinator(ref);
});

class MediaRefreshCoordinator {
  MediaRefreshCoordinator(this._ref);

  final Ref _ref;

  Future<void> refreshSelectedSources({
    required List<String> sourceIds,
    int delaySeconds = 0,
    bool forceFullRescan = false,
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
                  source.kind == MediaSourceKind.nas),
        )
        .map((source) => source.id)
        .toSet();
    final scopedIds = normalizedIds
        .where(enabledRefreshableIds.contains)
        .toList(growable: false);
    if (scopedIds.isEmpty) {
      return;
    }

    if (delaySeconds > 0) {
      await Future<void>.delayed(Duration(seconds: delaySeconds));
    }

    final repository = _ref.read(mediaRepositoryProvider);
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

    _ref.invalidate(homeRecentItemsProvider);
    _ref.invalidate(homeCarouselItemsProvider);
    _ref.invalidate(homeSectionProvider);
    _ref.invalidate(homeSectionsProvider);
    primeHomeModules(_ref);
  }
}
