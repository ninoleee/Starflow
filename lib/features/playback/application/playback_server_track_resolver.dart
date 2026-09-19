import 'package:media_kit/media_kit.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

PlaybackAudioStream? preferredPlaybackAudioStream(
  PlaybackTarget target,
) {
  return _preferredStream<PlaybackAudioStream>(
    target.audioStreams,
    target.preferredAudioStreamId,
    (stream) => stream.id,
    (stream) => stream.isDefault,
  );
}

PlaybackSubtitleStream? preferredPlaybackSubtitleStream(
  PlaybackTarget target,
) {
  return _preferredStream<PlaybackSubtitleStream>(
    target.subtitleStreams,
    target.preferredSubtitleStreamId,
    (stream) => stream.id,
    (stream) => stream.isDefault,
  );
}

AudioTrack? resolvePlaybackAudioTrack({
  required PlaybackTarget target,
  required List<AudioTrack> tracks,
  PlaybackAudioStream? preferred,
}) {
  final streams = [...target.audioStreams]
    ..sort((left, right) => left.index.compareTo(right.index));
  final preferredStream = preferred ?? preferredPlaybackAudioStream(target);
  if (preferredStream == null) {
    return null;
  }
  final embedded = tracks
      .where((track) =>
          track.id != 'auto' && track.id != 'no' && track.uri == false)
      .toList(growable: false);
  if (embedded.isEmpty) {
    return null;
  }

  final exact = embedded
      .where((track) => _matchesAudio(track, preferredStream, codec: true))
      .toList(growable: false);
  if (exact.length == 1) {
    return exact.single;
  }
  final titleAndLanguage = embedded
      .where((track) => _matchesAudio(track, preferredStream))
      .toList(growable: false);
  if (titleAndLanguage.length == 1) {
    return titleAndLanguage.single;
  }
  final languageAndChannels = embedded
      .where((track) => _matchesAudioChannels(track, preferredStream))
      .toList(growable: false);
  if (languageAndChannels.length == 1) {
    return languageAndChannels.single;
  }

  final ordinal =
      streams.indexWhere((stream) => stream.id == preferredStream.id);
  if (streams.length == embedded.length &&
      ordinal >= 0 &&
      ordinal < embedded.length) {
    return embedded[ordinal];
  }
  return null;
}

PlaybackAudioStream? matchPlaybackAudioStreamForTrack({
  required PlaybackTarget target,
  required List<AudioTrack> tracks,
  required AudioTrack track,
}) {
  final streams = [...target.audioStreams]
    ..sort((left, right) => left.index.compareTo(right.index));
  final embedded = tracks
      .where(
          (item) => item.id != 'auto' && item.id != 'no' && item.uri == false)
      .toList(growable: false);
  final ordinal = embedded.indexOf(track);
  for (final matches in [
    streams.where((stream) => _matchesAudio(track, stream, codec: true)),
    streams.where((stream) => _matchesAudio(track, stream)),
    streams.where((stream) => _matchesAudioChannels(track, stream)),
  ]) {
    if (matches.length == 1) return matches.single;
  }
  return streams.length == embedded.length &&
          ordinal >= 0 &&
          ordinal < streams.length
      ? streams[ordinal]
      : null;
}

SubtitleTrack? resolveEmbeddedPlaybackSubtitleTrack({
  required PlaybackTarget target,
  required List<SubtitleTrack> tracks,
  PlaybackSubtitleStream? preferred,
}) {
  final streams = target.subtitleStreams
      .where((stream) => !stream.isExternal)
      .toList(growable: false)
    ..sort((left, right) => left.index.compareTo(right.index));
  final preferredStream = preferred ?? preferredPlaybackSubtitleStream(target);
  if (preferredStream == null || preferredStream.isExternal) {
    return null;
  }
  final embedded = tracks
      .where((track) =>
          track.id != 'auto' &&
          track.id != 'no' &&
          track.uri == false &&
          track.data == false)
      .toList(growable: false);
  if (embedded.isEmpty) {
    return null;
  }

  final exact = embedded
      .where((track) => _matchesSubtitle(track, preferredStream))
      .toList(growable: false);
  if (exact.length == 1) {
    return exact.single;
  }
  final ordinal =
      streams.indexWhere((stream) => stream.id == preferredStream.id);
  if (ordinal >= 0 && ordinal < embedded.length) {
    return embedded[ordinal];
  }
  return null;
}

PlaybackSubtitleStream? matchPlaybackSubtitleStreamForTrack({
  required PlaybackTarget target,
  required List<SubtitleTrack> tracks,
  required SubtitleTrack track,
}) {
  final streams = target.subtitleStreams
      .where((stream) => !stream.isExternal)
      .toList(growable: false)
    ..sort((left, right) => left.index.compareTo(right.index));
  final embedded = tracks
      .where((item) =>
          item.id != 'auto' &&
          item.id != 'no' &&
          item.uri == false &&
          item.data == false)
      .toList(growable: false);
  final ordinal = embedded.indexOf(track);
  for (final stream in streams) {
    if (_matchesSubtitle(track, stream)) {
      return stream;
    }
  }
  return ordinal >= 0 && ordinal < streams.length ? streams[ordinal] : null;
}

T? _preferredStream<T>(
  List<T> streams,
  String preferredId,
  String Function(T stream) idOf,
  bool Function(T stream) isDefault,
) {
  if (streams.isEmpty) {
    return null;
  }
  final normalizedId = preferredId.trim();
  if (normalizedId.isNotEmpty) {
    for (final stream in streams) {
      if (idOf(stream).trim() == normalizedId) {
        return stream;
      }
    }
  }
  for (final stream in streams) {
    if (isDefault(stream)) {
      return stream;
    }
  }
  return streams.first;
}

bool _matchesAudio(
  AudioTrack track,
  PlaybackAudioStream stream, {
  bool codec = false,
}) {
  final title = _normalize(stream.title);
  final language = _normalizeLanguage(stream.language);
  if (title.isEmpty || language.isEmpty) {
    return false;
  }
  if (_normalize(track.title) != title ||
      _normalizeLanguage(track.language) != language) {
    return false;
  }
  if (!codec) {
    return true;
  }
  final targetCodec = _normalize(stream.codec);
  return targetCodec.isEmpty || _normalize(track.codec) == targetCodec;
}

bool _matchesAudioChannels(
  AudioTrack track,
  PlaybackAudioStream stream,
) {
  final language = _normalizeLanguage(stream.language);
  return language.isNotEmpty &&
      stream.channels > 0 &&
      _normalizeLanguage(track.language) == language &&
      track.channelscount == stream.channels;
}

bool _matchesSubtitle(
  SubtitleTrack track,
  PlaybackSubtitleStream stream,
) {
  final title = _normalize(stream.title);
  final language = _normalizeLanguage(stream.language);
  return title.isNotEmpty &&
      language.isNotEmpty &&
      _normalize(track.title) == title &&
      _normalizeLanguage(track.language) == language;
}

String _normalizeLanguage(String? value) =>
    switch (_normalize(value).replaceAll('_', '-')) {
      'eng' => 'en',
      'chi' || 'zho' || 'cmn' => 'zh',
      'jpn' => 'ja',
      final language => language,
    };

String _normalize(String? value) => (value ?? '').trim().toLowerCase();
