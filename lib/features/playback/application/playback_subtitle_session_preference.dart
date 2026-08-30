import 'package:media_kit/media_kit.dart';
import 'package:starflow/features/playback/application/subtitle_language_preferences.dart';

enum PlaybackSubtitleSessionMode {
  automatic,
  off,
  single,
  dual,
}

class PlaybackSubtitleTrackFingerprint {
  const PlaybackSubtitleTrackFingerprint({
    required this.id,
    required this.title,
    required this.language,
    required this.codec,
    required this.isDefault,
    required this.isImage,
  });

  factory PlaybackSubtitleTrackFingerprint.fromTrack(SubtitleTrack track) {
    return PlaybackSubtitleTrackFingerprint(
      id: track.id.trim(),
      title: track.title?.trim() ?? '',
      language: track.language?.trim() ?? '',
      codec: track.codec?.trim() ?? '',
      isDefault: track.isDefault == true,
      isImage: track.image == true,
    );
  }

  final String id;
  final String title;
  final String language;
  final String codec;
  final bool isDefault;
  final bool isImage;
}

class PlaybackSubtitleSessionPreference {
  const PlaybackSubtitleSessionPreference._({
    required this.mode,
    this.primary,
    this.secondary,
  });

  const PlaybackSubtitleSessionPreference.automatic()
      : this._(mode: PlaybackSubtitleSessionMode.automatic);

  const PlaybackSubtitleSessionPreference.off()
      : this._(mode: PlaybackSubtitleSessionMode.off);

  PlaybackSubtitleSessionPreference.single(SubtitleTrack track)
      : this._(
          mode: PlaybackSubtitleSessionMode.single,
          primary: PlaybackSubtitleTrackFingerprint.fromTrack(track),
        );

  PlaybackSubtitleSessionPreference.dual({
    required SubtitleTrack primary,
    required SubtitleTrack secondary,
  }) : this._(
          mode: PlaybackSubtitleSessionMode.dual,
          primary: PlaybackSubtitleTrackFingerprint.fromTrack(primary),
          secondary: PlaybackSubtitleTrackFingerprint.fromTrack(secondary),
        );

  final PlaybackSubtitleSessionMode mode;
  final PlaybackSubtitleTrackFingerprint? primary;
  final PlaybackSubtitleTrackFingerprint? secondary;
}

SubtitleTrack? matchPlaybackSubtitleTrack(
  Iterable<SubtitleTrack> tracks,
  PlaybackSubtitleTrackFingerprint fingerprint, {
  Set<String> excludedIds = const <String>{},
  bool textOnly = false,
}) {
  SubtitleTrack? best;
  var bestScore = 0;
  for (final track in tracks) {
    if (_isSyntheticSubtitleTrack(track) ||
        track.uri ||
        track.data ||
        excludedIds.contains(track.id) ||
        (textOnly && track.image == true)) {
      continue;
    }
    final score = _scoreSubtitleTrackMatch(track, fingerprint);
    if (score > bestScore) {
      best = track;
      bestScore = score;
    }
  }
  return bestScore >= 30 ? best : null;
}

int _scoreSubtitleTrackMatch(
  SubtitleTrack track,
  PlaybackSubtitleTrackFingerprint fingerprint,
) {
  final trackLanguage = _canonicalTrackLanguage(track.language ?? '');
  final preferredLanguage = _canonicalTrackLanguage(fingerprint.language);
  final trackTitle = normalizeSubtitlePreferenceText(track.title ?? '');
  final preferredTitle = normalizeSubtitlePreferenceText(fingerprint.title);
  final trackCodec = (track.codec ?? '').trim().toLowerCase();
  final preferredCodec = fingerprint.codec.trim().toLowerCase();

  var score = 0;
  if (trackLanguage.isNotEmpty && preferredLanguage.isNotEmpty) {
    if (trackLanguage == preferredLanguage) {
      score += 120;
    } else if (trackLanguage.split('-').first ==
        preferredLanguage.split('-').first) {
      score += 72;
    } else {
      score -= 200;
    }
  }
  if (trackTitle.isNotEmpty && preferredTitle.isNotEmpty) {
    if (trackTitle == preferredTitle) {
      score += 100;
    } else if (trackTitle.contains(preferredTitle) ||
        preferredTitle.contains(trackTitle)) {
      score += 54;
    }
  }
  if (fingerprint.id.isNotEmpty && track.id == fingerprint.id) {
    score += 36;
  }
  if (trackCodec.isNotEmpty &&
      preferredCodec.isNotEmpty &&
      trackCodec == preferredCodec) {
    score += 14;
  }
  if ((track.isDefault == true) == fingerprint.isDefault) {
    score += 5;
  }
  if ((track.image == true) == fingerprint.isImage) {
    score += 5;
  }
  return score;
}

String _canonicalTrackLanguage(String raw) {
  final normalized = raw.trim().toLowerCase().replaceAll('_', '-');
  if (const <String>{
    'zh',
    'ch',
    'chi',
    'zho',
    'chn',
    'chinese',
    '中文',
    '中文字幕',
  }.contains(normalized)) {
    return 'zh';
  }
  final language = canonicalizeSubtitlePreferredLanguage(normalized);
  return const <String>{'und', 'zxx', 'null', 'unknown'}.contains(language)
      ? ''
      : language;
}

bool _isSyntheticSubtitleTrack(SubtitleTrack track) {
  return track.id == 'auto' || track.id == 'no';
}
