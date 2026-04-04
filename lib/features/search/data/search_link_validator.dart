import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final searchLinkValidatorProvider = Provider<SearchLinkValidator>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return SearchLinkValidator(client);
});

class SearchLinkValidator {
  SearchLinkValidator(this._client);

  final http.Client _client;
  final Map<String, bool> _cache = <String, bool>{};
  final Map<String, Future<bool>> _inflight = <String, Future<bool>>{};

  static const _requestHeaders = <String, String>{
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,application/json;q=0.8,*/*;q=0.7',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.6',
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
    'User-Agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1 Starflow/1.0',
  };

  static const _invalidMarkers = <String>[
    '来晚了',
    '分享已失效',
    '链接已失效',
    '链接不存在',
    '内容不存在',
    '资源不存在',
    '文件不存在',
    '文件已删除',
    '分享的文件已经被删除',
    '分享的文件已经被取消',
    '该分享已失效',
    '已取消分享',
    '页面不存在',
    '404 not found',
    'not found',
    'share has been canceled',
    'the share does not exist',
    'sorry, the page you visited does not exist',
  ];

  Future<bool> hasFiles(String rawUrl) {
    final url = rawUrl.trim();
    if (url.isEmpty) {
      return Future.value(false);
    }
    final cached = _cache[url];
    if (cached != null) {
      return Future.value(cached);
    }
    final inFlight = _inflight[url];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _probe(url);
    _inflight[url] = future;
    return future.whenComplete(() {
      _inflight.remove(url);
    });
  }

  Future<bool> _probe(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.hasScheme) {
      _cache[rawUrl] = false;
      return false;
    }

    try {
      final response = await _client
          .get(uri, headers: _requestHeaders)
          .timeout(const Duration(seconds: 6));
      final valid = _isResponseValid(response);
      _cache[rawUrl] = valid;
      return valid;
    } catch (_) {
      _cache[rawUrl] = false;
      return false;
    }
  }

  bool _isResponseValid(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 400) {
      return false;
    }

    final body = response.body.trim().toLowerCase();
    if (body.isEmpty) {
      return true;
    }

    for (final marker in _invalidMarkers) {
      if (body.contains(marker)) {
        return false;
      }
    }
    return true;
  }
}
