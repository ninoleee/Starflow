import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/core/network/starflow_http_transport.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

enum PlaybackRemotePreflightFailureReason {
  none,
  emptyUrl,
  unsupportedScheme,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  linkExpired,
  serverError,
  networkError,
}

class PlaybackRemotePreflightResult {
  const PlaybackRemotePreflightResult({
    required this.attempted,
    required this.canStream,
    required this.acceptableStatus,
    required this.supportsByteRange,
    required this.authLikelyInvalid,
    required this.linkLikelyExpired,
    required this.statusCode,
    required this.sampledBytes,
    required this.failureReason,
    required this.duration,
    this.samplePrefix = const <int>[],
    this.requestUri,
    this.finalUri,
    this.contentType,
    this.errorMessage,
  });

  final bool attempted;
  final bool canStream;
  final bool acceptableStatus;
  final bool supportsByteRange;
  final bool authLikelyInvalid;
  final bool linkLikelyExpired;
  final int? statusCode;
  final int sampledBytes;
  final PlaybackRemotePreflightFailureReason failureReason;
  final Duration duration;
  final List<int> samplePrefix;
  final Uri? requestUri;
  final Uri? finalUri;
  final String? contentType;
  final String? errorMessage;

  bool get hasHardFailure => !canStream || !acceptableStatus;

  bool get isHlsStream {
    final normalizedContentType = contentType?.trim().toLowerCase() ?? '';
    if (normalizedContentType.contains('mpegurl')) {
      return true;
    }
    return finalUri?.path.toLowerCase().endsWith('.m3u8') ?? false;
  }

  int? get estimatedSpeedBytesPerSecond {
    if (sampledBytes <= 0 || duration.inMicroseconds <= 0) {
      return null;
    }
    return (sampledBytes *
            Duration.microsecondsPerSecond /
            duration.inMicroseconds)
        .round();
  }
}

class PlaybackRemotePreflightOptions {
  const PlaybackRemotePreflightOptions({
    this.requestTimeout = const Duration(seconds: 4),
    this.streamSampleTimeout = const Duration(seconds: 2),
    this.rangeProbeBytes = 256 * 1024,
    this.readSampleBytes = 16 * 1024,
  });

  final Duration requestTimeout;
  final Duration streamSampleTimeout;
  final int rangeProbeBytes;
  final int readSampleBytes;
}

typedef PlaybackRemotePreflightClientFactory = http.Client Function();

class PlaybackRemotePreflight {
  PlaybackRemotePreflight({
    PlaybackRemotePreflightClientFactory? clientFactory,
  }) : _clientFactory = clientFactory ?? _defaultPreflightClientFactory;

  final PlaybackRemotePreflightClientFactory _clientFactory;

  Future<PlaybackRemotePreflightResult> probe(
    PlaybackTarget target, {
    PlaybackRemotePreflightOptions options =
        const PlaybackRemotePreflightOptions(),
  }) async {
    final startedAt = DateTime.now();
    final streamUrl = _resolveTransportUrl(target);
    if (streamUrl.isEmpty) {
      return _buildResult(
        startedAt: startedAt,
        canStream: false,
        acceptableStatus: false,
        supportsByteRange: false,
        authLikelyInvalid: false,
        linkLikelyExpired: false,
        failureReason: PlaybackRemotePreflightFailureReason.emptyUrl,
      );
    }

    final uri = Uri.tryParse(streamUrl);
    if (uri == null ||
        (uri.scheme.toLowerCase() != 'http' &&
            uri.scheme.toLowerCase() != 'https')) {
      return _buildResult(
        startedAt: startedAt,
        canStream: false,
        acceptableStatus: false,
        supportsByteRange: false,
        authLikelyInvalid: false,
        linkLikelyExpired: false,
        failureReason: PlaybackRemotePreflightFailureReason.unsupportedScheme,
      );
    }

    final client = _clientFactory();
    try {
      final request = http.Request('GET', uri)..headers.addAll(target.headers);
      final rangeEnd = options.rangeProbeBytes > 0
          ? options.rangeProbeBytes - 1
          : 255 * 1024;
      request.headers['Range'] = 'bytes=0-$rangeEnd';

      final response =
          await client.send(request).timeout(options.requestTimeout);
      final sample = await _readSample(
        response,
        sampleBytes: options.readSampleBytes,
        timeout: options.streamSampleTimeout,
      );
      final statusCode = response.statusCode;
      final acceptableStatus =
          statusCode == 200 || statusCode == 206 || statusCode == 416;
      final supportsByteRange = _supportsByteRange(response);
      final authLikelyInvalid = _isAuthLikelyInvalidStatus(statusCode);
      final linkLikelyExpired = _isExpiredLikeStatus(statusCode);

      return _buildResult(
        startedAt: startedAt,
        attempted: true,
        canStream: acceptableStatus && !authLikelyInvalid && !linkLikelyExpired,
        acceptableStatus: acceptableStatus,
        supportsByteRange: supportsByteRange,
        authLikelyInvalid: authLikelyInvalid,
        linkLikelyExpired: linkLikelyExpired,
        statusCode: statusCode,
        sampledBytes: sample.byteCount,
        samplePrefix: sample.prefix,
        failureReason: _classifyFailureReason(
          statusCode: statusCode,
          acceptableStatus: acceptableStatus,
          authLikelyInvalid: authLikelyInvalid,
          linkLikelyExpired: linkLikelyExpired,
        ),
        requestUri: uri,
        finalUri: response.request?.url,
        contentType: response.headers['content-type'],
      );
    } on TimeoutException catch (error) {
      return _buildResult(
        startedAt: startedAt,
        attempted: true,
        canStream: false,
        acceptableStatus: false,
        supportsByteRange: false,
        authLikelyInvalid: false,
        linkLikelyExpired: false,
        failureReason: PlaybackRemotePreflightFailureReason.timeout,
        requestUri: uri,
        errorMessage: error.message,
      );
    } catch (error) {
      return _buildResult(
        startedAt: startedAt,
        attempted: true,
        canStream: false,
        acceptableStatus: false,
        supportsByteRange: false,
        authLikelyInvalid: false,
        linkLikelyExpired: false,
        failureReason: PlaybackRemotePreflightFailureReason.networkError,
        requestUri: uri,
        errorMessage: '$error',
      );
    } finally {
      client.close();
    }
  }

