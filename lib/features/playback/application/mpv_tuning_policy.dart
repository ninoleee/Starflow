import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const Set<String> _kBufferedRemotePlaybackSchemes = {
  'http',
  'https',
  'ftp',
  'ftps',
};

const Set<String> _kLowLatencyRemotePlaybackSchemes = {
  'rtsp',
  'rtmp',
};

String playbackUrlScheme(String url) {
  return Uri.tryParse(url.trim())?.scheme.toLowerCase() ?? '';
}

bool isLikelyRemotePlaybackUrl(String url) {
  final scheme = playbackUrlScheme(url);
  return _kBufferedRemotePlaybackSchemes.contains(scheme) ||
      _kLowLatencyRemotePlaybackSchemes.contains(scheme);
}

bool isLikelyLiveRemotePlaybackUrl(String url) {
  return _kLowLatencyRemotePlaybackSchemes.contains(playbackUrlScheme(url));
}

bool isHeavyPlaybackTargetMetadata(PlaybackTarget target) {
  final width = target.width ?? 0;
  final height = target.height ?? 0;
  final bitrate = target.bitrate ?? 0;
  final codec = target.videoCodec.trim().toLowerCase();
  final is4k = width >= 3840 || height >= 2160;
  final isHevc = codec == 'hevc' || codec == 'h265' || codec == 'x265';
  final isAv1 = codec == 'av1';
  final veryHighBitrate = bitrate >= 24000000;
  final heavyHevc = isHevc && (is4k || bitrate >= 14000000);
  final heavyAv1 = isAv1 && bitrate >= 10000000;
  return is4k || veryHighBitrate || heavyHevc || heavyAv1;
}

PlaybackMpvQualityPreset resolveEffectivePlaybackMpvQualityPreset({
  required PlaybackMpvQualityPreset requestedPreset,
  required PlaybackTarget target,
  required bool isWindowsPlatform,
  required bool isTelevision,
  required bool isFullscreen,
  required bool aggressiveTuningEnabled,
  required PlaybackDecodeMode decodeMode,
}) {
  if (requestedPreset == PlaybackMpvQualityPreset.performanceFirst) {
    return requestedPreset;
  }

  final heavyPlayback = isHeavyPlaybackTargetMetadata(target);
  final remotePlayback = isLikelyRemotePlaybackUrl(target.streamUrl);
  final windowedWindows = isWindowsPlatform && !isTelevision && !isFullscreen;

  if (requestedPreset == PlaybackMpvQualityPreset.qualityFirst) {
    if (heavyPlayback) {
      return windowedWindows
          ? PlaybackMpvQualityPreset.performanceFirst
          : PlaybackMpvQualityPreset.balanced;
    }
    if (windowedWindows && remotePlayback) {
      return PlaybackMpvQualityPreset.balanced;
    }
  }

  if (requestedPreset == PlaybackMpvQualityPreset.balanced &&
      windowedWindows &&
      heavyPlayback &&
      (aggressiveTuningEnabled ||
          decodeMode == PlaybackDecodeMode.softwarePreferred)) {
    return PlaybackMpvQualityPreset.performanceFirst;
  }

  return requestedPreset;
}

class MpvRemotePlaybackTuningProfile {
  const MpvRemotePlaybackTuningProfile({
    required this.networkTimeoutSeconds,
    required this.cacheOnDisk,
    required this.cacheSecs,
    required this.demuxerReadaheadSecs,
    required this.demuxerHysteresisSecs,
    required this.cachePauseWait,
    required this.cachePauseInitial,
    required this.lowLatency,
  });

  final String networkTimeoutSeconds;
  final String cacheOnDisk;
  final String cacheSecs;
  final String demuxerReadaheadSecs;
  final String demuxerHysteresisSecs;
  final String cachePauseWait;
  final String cachePauseInitial;
  final bool lowLatency;
}

MpvRemotePlaybackTuningProfile? resolveMpvRemotePlaybackTuningProfile({
  required PlaybackTarget target,
  required bool aggressiveTuning,
  required bool heavyPlayback,
}) {
  final scheme = playbackUrlScheme(target.streamUrl);
  if (_kLowLatencyRemotePlaybackSchemes.contains(scheme)) {
    return MpvRemotePlaybackTuningProfile(
      networkTimeoutSeconds: aggressiveTuning || heavyPlayback ? '8' : '5',
      cacheOnDisk: 'no',
      cacheSecs: '',
      demuxerReadaheadSecs: aggressiveTuning ? '4' : '2',
      demuxerHysteresisSecs: aggressiveTuning ? '2' : '1',
      cachePauseWait: aggressiveTuning ? '0.4' : '0.2',
      cachePauseInitial: 'no',
      lowLatency: true,
    );
  }

  if (_kBufferedRemotePlaybackSchemes.contains(scheme)) {
    return MpvRemotePlaybackTuningProfile(
      networkTimeoutSeconds: aggressiveTuning || heavyPlayback ? '15' : '10',
      cacheOnDisk: 'no',
      cacheSecs: aggressiveTuning
          ? '45'
          : heavyPlayback
              ? '30'
              : '20',
      demuxerReadaheadSecs: aggressiveTuning
          ? '16'
          : heavyPlayback
              ? '10'
              : '6',
      demuxerHysteresisSecs: aggressiveTuning ? '8' : '4',
      cachePauseWait: aggressiveTuning
          ? '1.5'
          : heavyPlayback
              ? '1.0'
              : '0.8',
      cachePauseInitial: (aggressiveTuning || heavyPlayback) ? 'yes' : 'no',
      lowLatency: false,
    );
  }

  return null;
}

bool isLikelyLocalMpvIsoDeviceSource(
  String value, {
  required bool windowsPlatform,
  required bool posixPlatform,
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  if (_looksLikeWindowsAbsolutePath(trimmed) || _looksLikeUncPath(trimmed)) {
    return true;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) {
    return uri.scheme.toLowerCase() == 'file';
  }
  return posixPlatform && trimmed.startsWith('/');
}

bool _looksLikeWindowsAbsolutePath(String value) {
  return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value);
}

bool _looksLikeUncPath(String value) {
  return value.startsWith(r'\\') || value.startsWith('//');
}
