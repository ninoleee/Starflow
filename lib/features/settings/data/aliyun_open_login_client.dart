import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/network/bounded_http_request.dart';
import 'package:starflow/core/network/starflow_http_transport.dart';
import 'package:starflow/features/settings/data/aliyun_open_oauth_config.dart';

final aliyunOpenLoginClientProvider = Provider((ref) {
  final transport = createStarflowTransportClient();
  ref.onDispose(transport.close);
  return AliyunOpenLoginClient(transport);
});

class AliyunOpenLoginException implements Exception {
  const AliyunOpenLoginException(this.message, {this.retryable = false});
  final String message;
  final bool retryable;
  @override
  String toString() => message;
}

class AliyunOpenQrToken {
  const AliyunOpenQrToken({
    required this.sessionId,
    required this.qrCodeUrl,
    required this.expiresIn,
  });

  final String sessionId;
  final String qrCodeUrl;
  final Duration expiresIn;
}

enum AliyunOpenQrStatus { waiting, scanned, confirmed, expired, cancelled }

class AliyunOpenQrResult {
  const AliyunOpenQrResult(this.status);
  final AliyunOpenQrStatus status;
}

class AliyunOpenToken {
  const AliyunOpenToken({
    required this.accessToken,
    required this.refreshToken,
    this.userId = '',
  });

  final String accessToken;
  final String refreshToken;
  final String userId;
}

class AliyunOpenLoginClient {
  AliyunOpenLoginClient(this.client);
  final http.Client client;
  static const _fingerprint = 'starflow';
  String? _selectedServiceBase;

  Future<Map<String, dynamic>> _get(Uri uri) async {
    var visited = false;
    late final http.Response response;
    try {
      response = await sendBoundedRequest(client, 'GET', uri,
          headers: {
            'Accept': 'application/json',
            'X-Client-Fingerprint': _fingerprint,
          },
          timeout: const Duration(seconds: 20),
          maxBytes: 128 * 1024, allowUri: (next) {
        if (visited) return false;
        visited = true;
        return next == uri;
      });
    } catch (_) {
      throw const AliyunOpenLoginException('阿里 Open 授权网络异常，请重试',
          retryable: true);
    }
    if (response.statusCode != 200) {
      throw AliyunOpenLoginException(
          response.statusCode == 429
              ? '阿里 Open 授权请求过于频繁，请稍后重试'
              : '阿里 Open 授权请求失败，请重试',
          retryable: response.statusCode == 429 || response.statusCode >= 500);
    }
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is! Map<String, dynamic>) {
        throw const AliyunOpenLoginException('阿里 Open 授权响应异常');
      }
      return value;
    } on AliyunOpenLoginException {
      rethrow;
    } catch (_) {
      throw const AliyunOpenLoginException('阿里 Open 授权响应异常');
    }
  }

  Future<Map<String, dynamic>> _getService(
      String path, Map<String, String>? query) async {
    final bases = _selectedServiceBase == null
        ? AliyunOpenOAuthConfig.serviceBases
        : [_selectedServiceBase!];
    AliyunOpenLoginException? lastError;
    for (final base in bases) {
      final uri = Uri.parse('$base$path').replace(queryParameters: query);
      try {
        final data = await _get(uri);
        _selectedServiceBase = base;
        return data;
      } on AliyunOpenLoginException catch (error) {
        lastError = error;
        if (!error.retryable) rethrow;
      }
    }
    throw lastError ?? const AliyunOpenLoginException('阿里 Open 授权请求失败');
  }

  Future<AliyunOpenQrToken> createToken() async {
    final data = await _getService(AliyunOpenOAuthConfig.generateQrPath, null);
    final session = data['session_id'];
    final qr = data['qr_code_url'];
    final expires = data['expires_in'];
    if (data['success'] != true ||
        session is! String ||
        session.isEmpty ||
        session.length > 256 ||
        qr is! String ||
        qr.isEmpty ||
        qr.length > 4096) {
      throw const AliyunOpenLoginException('阿里 Open 二维码响应无效');
    }
    final uri = Uri.tryParse(qr);
    if (uri == null ||
        uri.scheme != 'https' ||
        !{'passport.aliyundrive.com', 'passport.alipan.com'}
            .contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort) {
      throw const AliyunOpenLoginException('阿里 Open 二维码地址无效');
    }
    final seconds =
        expires is num && expires > 0 ? expires.toInt().clamp(30, 600) : 120;
    return AliyunOpenQrToken(
        sessionId: session,
        qrCodeUrl: qr,
        expiresIn: Duration(seconds: seconds));
  }

  Future<AliyunOpenQrResult> status(AliyunOpenQrToken token) async {
    final data = await _getService(
        AliyunOpenOAuthConfig.checkLoginPath, {'session_id': token.sessionId});
    final status = data['status'];
    return AliyunOpenQrResult(switch (status) {
      'WAITING' => AliyunOpenQrStatus.waiting,
      'SCANED' => AliyunOpenQrStatus.scanned,
      'CONFIRMED' => AliyunOpenQrStatus.confirmed,
      'EXPIRED' => AliyunOpenQrStatus.expired,
      'CANCELED' || 'CANCELLED' => AliyunOpenQrStatus.cancelled,
      _ => throw const AliyunOpenLoginException('阿里 Open 登录状态异常'),
    });
  }

  Future<AliyunOpenToken> complete(AliyunOpenQrToken token) async {
    final data = await _getService(
        AliyunOpenOAuthConfig.userInfoPath, {'session_id': token.sessionId});
    final access = data['access_token'];
    final refresh = data['refresh_token'];
    final info = data['user_info'];
    final userId = info is Map ? '${info['user_id'] ?? ''}' : '';
    if (data['success'] != true ||
        access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty) {
      throw const AliyunOpenLoginException('阿里 Open 登录凭据不完整');
    }
    return AliyunOpenToken(
        accessToken: access, refreshToken: refresh, userId: userId);
  }

  Future<AliyunOpenToken> refresh(String refreshToken) async {
    final data = await _getService(
        AliyunOpenOAuthConfig.renewPath, {'refresh_ui': refreshToken.trim()});
    final access = data['access_token'];
    final refresh = data['refresh_token'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        !_isJwt(refresh)) {
      throw const AliyunOpenLoginException('阿里 Open 登录已失效，请重新扫码');
    }
    return AliyunOpenToken(accessToken: access, refreshToken: refresh);
  }

  Future<void> logout(AliyunOpenQrToken token) async {
    try {
      await _getService(
          AliyunOpenOAuthConfig.logoutPath, {'session_id': token.sessionId});
    } catch (_) {
      // Logout is best-effort cleanup; the server session expires on its own.
    }
  }

  static bool _isJwt(String value) => value.split('.').length == 3;
}
