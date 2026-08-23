import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/network/network_failure.dart';

typedef NetworkCircuitExceptionFactory = Object Function(
  String host,
  DateTime retryAfter,
);

class NetworkRequestPolicy {
  const NetworkRequestPolicy({
    required this.id,
    required this.logCategory,
    this.requestTimeout = const Duration(seconds: 6),
    this.failureThreshold = 3,
    this.circuitOpenDuration = const Duration(minutes: 2),
    this.maxRetries = 0,
    this.retryDelay = const Duration(milliseconds: 250),
  });

  final String id;
  final String logCategory;
  final Duration requestTimeout;
  final int failureThreshold;
  final Duration circuitOpenDuration;
  final int maxRetries;
  final Duration retryDelay;
}

class NetworkRequestGuard {
  NetworkRequestGuard({
    required this.policy,
    NetworkCircuitExceptionFactory? circuitExceptionFactory,
  }) : _circuitExceptionFactory = circuitExceptionFactory ??
            ((host, retryAfter) => NetworkCircuitOpenException(
                  policyId: policy.id,
                  host: host,
                  retryAfter: retryAfter,
                ));

  final NetworkRequestPolicy policy;
  final NetworkCircuitExceptionFactory _circuitExceptionFactory;
  final Map<String, _NetworkHostFailureState> _hosts = {};

  Future<http.Response> get(
    http.Client client,
    Uri uri, {
    Map<String, String>? headers,
  }) {
    return run<http.Response>(
      uri: uri,
      idempotent: true,
      request: () => client.get(uri, headers: headers),
      statusCodeOf: (response) => response.statusCode,
    );
  }

  Future<T> run<T>({
    required Uri uri,
    required Future<T> Function() request,
    int? Function(T response)? statusCodeOf,
    bool idempotent = false,
  }) async {
    final host = uri.host.toLowerCase();
    _throwIfCircuitOpen(host);

    var attempt = 0;
    while (true) {
      try {
        final response = await request().timeout(policy.requestTimeout);
        final statusCode = statusCodeOf?.call(response);
        if (statusCode == null || !isTransientHttpStatus(statusCode)) {
          _hosts.remove(host);
          return response;
        }
        if (_shouldRetry(attempt: attempt, idempotent: idempotent)) {
          attempt += 1;
          await _waitBeforeRetry(
            host: host,
            attempt: attempt,
            failureKind: NetworkFailureKind.httpStatus,
          );
          continue;
        }
        _recordTransientFailure(
          host: host,
          failureKind: NetworkFailureKind.httpStatus,
          statusCode: statusCode,
        );
        return response;
      } catch (error) {
        if (error is NetworkCircuitOpenException) {
          rethrow;
        }
        final failure = classifyNetworkFailure(error);
        if (!failure.isTransient) {
          rethrow;
        }
        if (_shouldRetry(attempt: attempt, idempotent: idempotent)) {
          attempt += 1;
          await _waitBeforeRetry(
            host: host,
            attempt: attempt,
            failureKind: failure.kind,
          );
          continue;
        }
        _recordTransientFailure(
          host: host,
          failureKind: failure.kind,
        );
        rethrow;
      }
    }
  }

  void resetHost(String host) {
    _hosts.remove(host.trim().toLowerCase());
  }

  void _throwIfCircuitOpen(String host) {
    final state = _hosts[host];
    final now = DateTime.now();
    if (state?.openUntil == null || !now.isBefore(state!.openUntil!)) {
      if (state?.openUntil != null) {
        _hosts.remove(host);
      }
      return;
    }
    appLogTrace(
      policy.logCategory,
      'Network request skipped while circuit is open',
      fields: <String, Object?>{
        'policy': policy.id,
        'host': host,
        'failureKind': NetworkFailureKind.circuitOpen.name,
        'retryAfter': state.openUntil!.toIso8601String(),
      },
    );
    throw _circuitExceptionFactory(host, state.openUntil!);
  }

  bool _shouldRetry({required int attempt, required bool idempotent}) {
    return idempotent && attempt < policy.maxRetries;
  }

  Future<void> _waitBeforeRetry({
    required String host,
    required int attempt,
    required NetworkFailureKind failureKind,
  }) async {
    appLogTrace(
      policy.logCategory,
      'Transient network request scheduled for retry',
      fields: <String, Object?>{
        'policy': policy.id,
        'host': host,
        'attempt': attempt,
        'failureKind': failureKind.name,
        'retryDelayMs': policy.retryDelay.inMilliseconds,
      },
    );
    if (policy.retryDelay > Duration.zero) {
      await Future<void>.delayed(policy.retryDelay * attempt);
    }
  }

  void _recordTransientFailure({
    required String host,
    required NetworkFailureKind failureKind,
    int? statusCode,
  }) {
    final previous = _hosts[host];
    final failureCount = (previous?.consecutiveFailures ?? 0) + 1;
    final openUntil = failureCount >= policy.failureThreshold
        ? DateTime.now().add(policy.circuitOpenDuration)
        : null;
    _hosts[host] = _NetworkHostFailureState(
      consecutiveFailures: failureCount,
      openUntil: openUntil,
    );
    if (openUntil == null) {
      return;
    }
    appLogWarning(
      policy.logCategory,
      'Network host circuit opened',
      fields: <String, Object?>{
        'policy': policy.id,
        'host': host,
        'failureCount': failureCount,
        'failureKind': failureKind.name,
        if (statusCode != null) 'statusCode': statusCode,
        'retryAfter': openUntil.toIso8601String(),
      },
    );
  }
}

class _NetworkHostFailureState {
  const _NetworkHostFailureState({
    required this.consecutiveFailures,
    required this.openUntil,
  });

  final int consecutiveFailures;
  final DateTime? openUntil;
}
