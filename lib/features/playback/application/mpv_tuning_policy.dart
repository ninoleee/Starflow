import 'dart:async';

import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

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

const int _mib = 1024 * 1024;

class MpvBufferBudget {
  const MpvBufferBudget({
    required this.forwardBytes,
    required this.backBytes,
    required this.memoryCapApplied,
  });

  final int forwardBytes;
  final int backBytes;
  final bool memoryCapApplied;
}

MpvBufferBudget resolveMpvBufferBudget({
  required PlaybackTarget target,
  required bool aggressiveTuning,
  required bool isTelevision,
  int? memoryClassMb,
}) {
  final remote = isLikelyRemotePlaybackTargetTransport(target);
  final heavy = isHeavyPlaybackTargetMetadata(target);
  final quark = isLikelyQuarkPlaybackTarget(target);
  var forwardBytes = switch ((quark, aggressiveTuning, remote, heavy)) {
    (true, true, _, _) => 256 * _mib,
    (true, false, _, _) => 192 * _mib,
    (false, true, _, _) => 128 * _mib,
    (false, false, true, _) when isTelevision => 96 * _mib,
    (false, false, _, true) => 96 * _mib,
    (false, false, true, false) => 64 * _mib,
    _ => 32 * _mib,
  };
  var backCapBytes = quark ? 64 * _mib : 32 * _mib;
  final originalForwardBytes = forwardBytes;

  if (isTelevision && memoryClassMb != null && memoryClassMb > 0) {
    if (memoryClassMb <= 256) {
      forwardBytes = forwardBytes.clamp(
        32 * _mib,
        (quark || heavy) ? 96 * _mib : 64 * _mib,
      );
      backCapBytes = 16 * _mib;
    } else if (memoryClassMb <= 512) {
      forwardBytes = forwardBytes.clamp(32 * _mib, 160 * _mib);
      backCapBytes = 32 * _mib;
    }
  }

  final backBytes = (forwardBytes ~/ 4).clamp(8 * _mib, backCapBytes);
  return MpvBufferBudget(
    forwardBytes: forwardBytes,
    backBytes: backBytes,
    memoryCapApplied: forwardBytes < originalForwardBytes,
  );
}

enum MpvOpenFailureKind { transientNetwork, permanent, unknown }

MpvOpenFailureKind classifyMpvOpenFailure(Object error) {
  if (error is TimeoutException) {
    return MpvOpenFailureKind.transientNetwork;
  }
  final message = '$error'.trim().toLowerCase();
  final statusMatch = RegExp(
    r'(?:http(?:\s+error)?|status\s+code)\s*[:=]?\s*(\d{3})',
  ).firstMatch(message);
  final statusCode = int.tryParse(statusMatch?.group(1) ?? '');
  if (statusCode != null) {
    if (statusCode == 408 ||
        statusCode == 425 ||
        statusCode == 429 ||
        (statusCode >= 500 && statusCode <= 599)) {
      return MpvOpenFailureKind.transientNetwork;
    }
    if (<int>{400, 401, 403, 404, 405, 410, 416}.contains(statusCode)) {
      return MpvOpenFailureKind.permanent;
    }
  }
  const permanentFragments = <String>[
    'protocol not found',
    'no such file',
    'file not found',
    'permission denied',
    'invalid argument',
    'unsupported',
    'unrecognized file format',
    'no video or audio streams selected',
  ];
  if (permanentFragments.any(message.contains)) {
    return MpvOpenFailureKind.permanent;
  }
  const transientFragments = <String>[
    'connection',
    'timed out',
    'timeout',
    'network',
    'broken pipe',
    'temporarily unavailable',
    'i/o error',
    'reset by peer',
    'failed to open',
  ];
  if (transientFragments.any(message.contains)) {
    return MpvOpenFailureKind.transientNetwork;
  }
  return MpvOpenFailureKind.unknown;
}

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

class MpvRemotePlaybackTuningProfile {
  const MpvRemotePlaybackTuningProfile({
    required this.name,
    required this.networkTimeoutSeconds,
    required this.cacheOnDisk,
    required this.cacheSecs,
    required this.demuxerReadaheadSecs,
    required this.demuxerHysteresisSecs,
    required this.cachePauseWait,
    required this.cachePauseInitial,
    required this.lowLatency,
  });

  final String name;
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
  double? preflightEstimatedMegabitsPerSecond,
  bool? highRiskContainerOverride,
}) {
  final _ = aggressiveTuning;
  final transportUrl = isLoopbackPlaybackRelayUrl(target.streamUrl)
      ? target.actualAddress
      : target.streamUrl;
  final scheme = playbackUrlScheme(transportUrl);
  final measuredSpeedMbps = preflightEstimatedMegabitsPerSecond;
  final bitrateMbps =
      (target.bitrate ?? 0) > 0 ? (target.bitrate! / 1000000) : null;
  final throughputToBitrateRatio = measuredSpeedMbps != null &&
          measuredSpeedMbps > 0 &&
          bitrateMbps != null &&
          bitrateMbps > 0
      ? measuredSpeedMbps / bitrateMbps
      : null;
  final fastStartupSpeed =
      throughputToBitrateRatio != null && throughputToBitrateRatio >= 2.5;
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
      name: 'low-latency',
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
    if (fastStartupSpeed && !veryHeavyPlayback && !highRiskContainer) {
      return const MpvRemotePlaybackTuningProfile(
        name: 'fast-start',
        networkTimeoutSeconds: '16',
        cacheOnDisk: 'no',
        cacheSecs: '45',
        demuxerReadaheadSecs: '12',
        demuxerHysteresisSecs: '5',
        cachePauseWait: '1.2',
        cachePauseInitial: 'no',
        lowLatency: false,
      );
    }
    final highRisk = isLikelyQuarkPlaybackTarget(target) ||
        criticalStartupSpeed ||
        lowStartupSpeed ||
        veryHeavyPlayback ||
        highRiskContainer ||
        codecComplexityRisk ||
        heavyPlayback;
    if (highRisk) {
      return const MpvRemotePlaybackTuningProfile(
        name: 'buffered-high-risk',
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
      name: 'buffered-standard',
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
