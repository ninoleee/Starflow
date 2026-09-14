import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/domain/share_link_validation.dart';

http.Response _response(Object data) => http.Response.bytes(
      utf8.encode(jsonEncode(data)),
      200,
      headers: {'content-type': 'application/json'},
    );

void main() {
  for (final host in ['115.com', '115cdn.com', 'anxia.com']) {
    for (final embedded in [false, true]) {
      test('read-only validation supports $host embedded password=$embedded',
          () async {
        var calls = 0;
        final client = Cloud115SaveClient(MockClient((request) async {
          calls++;
          expect(request.method, 'GET');
          expect(request.url.host, 'webapi.115.com');
          expect(request.url.path, '/share/snap');
          expect(request.followRedirects, isFalse);
          expect(request.headers['cookie'], 'UID=test;');
          expect(request.url.queryParameters, {
            'share_code': 'abc123',
            'receive_code': embedded ? 'url-code' : 'separate',
            'cid': '0',
            'offset': '0',
            'limit': '1',
          });
          return _response({
            'state': true,
            'data': {
              'count': 2000,
              'list': [
                {'cid': '123'}
              ]
            },
          });
        }));
        final result = await client.validateShareLink(
          shareUrl:
              'https://$host/s/abc123${embedded ? '?password=url-code' : ''}',
          password: 'separate',
          cookie: 'UID=test;',
        );
        expect(result.isValid, isTrue);
        expect(calls, 1);
      });
    }
  }

  for (final message in [
    '好友已取消了分享',
    '分享已取消',
    '分享已过期',
    '分享链接已失效',
    '分享不存在',
    '分享已被删除',
    '接收码错误',
    '接收码不正确',
  ]) {
    test('excludes explicit share failure: $message', () async {
      final client = Cloud115SaveClient(MockClient(
          (_) async => _response({'state': false, 'error': message})));
      final result = await client.validateShareLink(
          shareUrl: 'https://115cdn.com/s/abc123', cookie: 'test');
      expect(result.isInvalid, isTrue);
    });
  }

  for (final message in [
    '登录已过期',
    '请重新登录',
    '请求过于频繁',
    '系统繁忙',
    '未知错误',
  ]) {
    test('keeps uncertain failure: $message', () async {
      final client = Cloud115SaveClient(MockClient(
          (_) async => _response({'state': false, 'message': message})));
      final result = await client.validateShareLink(
          shareUrl: 'https://115cdn.com/s/abc123', cookie: 'test');
      expect(result.status, ShareLinkValidationStatus.unavailable);
    });
  }

  for (final status in [302, 401, 403, 404, 410, 429, 500]) {
    test('HTTP $status alone does not prove a dead share', () async {
      final client = Cloud115SaveClient(
          MockClient((_) async => http.Response('upstream error', status)));
      final result = await client.validateShareLink(
          shareUrl: 'https://115cdn.com/s/abc123', cookie: 'test');
      expect(result.status, ShareLinkValidationStatus.unavailable);
    });
  }

  test('only a confirmed empty directory is invalid', () async {
    for (final data in [
      {'count': 0, 'list': []},
      {'count': 1, 'list': []},
      {'list': []},
      {'count': 1},
      {
        'count': 1,
        'list': [{}]
      },
    ]) {
      final client = Cloud115SaveClient(
          MockClient((_) async => _response({'state': true, 'data': data})));
      final result = await client.validateShareLink(
          shareUrl: 'https://115cdn.com/s/abc123', cookie: 'test');
      expect(
          result.status,
          data['count'] == 0
              ? ShareLinkValidationStatus.invalid
              : ShareLinkValidationStatus.unavailable);
    }
  });

  test('missing cookie or unsupported host never sends a request', () async {
    final client = Cloud115SaveClient(MockClient((_) async =>
        fail('Must not forward credentials or send an anonymous probe')));
    for (final input in [
      (url: 'https://115cdn.com/s/abc123', cookie: ''),
      (url: 'https://115cdn.com.evil.test/s/abc123', cookie: 'test'),
    ]) {
      final result = await client.validateShareLink(
          shareUrl: input.url, cookie: input.cookie);
      expect(result.status, ShareLinkValidationStatus.unavailable);
    }
  });

  test('timeout and malformed JSON remain unverified', () async {
    final pending = Completer<http.Response>();
    final client = Cloud115SaveClient(MockClient((_) => pending.future));
    final result = await client.validateShareLink(
      shareUrl: 'https://115cdn.com/s/abc123',
      cookie: 'test',
      timeout: const Duration(milliseconds: 1),
    );
    expect(result.status, ShareLinkValidationStatus.unavailable);
    expect(result.reason, contains('超时'));
    pending.complete(http.Response('<html>login</html>', 200));
    final malformed = await Cloud115SaveClient(
            MockClient((_) async => http.Response('<html>login</html>', 200)))
        .validateShareLink(
            shareUrl: 'https://115cdn.com/s/abc123', cookie: 'test');
    expect(malformed.status, ShareLinkValidationStatus.unavailable);
  });
}
