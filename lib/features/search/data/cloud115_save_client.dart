import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';

final cloud115SaveClientProvider = Provider<Cloud115SaveClient>((ref) {
  return Cloud115SaveClient(ref.watch(starflowHttpClientProvider));
});

class Cloud115ShareLink {
  const Cloud115ShareLink(this.code, this.password);
  final String code;
  final String password;

  static Cloud115ShareLink parse(String raw) {
    final match = RegExp(r'https?://[^\s<>]+').firstMatch(raw);
    final uri = Uri.tryParse(match?.group(0) ?? raw.trim());
    final host = uri?.host.toLowerCase();
    if (uri == null ||
        !{
          '115.com',
          'www.115.com',
          '115cdn.com',
          'www.115cdn.com',
          'anxia.com',
          'www.anxia.com'
        }.contains(host) ||
        uri.pathSegments.length != 2 ||
        uri.pathSegments.first != 's' ||
        !RegExp(r'^[a-zA-Z0-9]+$').hasMatch(uri.pathSegments.last)) {
      throw const QuarkSaveException('不是可识别的 115 分享链接');
    }
    final password = uri.queryParameters['password'] ??
        RegExp(r'(?:提取码|访问码|接收码)\s*[:：]?\s*([a-zA-Z0-9]+)')
            .firstMatch(raw)
            ?.group(1) ??
        '';
    return Cloud115ShareLink(uri.pathSegments.last, password);
  }
}

class Cloud115SaveClient {
  Cloud115SaveClient(this._client);
  final http.Client _client;

  Future<List<QuarkFileEntry>> listEntries(
      {required String cookie,
      String parentFid = '0',
      String parentPath = '/'}) async {
    final rows =
        await _list('/files', cookie, {'cid': parentFid, 'show_dir': '1'});
    return rows
        .map((row) => QuarkFileEntry(
              fid: '${row['fid'] ?? row['cid'] ?? ''}',
              name: '${row['n'] ?? ''}',
              path: '${parentPath == '/' ? '' : parentPath}/${row['n'] ?? ''}',
              isDirectory: row['fid'] == null,
              extension: '${row['n'] ?? ''}'.contains('.')
                  ? '${row['n']}'.split('.').last
                  : '',
            ))
        .toList();
  }

  Future<void> deleteEntries(
      {required String cookie,
      required String parentId,
      required List<String> fids}) async {
    if (fids.isEmpty) return;
    if (fids.any(
        (id) => !RegExp(r'^[1-9][0-9]*$').hasMatch(id) || id == parentId)) {
      throw const QuarkSaveException('115 删除目标无效，不能删除根目录或当前目录');
    }
    await _request(
        '/rb/delete',
        cookie,
        {
          'pid': parentId,
          for (var i = 0; i < fids.length; i++) 'fid[$i]': fids[i],
        },
        post: true);
  }

  Future<Map<String, dynamic>> _request(
      String path, String cookie, Map<String, String> parameters,
      {bool post = false}) async {
    if (cookie.trim().isEmpty) {
      throw const QuarkSaveException('请先在网络存储设置里填写 115 Cookie');
    }
    final uri = Uri.https('webapi.115.com', path, post ? null : parameters);
    final headers = {
      'Cookie': cookie.trim(),
      'Referer': 'https://115.com/',
      'User-Agent': 'Mozilla/5.0',
      'Accept': 'application/json'
    };
    try {
      final response = await (post
              ? _client.post(uri, headers: headers, body: parameters)
              : _client.get(uri, headers: headers))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw QuarkSaveException('115 请求失败（HTTP ${response.statusCode}）');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException();
      }
      if (decoded['state'] != true && decoded['state'] != 1) {
        final message =
            decoded['error'] ?? decoded['message'] ?? decoded['msg'];
        throw QuarkSaveException(
            '115：${message ?? '请求失败，请检查 Cookie、接收码或分享状态'}');
      }
      return decoded;
    } on TimeoutException {
      throw const QuarkSaveException('115 请求超时；写操作可能已提交，请检查网盘后再重试');
    } on FormatException {
      throw const QuarkSaveException('115 返回了无法识别的响应，请检查登录状态');
    } on http.ClientException {
      throw const QuarkSaveException('115 网络请求失败，请检查网络后重试');
    }
  }

  Future<List<Map<String, dynamic>>> _list(
      String path, String cookie, Map<String, String> parameters,
      {bool share = false}) async {
    final entries = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final response = await _request(path, cookie, {
        ...parameters,
        'offset': '$offset',
        'limit': '1000',
      });
      final container = share ? response['data'] : response;
      if (container is! Map) throw const QuarkSaveException('115 目录响应不完整');
      final rows = container[share ? 'list' : 'data'];
      if (rows is! List) throw const QuarkSaveException('115 目录列表无效');
      final page =
          rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
      entries.addAll(page);
      offset += page.length;
      final count = int.tryParse('${container['count']}');
      if (count != null && offset >= count) break;
      if (page.isEmpty && count != null && offset < count) {
        throw const QuarkSaveException('115 目录分页不完整，未提交转存');
      }
      if (page.isEmpty || (count == null && page.length < 1000)) break;
      if (offset > 100000) throw const QuarkSaveException('115 目录过大，请选择较小的分享');
    }
    return entries;
  }

  Future<List<QuarkDirectoryEntry>> listDirectories(
      {required String cookie,
      String parentFid = '0',
      String parentPath = '/'}) async {
    final rows = await _list('/files', cookie, {
      'cid': parentFid,
      'show_dir': '1',
      'o': 'file_name',
      'asc': '1',
    });
    return rows
        .where((row) => row['fid'] == null && row['cid'] != null)
        .map((row) => QuarkDirectoryEntry(
            fid: '${row['cid']}',
            name: '${row['n']}',
            path: '${parentPath == '/' ? '' : parentPath}/${row['n']}'))
        .toList();
  }

  Future<int> saveShareLink(
      {required String shareUrl,
      required String cookie,
      String folderId = '0',
      String password = ''}) async {
    final link = Cloud115ShareLink.parse(shareUrl);
    final parameters = {
      'share_code': link.code,
      'receive_code': link.password.isEmpty ? password.trim() : link.password
    };
    final entries = await _list(
        '/share/snap', cookie, {...parameters, 'cid': '0'},
        share: true);
    if (entries.isEmpty) throw const QuarkSaveException('115 分享中没有可保存的内容');
    final ids =
        entries.map((row) => '${row['fid'] ?? row['cid'] ?? ''}').toList();
    if (ids.any((id) => id.isEmpty)) {
      throw const QuarkSaveException('115 分享文件标识不完整，未提交转存');
    }
    // Do not retry this mutation: a lost response can still mean it succeeded.
    await _request(
        '/share/receive',
        cookie,
        {
          ...parameters,
          'file_id': ids.join(','),
          'cid': folderId,
        },
        post: true);
    return ids.length;
  }
}
