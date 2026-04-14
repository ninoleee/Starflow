import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
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

bool isLikelyRemotePlaybackTargetTransport(PlaybackTarget target) {
  return isLikelyRemotePlaybackUrl(target.streamUrl) ||
      (isLoopbackPlaybackRelayUrl(target.streamUrl) &&
          isLikelyRemotePlaybackUrl(target.actualAddress));
}

bool isLikelyQuarkPlaybackTarget(PlaybackTarget target) {
  return target.sourceKind == MediaSourceKind.quark &&
      isLikelyRemotePlaybackTargetTransport(target);
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

bool isHighRiskRemotePlaybackContainer(PlaybackTarget target) {
  const riskyContainers = <String>{
    'mkv',
    'ts',
    'm2ts',
    'mts',
    'flv',
    'avi',
  };
  final container = target.container.trim().toLowerCase();
  if (riskyContainers.contains(container)) {
    return true;
  }

  final candidateUrl = isLoopbackPlaybackRelayUrl(target.streamUrl)
      ? target.actualAddress
      : target.streamUrl;
  final uri = Uri.tryParse(candidateUrl.trim());
  final path = (uri?.path ?? candidateUrl).toLowerCase();
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex >= path.length - 1) {
    return false;
  }
  final extension = path.substring(dotIndex + 1).trim();
  return riskyContainers.contains(extension);
}

bool _isHevcCodec(String codec) {
  final normalized = codec.trim().toLowerCase();
  return normalized == 'hevc' || normalized == 'h265' || normalized == 'x265';
}

bool _isAv1Codec(String codec) {
  return codec.trim().toLowerCase() == 'av1';
}

bool _isCodecComplexityRisk(PlaybackTarget target) {
  return _isHevcCodec(target.videoCodec) || _isAv1Codec(target.videoCodec);
}

bool _isVeryHeavyPlaybackTargetMetadata(PlaybackTarget target) {
  final width = target.width ?? 0;
  final height = target.height ?? 0;
  final bitrate = target.bitrate ?? 0;
  final is4k = width >= 3840 || height >= 2160;
  final is8k = width >= 7680 || height >= 4320;
  final codecComplexityRisk = _isCodecComplexityRisk(target);
  final extremelyHighBitrate = bitrate >= 36000000;
  final veryHighBitrate = bitrate >= 28000000;
  return is8k ||
      extremelyHighBitrate ||
      (is4k && codecComplexityRisk && veryHighBitrate);
}

