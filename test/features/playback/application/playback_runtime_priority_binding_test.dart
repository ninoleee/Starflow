import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_runtime_priority_binding.dart';
import 'package:starflow/features/playback/application/playback_session.dart';

void main() {
  test('playback mode cancels active refresh work with forceful priority',
      () async {
    final repository = _BindingFakeMediaRepository();
    final container = ProviderContainer(
      overrides: [
        mediaRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    container.read(playbackRuntimePriorityBindingProvider);

    container.read(playbackPerformanceModeProvider.notifier).state = true;
    await Future<void>.delayed(Duration.zero);

    expect(repository.cancelCalls, 1);
    expect(repository.cancelIncludeForceFullValues, [true]);

    container.read(playbackPerformanceModeProvider.notifier).state = false;
    await Future<void>.delayed(Duration.zero);
    container.read(playbackPerformanceModeProvider.notifier).state = true;
    await Future<void>.delayed(Duration.zero);

    expect(repository.cancelCalls, 2);
    expect(repository.cancelIncludeForceFullValues, [true, true]);
  });
}

class _BindingFakeMediaRepository implements MediaRepository {
  int cancelCalls = 0;
  final List<bool> cancelIncludeForceFullValues = <bool>[];

  @override
  Future<void> cancelActiveWebDavRefreshes({
    bool includeForceFull = false,
  }) async {
    cancelCalls += 1;
    cancelIncludeForceFullValues.add(includeForceFull);
  }

  @override
  Future<void> deleteResource({
    required String sourceId,
    required String resourcePath,
    String sectionId = '',
  }) async {}

  @override
  Future<List<MediaCollection>> fetchCollections({
    MediaSourceKind? kind,
    String? sourceId,
  }) async =>
      const <MediaCollection>[];

  @override
  Future<List<MediaItem>> fetchChildren({
    required String sourceId,
    required String parentId,
    String sectionId = '',
    String sectionName = '',
    int limit = 200,
  }) async =>
      const <MediaItem>[];

  @override
  Future<List<MediaItem>> fetchLibrary({
    MediaSourceKind? kind,
    String? sourceId,
    String? sectionId,
    int limit = 200,
  }) async =>
      const <MediaItem>[];

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({
    MediaSourceKind? kind,
    int limit = 10,
  }) async =>
      const <MediaItem>[];

  @override
  Future<List<MediaSourceConfig>> fetchSources() async =>
      const <MediaSourceConfig>[];

  @override
  Future<MediaItem?> findById(String id) async => null;

  @override
  Future<MediaItem?> matchTitle(String title) async => null;

  @override
  Future<void> refreshSource({
    required String sourceId,
    bool forceFullRescan = false,
  }) async {}
}
