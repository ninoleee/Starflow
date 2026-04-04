import 'package:starflow/features/library/domain/media_models.dart';

class PlaybackTarget {
  const PlaybackTarget({
    required this.title,
    required this.streamUrl,
    required this.sourceName,
    required this.sourceKind,
    this.subtitle = '',
    this.headers = const {},
  });

  final String title;
  final String streamUrl;
  final String sourceName;
  final MediaSourceKind sourceKind;
  final String subtitle;
  final Map<String, String> headers;

  factory PlaybackTarget.fromMediaItem(MediaItem item) {
    return PlaybackTarget(
      title: item.title,
      streamUrl: item.streamUrl,
      sourceName: item.sourceName,
      sourceKind: item.sourceKind,
      subtitle: item.overview,
    );
  }
}
