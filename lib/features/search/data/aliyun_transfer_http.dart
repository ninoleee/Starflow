import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:starflow/core/network/bounded_http_request.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';

/// A transfer request never follows redirects or retries a mutation.
Future<http.Response> transferRequest(
    http.Client client, String method, Uri uri,
    {Map<String, String>? headers,
    Object? body,
    int maxBytes = 2 * 1024 * 1024}) async {
  var visited = false;
  try {
    return await sendBoundedRequest(client, method, uri,
        headers: headers,
        body: body,
        maxBytes: maxBytes,
        timeout: const Duration(seconds: 30), allowUri: (next) {
      if (visited) return false;
      visited = true;
      return next == uri && uri.scheme == 'https' && uri.userInfo.isEmpty;
    });
  } catch (_) {
    throw const QuarkSaveException('转存网络响应未确认，未自动重试；阿里副本保留');
  }
}

Map<String, dynamic> transferJson(http.Response response, String service) {
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw QuarkSaveException(
        '$service 请求失败（HTTP ${response.statusCode}），请检查登录或风控状态');
  }
  try {
    final value = jsonDecode(utf8.decode(response.bodyBytes));
    if (value is Map<String, dynamic>) return value;
  } catch (_) {}
  throw QuarkSaveException('$service 返回格式异常，结果未确认');
}
