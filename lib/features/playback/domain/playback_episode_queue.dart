import 'package:starflow/features/playback/domain/playback_models.dart';

class PlaybackEpisodeQueueEntry {
  const PlaybackEpisodeQueueEntry({
    required this.target,
    required this.playbackItemKey,
    required this.seriesKey,
  });

  final PlaybackTarget target;
  final String playbackItemKey;
  final String seriesKey;

  PlaybackEpisodeQueueEntry copyWith({
    PlaybackTarget? target,
    String? playbackItemKey,
    String? seriesKey,
  }) {
    return PlaybackEpisodeQueueEntry(
      target: target ?? this.target,
      playbackItemKey: playbackItemKey ?? this.playbackItemKey,
      seriesKey: seriesKey ?? this.seriesKey,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'target': target.toJson(),
      'playbackItemKey': playbackItemKey,
      'seriesKey': seriesKey,
    };
  }

  factory PlaybackEpisodeQueueEntry.fromJson(Map<String, dynamic> json) {
    return PlaybackEpisodeQueueEntry(
      target: PlaybackTarget.fromJson(
        Map<String, dynamic>.from(json['target'] as Map? ?? const {}),
      ),
      playbackItemKey: json['playbackItemKey'] as String? ?? '',
      seriesKey: json['seriesKey'] as String? ?? '',
    );
  }
}

class PlaybackEpisodeQueue {
  const PlaybackEpisodeQueue({
    required this.entries,
    this.currentIndex = 0,
  });

  final List<PlaybackEpisodeQueueEntry> entries;
  final int currentIndex;

  PlaybackEpisodeQueue copyWith({
    List<PlaybackEpisodeQueueEntry>? entries,
    int? currentIndex,
  }) {
    return PlaybackEpisodeQueue(
      entries: entries ?? this.entries,
      currentIndex: currentIndex ?? this.currentIndex,
    );
  }

  bool get isEmpty => entries.isEmpty;

  bool get hasCurrent =>
      currentIndex >= 0 && currentIndex < entries.length;

  bool get hasPrevious => currentIndex > 0 && currentIndex <= entries.length;

  bool get hasNext => currentIndex >= 0 && currentIndex + 1 < entries.length;

  PlaybackEpisodeQueueEntry? get currentEntry =>
      hasCurrent ? entries[currentIndex] : null;

  PlaybackEpisodeQueueEntry? get previousEntry =>
      hasPrevious ? entries[currentIndex - 1] : null;

  PlaybackEpisodeQueueEntry? get nextEntry =>
      hasNext ? entries[currentIndex + 1] : null;

  PlaybackEpisodeQueue replaceCurrentTarget(PlaybackTarget target) {
    if (!hasCurrent) {
      return this;
    }
    final nextEntries = [...entries];
    nextEntries[currentIndex] = nextEntries[currentIndex].copyWith(
      target: target,
    );
    return copyWith(entries: nextEntries);
  }

  PlaybackEpisodeQueue moveToNext() {
    if (!hasNext) {
      return this;
    }
    return copyWith(currentIndex: currentIndex + 1);
  }

  PlaybackEpisodeQueue moveToPrevious() {
    if (!hasPrevious) {
      return this;
    }
    return copyWith(currentIndex: currentIndex - 1);
  }

  Map<String, dynamic> toJson() {
    return {
      'currentIndex': currentIndex,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }

  factory PlaybackEpisodeQueue.fromJson(Map<String, dynamic> json) {
    return PlaybackEpisodeQueue(
      currentIndex: (json['currentIndex'] as num?)?.toInt() ?? 0,
      entries: (json['entries'] as List<dynamic>? ?? const [])
          .map(
            (entry) => PlaybackEpisodeQueueEntry.fromJson(
              Map<String, dynamic>.from(entry as Map? ?? const {}),
            ),
          )
          .toList(growable: false),
    );
  }
}