PlaybackMpvQualityPreset resolveEffectivePlaybackMpvQualityPreset({
  required PlaybackMpvQualityPreset requestedPreset,
  required PlaybackTarget target,
  required bool isWindowsPlatform,
  required bool isTelevision,
  required bool isFullscreen,
  required bool aggressiveTuningEnabled,
  required PlaybackDecodeMode decodeMode,
  bool? remotePlaybackOverride,
  bool? highRiskContainerOverride,
  double? startupProbeMegabitsPerSecond,
}) {
  if (requestedPreset == PlaybackMpvQualityPreset.performanceFirst) {
    return requestedPreset;
  }

  final codecComplexityRisk = _isCodecComplexityRisk(target);
  final heavyPlayback = isHeavyPlaybackTargetMetadata(target);
  final veryHeavyPlayback = _isVeryHeavyPlaybackTargetMetadata(target);
  final remotePlayback =
      remotePlaybackOverride ?? isLikelyRemotePlaybackTargetTransport(target);
  final highRiskContainer =
      highRiskContainerOverride ?? isHighRiskRemotePlaybackContainer(target);
  final quarkPlayback = isLikelyQuarkPlaybackTarget(target);
  final measuredSpeedMbps = startupProbeMegabitsPerSecond;
  final lowStartupSpeed = measuredSpeedMbps != null &&
      measuredSpeedMbps > 0 &&
      measuredSpeedMbps < 16;
  final criticalStartupSpeed = measuredSpeedMbps != null &&
      measuredSpeedMbps > 0 &&
      measuredSpeedMbps < 8;
  final constrainedStartupSpeed = measuredSpeedMbps != null &&
      measuredSpeedMbps > 0 &&
      measuredSpeedMbps < 24;
  final windowedWindows = isWindowsPlatform && !isTelevision && !isFullscreen;
  final remoteRisk = remotePlayback &&
      (quarkPlayback ||
          heavyPlayback ||
          veryHeavyPlayback ||
          codecComplexityRisk ||
          highRiskContainer ||
          constrainedStartupSpeed);
  final severeRemoteRisk = remotePlayback &&
      (criticalStartupSpeed ||
          veryHeavyPlayback ||
          (decodeMode == PlaybackDecodeMode.softwarePreferred &&
              (codecComplexityRisk || heavyPlayback)) ||
          (lowStartupSpeed &&
              (codecComplexityRisk || highRiskContainer || heavyPlayback)));

  if (requestedPreset == PlaybackMpvQualityPreset.qualityFirst) {
    if (severeRemoteRisk || remoteRisk) {
      return PlaybackMpvQualityPreset.performanceFirst;
    }
    if (heavyPlayback &&
        (codecComplexityRisk ||
            decodeMode == PlaybackDecodeMode.softwarePreferred ||
            (aggressiveTuningEnabled && constrainedStartupSpeed))) {
      return PlaybackMpvQualityPreset.balanced;
    }
    if (veryHeavyPlayback) {
      return PlaybackMpvQualityPreset.balanced;
    }
    if (heavyPlayback && windowedWindows) {
      return windowedWindows
          ? PlaybackMpvQualityPreset.performanceFirst
          : PlaybackMpvQualityPreset.balanced;
    }
    if (windowedWindows && remotePlayback) {
      return PlaybackMpvQualityPreset.performanceFirst;
    }
  }

  if (requestedPreset == PlaybackMpvQualityPreset.balanced &&
      ((remoteRisk || severeRemoteRisk) ||
          (windowedWindows &&
              heavyPlayback &&
              (aggressiveTuningEnabled ||
                  decodeMode == PlaybackDecodeMode.softwarePreferred)) ||
          (remotePlayback &&
              (veryHeavyPlayback ||
                  (heavyPlayback &&
                      (codecComplexityRisk ||
                          highRiskContainer ||
                          lowStartupSpeed)) ||
                  (decodeMode == PlaybackDecodeMode.softwarePreferred &&
                      (heavyPlayback ||
                          codecComplexityRisk ||
                          highRiskContainer ||
                          lowStartupSpeed)) ||
                  quarkPlayback)) ||
          (!remotePlayback &&
              heavyPlayback &&
              decodeMode == PlaybackDecodeMode.softwarePreferred &&
              (codecComplexityRisk || highRiskContainer)))) {
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
  double? startupProbeMegabitsPerSecond,
  bool? highRiskContainerOverride,
}) {
  final _ = aggressiveTuning;
  final transportUrl = isLoopbackPlaybackRelayUrl(target.streamUrl)
      ? target.actualAddress
      : target.streamUrl;
  final scheme = playbackUrlScheme(transportUrl);
  final measuredSpeedMbps = startupProbeMegabitsPerSecond;
  final lowStartupSpeed = measuredSpeedMbps != null &&
      measuredSpeedMbps > 0 &&
      measuredSpeedMbps < 16;
  final criticalStartupSpeed = measuredSpeedMbps != null &&
      measuredSpeedMbps > 0 &&
      measuredSpeedMbps < 8;
  final highRiskContainer =
      highRiskContainerOverride ?? isHighRiskRemotePlaybackContainer(target);
  final codecComplexityRisk = _isCodecComplexityRisk(target);
  final veryHeavyPlayback = _isVeryHeavyPlaybackTargetMetadata(target);
  if (_kLowLatencyRemotePlaybackSchemes.contains(scheme)) {
    return const MpvRemotePlaybackTuningProfile(
      networkTimeoutSeconds: '10',
      cacheOnDisk: 'no',
      cacheSecs: '',
      demuxerReadaheadSecs: '4',
      demuxerHysteresisSecs: '2',
      cachePauseWait: '0.5',
      cachePauseInitial: 'no',
      lowLatency: true,
    );
  }

  if (_kBufferedRemotePlaybackSchemes.contains(scheme)) {
    final highRisk = isLikelyQuarkPlaybackTarget(target) ||
        criticalStartupSpeed ||
        lowStartupSpeed ||
        veryHeavyPlayback ||
        highRiskContainer ||
        codecComplexityRisk ||
        heavyPlayback;
    if (highRisk) {
      return const MpvRemotePlaybackTuningProfile(
        networkTimeoutSeconds: '32',
        cacheOnDisk: 'no',
        cacheSecs: '150',
        demuxerReadaheadSecs: '42',
        demuxerHysteresisSecs: '20',
        cachePauseWait: '5.2',
        cachePauseInitial: 'yes',
        lowLatency: false,
      );
    }
    return const MpvRemotePlaybackTuningProfile(
      networkTimeoutSeconds: '24',
      cacheOnDisk: 'no',
      cacheSecs: '90',
      demuxerReadaheadSecs: '28',
      demuxerHysteresisSecs: '12',
      cachePauseWait: '3.0',
      cachePauseInitial: 'yes',
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
