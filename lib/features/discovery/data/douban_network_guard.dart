import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/logging/app_logger.dart';

final doubanNetworkGuardProvider = Provider<DoubanNetworkGuard>((ref) {
  return DoubanNetworkGuard();
});

/// Shares timeout and circuit-breaker state across all Douban Home modules.
class DoubanNetworkGuard {
  DoubanNetworkGuard({
    this.requestTimeout = const Duration(seconds: 6),
    this.failureThreshold = 3,
    this.circuitOpenDuration = const Duration(minutes: 2),
  });

  final Duration requestTimeout;
  final int failureThreshold;
  final Duration circuitOpenDuration;
  final Map<String, _DoubanHostFailureState> _hosts = {};

  Future<http.Response> get(
    http.Client client,
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final host = uri.host.toLowerCase();
    final state = _hosts[host];
    final now = DateTime.now();
    if (state?.openUntil != null && now.isBefore(state!.openUntil!)) {
      appLogTrace(
        'douban.network',
        'Douban request skipped while circuit is open',
        fields: <String, Object?>{
          'host': host,
          'retryAfter': state.openUntil!.toIso8601String(),
        },
      );
      throw DoubanNetworkCircuitOpenException(host, state.openUntil!);
    }

    try {
      final response =
          await client.get(uri, headers: headers).timeout(requestTimeout);
      if (_isTransientStatus(response.statusCode)) {
        _recordTransientFailure(host, 'HTTP ${response.statusCode}');
      } else {
        _hosts.remove(host);
      }
      return response;
    } catch (error) {
      _recordTransientFailure(host, error.toString());
      rethrow;
    }
  }

  bool _isTransientStatus(int statusCode) {
    return statusCode >= 500 || statusCode == 408 || statusCode == 429;
  }

  void _recordTransientFailure(String host, String reason) {
    final previous = _hosts[host];
    final failureCount = (previous?.consecutiveFailures ?? 0) + 1;
    final openUntil = failureCount >= failureThreshold
        ? DateTime.now().add(circuitOpenDuration)
        : null;
    _hosts[host] = _DoubanHostFailureState(
      consecutiveFailures: failureCount,
      openUntil: openUntil,
    );
    if (openUntil != null) {
      appLogWarning(
        'douban.network',
        'Douban host circuit opened',
        fields: <String, Object?>{
          'host': host,
          'failureCount': failureCount,
          'retryAfter': openUntil.toIso8601String(),
          'reason': reason,
        },
      );
    }
  }
}

class DoubanNetworkCircuitOpenException implements Exception {
  const DoubanNetworkCircuitOpenException(this.host, this.retryAfter);

  final String host;
  final DateTime retryAfter;

  @override
  String toString() =>
      'Douban requests for $host are paused until ${retryAfter.toIso8601String()}';
}

class _DoubanHostFailureState {
  const _DoubanHostFailureState({
    required this.consecutiveFailures,
    required this.openUntil,
  });

  final int consecutiveFailures;
  final DateTime? openUntil;
}