  PlaybackRemotePreflightResult _buildResult({
    required DateTime startedAt,
    bool attempted = false,
    required bool canStream,
    required bool acceptableStatus,
    required bool supportsByteRange,
    required bool authLikelyInvalid,
    required bool linkLikelyExpired,
    required PlaybackRemotePreflightFailureReason failureReason,
    int? statusCode,
    int sampledBytes = 0,
    List<int> samplePrefix = const <int>[],
    Uri? requestUri,
    Uri? finalUri,
    String? contentType,
    String? errorMessage,
  }) {
    return PlaybackRemotePreflightResult(
      attempted: attempted,
      canStream: canStream,
      acceptableStatus: acceptableStatus,
      supportsByteRange: supportsByteRange,
      authLikelyInvalid: authLikelyInvalid,
      linkLikelyExpired: linkLikelyExpired,
      statusCode: statusCode,
      sampledBytes: sampledBytes,
      samplePrefix: samplePrefix,
      failureReason: failureReason,
      duration: DateTime.now().difference(startedAt),
      requestUri: requestUri,
      finalUri: finalUri,
      contentType: contentType,
      errorMessage: errorMessage,
    );
  }

  Future<({int byteCount, List<int> prefix})> _readSample(
    http.StreamedResponse response, {
    required int sampleBytes,
    required Duration timeout,
  }) async {
    var bytes = 0;
    final prefix = <int>[];
    final iterator = StreamIterator<List<int>>(response.stream);
    try {
      while (bytes < sampleBytes) {
        final hasNext = await iterator.moveNext().timeout(
              timeout,
              onTimeout: () => false,
            );
        if (!hasNext) {
          break;
        }
        final chunk = iterator.current;
        bytes += chunk.length;
        if (prefix.length < _maxSamplePrefixBytes) {
          prefix.addAll(
            chunk.take(_maxSamplePrefixBytes - prefix.length),
          );
        }
      }
      return (
        byteCount: bytes,
        prefix: List<int>.unmodifiable(prefix),
      );
    } finally {
      await iterator.cancel();
    }
  }

  bool _supportsByteRange(http.StreamedResponse response) {
    if (response.statusCode == 206 || response.statusCode == 416) {
      return true;
    }
    final acceptRanges = response.headers['accept-ranges']?.toLowerCase();
    if (acceptRanges != null && acceptRanges.contains('bytes')) {
      return true;
    }
    final contentRange = response.headers['content-range']?.toLowerCase();
    return contentRange != null && contentRange.startsWith('bytes ');
  }

  bool _isAuthLikelyInvalidStatus(int statusCode) {
    return statusCode == 401 || statusCode == 403;
  }

  bool _isExpiredLikeStatus(int statusCode) {
    return statusCode == 404 || statusCode == 410;
  }

  PlaybackRemotePreflightFailureReason _classifyFailureReason({
    required int statusCode,
    required bool acceptableStatus,
    required bool authLikelyInvalid,
    required bool linkLikelyExpired,
  }) {
    if (authLikelyInvalid) {
      return statusCode == 401
          ? PlaybackRemotePreflightFailureReason.unauthorized
          : PlaybackRemotePreflightFailureReason.forbidden;
    }
    if (linkLikelyExpired) {
      return statusCode == 404
          ? PlaybackRemotePreflightFailureReason.notFound
          : PlaybackRemotePreflightFailureReason.linkExpired;
    }
    if (!acceptableStatus && statusCode >= 500) {
      return PlaybackRemotePreflightFailureReason.serverError;
    }
    if (!acceptableStatus) {
      return PlaybackRemotePreflightFailureReason.networkError;
    }
    return PlaybackRemotePreflightFailureReason.none;
  }

  String _resolveTransportUrl(PlaybackTarget target) {
    final streamUrl = target.streamUrl.trim();
    if (isLoopbackPlaybackRelayUrl(streamUrl)) {
      final actualAddress = target.actualAddress.trim();
      if (actualAddress.isNotEmpty) {
        return actualAddress;
      }
    }
    return streamUrl;
  }
}

const int _maxSamplePrefixBytes = 64;

http.Client _defaultPreflightClientFactory() {
  return StarflowHttpClient(createStarflowTransportClient());
}
