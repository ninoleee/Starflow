import 'package:starflow/features/library/domain/media_models.dart';

class PlaybackTarget {
  const PlaybackTarget({
    required this.title,
    required this.sourceId,
    required this.streamUrl,
    required this.sourceName,
    required this.sourceKind,
    this.itemId = '',
    this.preferredMediaSourceId = '',
    this.subtitle = '',
    this.headers = const {},
  });

  final String title;
  final String sourceId;
  final String streamUrl;
  final String sourceName;
  final MediaSourceKind sourceKind;
  final String itemId;
  final String preferredMediaSourceId;
  final String subtitle;
  final Map<String, String> headers;

  bool get needsResolution =>
      streamUrl.trim().isEmpty &&
      sourceKind == MediaSourceKind.emby &&
      itemId.trim().isNotEmpty;

  bool get canPlay => streamUrl.trim().isNotEmpty || needsResolution;

  factory PlaybackTarget.fromMediaItem(MediaItem item) {
    return PlaybackTarget(
      title: item.title,
      sourceId: item.sourceId,
      streamUrl: item.streamUrl,
      sourceName: item.sourceName,
      sourceKind: item.sourceKind,
      itemId: item.playbackItemId,
      preferredMediaSourceId: item.preferredMediaSourceId,
      subtitle: item.overview,
      headers: item.streamHeaders,
    );
  }
}
