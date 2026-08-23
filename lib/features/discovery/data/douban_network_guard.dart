import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/network/network_failure.dart';
import 'package:starflow/core/network/network_request_guard.dart';

final doubanNetworkGuardProvider = Provider<DoubanNetworkGuard>((ref) {
  return DoubanNetworkGuard();
});

/// Shares timeout and circuit-breaker state across all Douban Home modules.
class DoubanNetworkGuard {
  DoubanNetworkGuard({
    Duration requestTimeout = const Duration(seconds: 6),
    int failureThreshold = 3,
    Duration circuitOpenDuration = const Duration(minutes: 2),
  }) : _delegate = NetworkRequestGuard(
          policy: NetworkRequestPolicy(
            id: 'douban',
            logCategory: 'douban.network',
            requestTimeout: requestTimeout,
            failureThreshold: failureThreshold,
            circuitOpenDuration: circuitOpenDuration,
          ),
          circuitExceptionFactory: DoubanNetworkCircuitOpenException.new,
        );

  final NetworkRequestGuard _delegate;

  Future<http.Response> get(
    http.Client client,
    Uri uri, {
    Map<String, String>? headers,
  }) {
    return _delegate.get(client, uri, headers: headers);
  }
}

class DoubanNetworkCircuitOpenException extends NetworkCircuitOpenException {
  const DoubanNetworkCircuitOpenException(String host, DateTime retryAfter)
      : super(
          policyId: 'douban',
          host: host,
          retryAfter: retryAfter,
        );

  @override
  String toString() =>
      'Douban requests for $host are paused until ${retryAfter.toIso8601String()}';
}
