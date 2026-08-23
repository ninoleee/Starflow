import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/logging/app_logger.dart';

final metadataNetworkGuardProvider = Provider<MetadataNetworkGuard>((ref) {
  return MetadataNetworkGuard();
});

class MetadataNetworkGuard {
  MetadataNetworkGuard({
    this.requestTimeout = const Duration(seconds: 6),
    this.failureThreshold = 3,
    this.circuitOpenDuration = const Duration(minutes: 2),
  });

  final Duration requestTimeout;
  final int failureThreshold;
  final Duration circuitOpenDuration;
  final Map<String, _MetadataHostFailureState> _hosts = {};

  Future<http.Response> get(
    http.Client client,
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final host = uri.host.toLowerCase();
    final state = _hosts[host];
    final now = DateTime.now();
    if (state?.openUntil != null && now.isBefore(state!.openUntil!)) {
      throw MetadataNetworkCircuitOpenException(host, state.openUntil!);
    }
    try {
      final response =
          await client.get(uri, headers: headers).timeout(requestTimeout);
      if (response.statusCode < 500 &&
          response.statusCode != 408 &&
          response.statusCode != 429) {
        _hosts.remove(host);
      } else {
        _recordTransientFailure(host, 'HTTP ${response.statusCode}');
      }
      return response;
    } catch (error) {
      _recordTransientFailure(host, error.toString());
      rethrow;
    }
  }

  void _recordTransientFailure(String host, String reason) {
    final previous = _hosts[host];
    final count = (previous?.consecutiveFailures ?? 0) + 1;
    final openUntil = count >= failureThreshold
        ? DateTime.now().add(circuitOpenDuration)
        : null;
    _hosts[host] = _MetadataHostFailureState(
      consecutiveFailures: count,
      openUntil: openUntil,
    );
    if (openUntil != null) {
      appLogWarning(
        'metadata.network',
        'Metadata host circuit opened',
        fields: <String, Object?>{
          'host': host,
          'failureCount': count,
          'retryAfter': openUntil.toIso8601String(),
          'reason': reason,
        },
      );
    }
  }
}

class MetadataNetworkCircuitOpenException implements Exception {
  const MetadataNetworkCircuitOpenException(this.host, this.retryAfter);

  final String host;
  final DateTime retryAfter;

  @override
  String toString() =>
      'Metadata requests for $host are paused until ${retryAfter.toIso8601String()}';
}

class _MetadataHostFailureState {
  const _MetadataHostFailureState({
    required this.consecutiveFailures,
    required this.openUntil,
  });

  final int consecutiveFailures;
  final DateTime? openUntil;
}
