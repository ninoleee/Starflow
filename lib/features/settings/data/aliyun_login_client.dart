import 'dart:convert';

import 'package:charset/charset.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/network/bounded_http_request.dart';
import 'package:starflow/core/network/starflow_http_transport.dart';

// QR sessions and login responses contain secrets; bypass HTTP logging.
final aliyunLoginClientProvider = Provider((ref) {
  final transport = createStarflowTransportClient();
  ref.onDispose(transport.close);
  return AliyunLoginClient(transport);
});

class AliyunLoginException implements Exception {
  const AliyunLoginException(this.message, {this.retryable = false});
  final String message;
  final bool retryable;
  @override
  String toString() => message;
}

class AliyunQrToken {
  const AliyunQrToken(
      {required this.t, required this.ck, required this.qrcode});
  final String t;
  final String ck;
  final String qrcode;
}

enum AliyunQrStatus { waiting, scanned, confirmed, expired, cancelled }

class AliyunQrResult {
  const AliyunQrResult(this.status, {this.refreshToken});
  final AliyunQrStatus status;
  final String? refreshToken;
}

class AliyunLoginClient {
  const AliyunLoginClient(this.client);
  final http.Client client;
  static const _host = 'passport.aliyundrive.com';
  static const _invalid = AliyunLoginException('阿里登录响应无效，请重新扫码');

  Future<Map<String, dynamic>> _request(String path,
      {Map<String, String>? body}) async {
    try {
      final uri = Uri.https(
          _host, '/newlogin/qrcode/$path.do', {'appName': 'aliyun_drive'});
      var visited = false;
      final response = await sendBoundedRequest(
          client, body == null ? 'GET' : 'POST', uri,
          body: body,
          headers: const {'Referer': 'https://www.aliyundrive.com/'},
          timeout: const Duration(seconds: 20),
          maxBytes: 128 * 1024, allowUri: (next) {
        if (visited) return false;
        visited = true;
        return next == uri;
      });
      if (response.statusCode != 200) {
        throw AliyunLoginException('阿里登录请求失败，请重新扫码',
            retryable: response.statusCode == 429 || response.statusCode >= 500);
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final content = decoded is Map ? decoded['content'] : null;
      if (content is! Map ||
          content['success'] != true ||
          content['data'] is! Map<String, dynamic>) {
        throw _invalid;
      }
      return content['data'] as Map<String, dynamic>;
    } on AliyunLoginException {
      rethrow;
    } catch (_) {
      throw const AliyunLoginException('阿里登录网络或响应异常，请重新扫码', retryable: true);
    }
  }

  Future<AliyunQrToken> createToken() async {
    final data = await _request('generate');
    final t = data['t'];
    final ck = data['ck'];
    final qr = data['codeContent'];
    if ((t is! int && t is! String) ||
        !RegExp(r'^[0-9]{1,20}$').hasMatch('$t') ||
        ck is! String ||
        ck.isEmpty ||
        ck.length > 4096 ||
        RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(ck) ||
        qr is! String ||
        qr.length > 4096 ||
        RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(qr)) {
      throw _invalid;
    }
    final uri = Uri.tryParse(qr);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != _host ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.path != '/qrcodeCheck.htm' ||
        !uri.hasQuery) {
      throw _invalid;
    }
    return AliyunQrToken(t: '$t', ck: ck, qrcode: qr);
  }

  Future<AliyunQrResult> status(AliyunQrToken token) async {
    final data = await _request('query', body: {'t': token.t, 'ck': token.ck});
    final status = switch (data['qrCodeStatus']) {
      'NEW' => AliyunQrStatus.waiting,
      'SCANED' => AliyunQrStatus.scanned,
      'CONFIRMED' => AliyunQrStatus.confirmed,
      'EXPIRED' => AliyunQrStatus.expired,
      'CANCELED' || 'CANCELLED' => AliyunQrStatus.cancelled,
      _ => throw _invalid,
    };
    if (status != AliyunQrStatus.confirmed) return AliyunQrResult(status);
    try {
      final encoded = data['bizExt'];
      if (encoded is! String || encoded.isEmpty || encoded.length > 96000) {
        throw _invalid;
      }
      final bytes = base64.decode(encoded);
      String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        text = gbk.decode(bytes);
      }
      final payload = jsonDecode(text);
      final login = payload is Map ? payload['pds_login_result'] : null;
      final refresh = login is Map ? login['refreshToken'] : null;
      if (refresh is! String ||
          refresh.isEmpty ||
          refresh.length > 8192 ||
          !RegExp(r'^[A-Za-z0-9._~+/=-]+$').hasMatch(refresh)) {
        throw _invalid;
      }
      return AliyunQrResult(status, refreshToken: refresh);
    } catch (_) {
      throw _invalid;
    }
  }
}
