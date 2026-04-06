import 'package:starflow/features/playback/domain/playback_models.dart';

class PlaybackProgressEntry {
  const PlaybackProgressEntry({
    required this.key,
    required this.target,
    required this.updatedAt,
    this.seriesKey = '',
    this.seriesTitle = '',
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.progress = 0,
    this.completed = false,
  });

  final String key;
  final PlaybackTarget target;
  final DateTime updatedAt;
  final String seriesKey;
  final String seriesTitle;
  final Duration position;
  final Duration duration;
  final double progress;
  final bool completed;

  bool get hasProgress => position > Duration.zero || progress > 0;

  bool get canResume {
    if (completed) {
      return false;
    }
    final milliseconds = position.inMilliseconds;
    if (milliseconds < 5000) {
      return false;
    }
    if (duration > Duration.zero) {
      final remaining = duration - position;
      if (remaining <= const Duration(seconds: 12)) {
        return false;
      }
    }
    return progress < 0.985;
  }

  PlaybackProgressEntry copyWith({
    String? key,
    PlaybackTarget? target,
    DateTime? updatedAt,
    String? seriesKey,
    String? seriesTitle,
    Duration? position,
    Duration? duration,
    double? progress,
    bool? completed,
  }) {
    return PlaybackProgressEntry(
      key: key ?? this.key,
      target: target ?? this.target,
      updatedAt: updatedAt ?? this.updatedAt,
      seriesKey: seriesKey ?? this.seriesKey,
      seriesTitle: seriesTitle ?? this.seriesTitle,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      progress: progress ?? this.progress,
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'target': target.toJson(),
      'updatedAt': updatedAt.toIso8601String(),
      'seriesKey': seriesKey,
      'seriesTitle': seriesTitle,
      'positionMs': position.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'progress': progress,
      'completed': completed,
    };
  }

  factory PlaybackProgressEntry.fromJson(Map<String, dynamic> json) {
    return PlaybackProgressEntry(
      key: json['key'] as String? ?? '',
      target: PlaybackTarget.fromJson(
        Map<String, dynamic>.from((json['target'] as Map?) ?? const {}),
      ),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      seriesKey: json['seriesKey'] as String? ?? '',
      seriesTitle: json['seriesTitle'] as String? ?? '',
      position: Duration(
        milliseconds: (json['positionMs'] as num?)?.toInt() ?? 0,
      ),
      duration: Duration(
        milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0,
      ),
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      completed: json['completed'] as bool? ?? false,
    );
  }
}

class SeriesSkipPreference {
  const SeriesSkipPreference({
    required this.seriesKey,
    required this.updatedAt,
    this.seriesTitle = '',
    this.enabled = false,
    this.introDuration = Duration.zero,
    this.outroDuration = Duration.zero,
  });

  final String seriesKey;
  final DateTime updatedAt;
  final String seriesTitle;
  final bool enabled;
  final Duration introDuration;
  final Duration outroDuration;

  bool get hasEffect =>
      enabled &&
      (introDuration > Duration.zero || outroDuration > Duration.zero);

  SeriesSkipPreference copyWith({
    String? seriesKey,
    DateTime? updatedAt,
    String? seriesTitle,
    bool? enabled,
    Duration? introDuration,
    Duration? outroDuration,
  }) {
    return SeriesSkipPreference(
      seriesKey: seriesKey ?? this.seriesKey,
      updatedAt: updatedAt ?? this.updatedAt,
      seriesTitle: seriesTitle ?? this.seriesTitle,
      enabled: enabled ?? this.enabled,
      introDuration: introDuration ?? this.introDuration,
      outroDuration: outroDuration ?? this.outroDuration,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'seriesKey': seriesKey,
      'updatedAt': updatedAt.toIso8601String(),
      'seriesTitle': seriesTitle,
      'enabled': enabled,
      'introDurationMs': introDuration.inMilliseconds,
      'outroDurationMs': outroDuration.inMilliseconds,
    };
  }

  factory SeriesSkipPreference.fromJson(Map<String, dynamic> json) {
    return SeriesSkipPreference(
      seriesKey: json['seriesKey'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      seriesTitle: json['seriesTitle'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      introDuration: Duration(
        milliseconds: (json['introDurationMs'] as num?)?.toInt() ?? 0,
      ),
      outroDuration: Duration(
        milliseconds: (json['outroDurationMs'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

class PlaybackMemorySnapshot {
  const PlaybackMemorySnapshot({
    this.items = const {},
    this.series = const {},
    this.skipPreferences = const {},
  });

  final Map<String, PlaybackProgressEntry> items;
  final Map<String, PlaybackProgressEntry> series;
  final Map<String, SeriesSkipPreference> skipPreferences;

  Map<String, dynamic> toJson() {
    return {
      'items': items.map((key, value) => MapEntry(key, value.toJson())),
      'series': series.map((key, value) => MapEntry(key, value.toJson())),
      'skipPreferences': skipPreferences.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
    };
  }

  factory PlaybackMemorySnapshot.fromJson(Map<String, dynamic> json) {
    return PlaybackMemorySnapshot(
      items: (json['items'] as Map<dynamic, dynamic>? ?? const {}).map(
        (key, value) => MapEntry(
          '$key',
          PlaybackProgressEntry.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        ),
      ),
      series: (json['series'] as Map<dynamic, dynamic>? ?? const {}).map(
        (key, value) => MapEntry(
          '$key',
          PlaybackProgressEntry.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        ),
      ),
      skipPreferences:
          (json['skipPreferences'] as Map<dynamic, dynamic>? ?? const {}).map(
        (key, value) => MapEntry(
          '$key',
          SeriesSkipPreference.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        ),
      ),
    );
  }
}
