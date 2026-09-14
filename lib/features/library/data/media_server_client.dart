import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/fntv_api_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

final mediaServerClientProvider =
    Provider.family<MediaServerClient, MediaSourceKind>(
  (ref, kind) => switch (kind) {
    MediaSourceKind.emby => ref.watch(embyApiClientProvider),
    MediaSourceKind.fntv => ref.watch(fntvApiClientProvider),
    _ => throw ArgumentError.value(kind, 'kind', 'Not a media server'),
  },
);

abstract interface class MediaServerClient {
  Future<List<MediaCollection>> fetchCollections(MediaSourceConfig source);

  Future<List<MediaItem>> fetchLibrary(
    MediaSourceConfig source, {
    int limit = 200,
    String? sectionId,
    String sectionName = '',
  });

  Future<List<MediaItem>> fetchChildren(
    MediaSourceConfig source, {
    required String parentId,
    String sectionId = '',
    String sectionName = '',
    int limit = 200,
  });

  Future<PlaybackTarget> resolvePlaybackTarget({
    required MediaSourceConfig source,
    required PlaybackTarget target,
  });

  Future<List<PlaybackTarget>> fetchPlaybackVariants({
    required MediaSourceConfig source,
    required PlaybackTarget target,
  });

  Future<String> downloadExternalSubtitle({
    required MediaSourceConfig source,
    required String subtitleId,
  });
}
