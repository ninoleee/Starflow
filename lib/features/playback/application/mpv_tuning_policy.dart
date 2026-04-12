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

  final codec = target.videoCodec.trim().toLowerCase();
  final isHevc = codec == 'hevc' || codec == 'h265' || codec == 'x265';
  final isAv1 = codec == 'av1';
  final codecComplexityRisk = isHevc || isAv1;
  final heavyPlayback = isHeavyPlaybackTargetMetadata(target);
  final remotePlayback =
      remotePlaybackOverride ?? isLikelyRemotePlaybackTargetTransport(target);
  final highRiskContainer = highRiskContainerOverride ?? false;
  final quarkPlayback = isLikelyQuarkPlaybackTarget(target);
  final measuredSpeedMbps = startupProbeMegabitsPerSecond;
  final lowStartupSpeed =
      measuredSpeedMbps != null && measuredSpeedMbps > 0 && measuredSpeedMbps < 12;
  final criticalStartupSpeed =
      measuredSpeedMbps != null && measuredSpeedMbps > 0 && measuredSpeedMbps < 6;
  final windowedWindows = isWindowsPlatform && !isTelevision && !isFullscreen;
  final riskyRemotePlayback = remotePlayback &&
      (quarkPlayback ||
          heavyPlayback ||
          codecComplexityRisk ||
          highRiskContainer ||
          lowStartupSpeed);

  if (requestedPreset == PlaybackMpvQualityPreset.qualityFirst) {
    if (remotePlayback && (criticalStartupSpeed || (quarkPlayback && lowStartupSpeed))) {
      return PlaybackMpvQualityPreset.performanceFirst;
    }
    if (remotePlayback &&
        heavyPlayback &&
        (codecComplexityRisk || highRiskContainer || lowStartupSpeed)) {
      return PlaybackMpvQualityPreset.performanceFirst;
    }
    if (riskyRemotePlayback) {
      return PlaybackMpvQualityPreset.balanced;
    }
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
      ((windowedWindows &&
              heavyPlayback &&
              (aggressiveTuningEnabled ||
                  decodeMode == PlaybackDecodeMode.softwarePreferred)) ||
          (remotePlayback &&
              (criticalStartupSpeed ||
                  (heavyPlayback && (codecComplexityRisk || highRiskContainer)) ||
                  (aggressiveTuningEnabled && lowStartupSpeed) ||
                  (decodeMode == PlaybackDecodeMode.softwarePreferred &&
                      (heavyPlayback || lowStartupSpeed)) ||
                  (quarkPlayback && lowStartupSpeed))))) {
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
  final transportUrl = isLoopbackPlaybackRelayUrl(target.streamUrl)
      ? target.actualAddress
      : target.streamUrl;
  final scheme = playbackUrlScheme(transportUrl);
  final measuredSpeedMbps = startupProbeMegabitsPerSecond;
  final lowStartupSpeed =
      measuredSpeedMbps != null && measuredSpeedMbps > 0 && measuredSpeedMbps < 12;
  final criticalStartupSpeed =
      measuredSpeedMbps != null && measuredSpeedMbps > 0 && measuredSpeedMbps < 6;
  final highRiskContainer = highRiskContainerOverride ?? false;
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
    if (isLikelyQuarkPlaybackTarget(target)) {
      if (criticalStartupSpeed) {
        return const MpvRemotePlaybackTuningProfile(
          networkTimeoutSeconds: '35',
          cacheOnDisk: 'no',
          cacheSecs: '180',
          demuxerReadaheadSecs: '48',
          demuxerHysteresisSecs: '24',
          cachePauseWait: '6.0',
          cachePauseInitial: 'yes',
          lowLatency: false,
        );
      }
      if (lowStartupSpeed || highRiskContainer) {
        return MpvRemotePlaybackTuningProfile(
          networkTimeoutSeconds: aggressiveTuning || heavyPlayback ? '30' : '28',
          cacheOnDisk: 'no',
          cacheSecs: aggressiveTuning || heavyPlayback ? '165' : '150',
          demuxerReadaheadSecs: aggressiveTuning || heavyPlayback ? '44' : '40',
          demuxerHysteresisSecs: aggressiveTuning || heavyPlayback ? '22' : '20',
          cachePauseWait: aggressiveTuning || heavyPlayback ? '5.5' : '5.0',
          cachePauseInitial: 'yes',
          lowLatency: false,
        );
      }
      return MpvRemotePlaybackTuningProfile(
        networkTimeoutSeconds: aggressiveTuning || heavyPlayback ? '25' : '20',
        cacheOnDisk: 'no',
        cacheSecs: aggressiveTuning
            ? '120'
            : heavyPlayback
                ? '90'
                : '75',
        demuxerReadaheadSecs: aggressiveTuning
            ? '36'
            : heavyPlayback
                ? '28'
                : '24',
        demuxerHysteresisSecs: aggressiveTuning ? '18' : '12',
        cachePauseWait: aggressiveTuning
            ? '4.0'
            : heavyPlayback
                ? '3.0'
                : '2.5',
        cachePauseInitial: 'yes',
        lowLatency: false,
      );
    }
    if (criticalStartupSpeed || (highRiskContainer && (heavyPlayback || lowStartupSpeed))) {
      return const MpvRemotePlaybackTuningProfile(
        networkTimeoutSeconds: '22',
        cacheOnDisk: 'no',
        cacheSecs: '70',
        demuxerReadaheadSecs: '24',
        demuxerHysteresisSecs: '12',
        cachePauseWait: '2.8',
        cachePauseInitial: 'yes',
        lowLatency: false,
      );
    }
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
