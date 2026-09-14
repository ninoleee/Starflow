import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/network/starflow_http_transport.dart';

// Login URLs and responses contain session secrets. Do not use HTTP logging.
final cloud115LoginClientProvider = Provider((ref) {
  final transport = createStarflowTransportClient();
  ref.onDispose(transport.close);
  return Cloud115LoginClient(transport);
});

class Cloud115LoginException implements Exception {
  const Cloud115LoginException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Cloud115QrToken {
  const Cloud115QrToken(
      {required this.uid,
      required this.time,
      required this.sign,
      required this.qrcode});
  final String uid;
  final String time;
  final String sign;
  final String qrcode;
}

enum Cloud115QrStatus { waiting, scanned, confirmed, expired, cancelled }

class Cloud115LoginClient {
  const Cloud115LoginClient(this.client);
  final http.Client client;

  Future<Map<String, dynamic>> _request(Uri uri,
      {Map<String, String>? body}) async {
    try {
      final request = http.Request(body == null ? 'GET' : 'POST', uri)
        ..followRedirects = false;
      if (body != null) request.bodyFields = body;
      final response = await (() async =>
              http.Response.fromStream(await client.send(request)))()
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw const Cloud115LoginException('115 登录请求失败，请重试');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map ||
          decoded['state'] == false ||
          decoded['data'] is! Map) {
        throw const Cloud115LoginException('115 登录响应无效，请重新获取二维码');
      }
      return Map<String, dynamic>.from(decoded['data'] as Map);
    } on Cloud115LoginException {
      rethrow;
    } catch (_) {
      throw const Cloud115LoginException('115 登录网络异常，请重新获取二维码');
    }
  }

  Future<Cloud115QrToken> createToken() async {
    final data = await _request(
        Uri.https('qrcodeapi.115.com', '/api/1.0/web/1.0/token/'));
    String field(String key) => '${data[key] ?? ''}'.trim();
    if (['uid', 'time', 'sign', 'qrcode'].any((key) => field(key).isEmpty)) {
      throw const Cloud115LoginException('115 二维码信息不完整');
    }
    return Cloud115QrToken(
        uid: field('uid'),
        time: field('time'),
        sign: field('sign'),
        qrcode: field('qrcode'));
  }

  Future<Cloud115QrStatus> status(Cloud115QrToken token) async {
    final data = await _request(Uri.https('qrcodeapi.115.com', '/get/status/', {
      'uid': token.uid,
      'time': token.time,
      'sign': token.sign,
    }));
    return switch ('${data['status']}') {
      '0' => Cloud115QrStatus.waiting,
      '1' => Cloud115QrStatus.scanned,
      '2' => Cloud115QrStatus.confirmed,
      '-1' => Cloud115QrStatus.expired,
      '-2' => Cloud115QrStatus.cancelled,
      _ => throw const Cloud115LoginException('115 登录状态异常，请重新扫码'),
    };
  }

  Future<String> exchange(Cloud115QrToken token) async {
    final data = await _request(
        Uri.https('passportapi.115.com', '/app/1.0/web/1.0/login/qrcode/'),
        body: {'account': token.uid});
    final cookie = data['cookie'];
    if (cookie is! Map ||
        ['UID', 'CID', 'SEID'].any((key) => '${cookie[key] ?? ''}'.isEmpty)) {
      throw const Cloud115LoginException('115 未返回完整登录凭据');
    }
    final entries = <String>[];
    for (final entry in cookie.entries) {
      final name = '${entry.key}';
      final value = '${entry.value}';
      if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(name) ||
          RegExp(r'[;\r\n]').hasMatch(value)) {
        throw const Cloud115LoginException('115 登录凭据格式无效');
      }
      entries.add('$name=$value');
    }
    return entries.join('; ');
  }
}
