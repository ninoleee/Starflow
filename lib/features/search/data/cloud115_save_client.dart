import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/features/search/application/cloud_save_planner.dart';
import 'package:starflow/features/search/application/cloud_saved_name_sanitizer.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/domain/cloud_save_rules.dart';
import 'package:starflow/features/search/domain/share_link_validation.dart';

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

class Cloud115SaveResult {
  const Cloud115SaveResult({
    required this.savedCount,
    required this.skippedCount,
    required this.targetFolderId,
    required this.targetFolderPath,
    this.savedEntries = const [],
  });

  final int savedCount;
  final int skippedCount;
  final String targetFolderId;
  final String targetFolderPath;
  final List<CloudSavedEntry> savedEntries;
}

class Cloud115SaveClient {
  Cloud115SaveClient(this._client);
  final http.Client _client;

  static const _userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/131.0.0.0 Safari/537.36';

  Map<String, String> _headers(String cookie) => {
        'Cookie': cookie.trim(),
        'Referer': 'https://115.com/',
        'Origin': 'https://115.com',
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      };

  String _operation(String path) => switch (path) {
        '/share/snap' => '读取分享目录',
        '/share/receive' => '提交转存',
        '/files/add' => '创建保存目录',
        '/files/batch_rename' => '修正保存名称',
        '/rb/delete' => '删除网盘文件',
        _ => '读取网盘目录',
      };

  String _httpFailure(String path, int status) {
    final message = '115 ${_operation(path)}失败（HTTP $status）';
    return status == 405
        ? '$message，请求被拒绝，可能涉及网关或风控。请先在 115 网页确认登录和分享可用，稍后再试；未自动重试'
        : message;
  }

  Future<ShareLinkValidationResult> validateShareLink({
    required String shareUrl,
    required String cookie,
    String password = '',
    Duration timeout = const Duration(seconds: 8),
  }) async {
    late final Cloud115ShareLink link;
    try {
      link = Cloud115ShareLink.parse(shareUrl);
    } on QuarkSaveException {
      return const ShareLinkValidationResult.unavailable('无法识别 115 分享地址');
    }
    if (cookie.trim().isEmpty) {
      return const ShareLinkValidationResult.unavailable('未配置 115 Cookie');
    }
    try {
      return await (() async {
        final request = http.Request(
          'GET',
          Uri.https('webapi.115.com', '/share/snap', {
            'share_code': link.code,
            'receive_code':
                link.password.isEmpty ? password.trim() : link.password,
            'cid': '0',
            'offset': '0',
            'limit': '1',
          }),
        )
          ..followRedirects = false
          ..headers.addAll(_headers(cookie));
        final response =
            await http.Response.fromStream(await _client.send(request));
        if (response.statusCode != 200) {
          return ShareLinkValidationResult.unavailable(
              _httpFailure('/share/snap', response.statusCode));
        }
        final payload = jsonDecode(utf8.decode(response.bodyBytes));
        if (payload is! Map<String, dynamic>) {
          return const ShareLinkValidationResult.unavailable('115 验证响应格式异常');
        }
        if (payload['state'] != true && payload['state'] != 1) {
          final message =
              '${payload['error'] ?? payload['message'] ?? payload['msg'] ?? ''}'
                  .trim()
                  .toLowerCase();
          // Only explicit share failures are permanent, never login or HTTP errors.
          for (final phrase in const [
            '分享已取消',
            '取消分享',
            '取消了分享',
            '分享被取消',
            '分享已被取消',
            '分享不存在',
            '分享已失效',
            '分享链接已失效',
            '分享已过期',
            '分享链接已过期',
            '分享已删除',
            '分享已被删除',
            '链接不存在',
            '链接已失效',
            '链接已过期',
            '接收码错误',
            '接收码不正确',
            '提取码错误',
            'share not found',
            'share expired',
            'share cancelled',
          ]) {
            if (message.contains(phrase)) {
              return ShareLinkValidationResult.invalid('115：$phrase');
            }
          }
          return const ShareLinkValidationResult.unavailable(
              '115 无法验证，请检查登录状态、接收码或稍后重试');
        }
        final data = payload['data'];
        if (data is! Map || data['list'] is! List) {
          return const ShareLinkValidationResult.unavailable('115 分享目录响应不完整');
        }
        final entries = data['list'] as List;
        final count = int.tryParse('${data['count']}');
        if (entries.isEmpty) {
          return count == 0
              ? const ShareLinkValidationResult.invalid('115 分享内容为空')
              : const ShareLinkValidationResult.unavailable('115 分享目录响应不完整');
        }
        if (count == 0 ||
            entries.any((entry) =>
                entry is! Map ||
                '${entry['fid'] ?? entry['cid'] ?? ''}'.trim().isEmpty)) {
          return const ShareLinkValidationResult.unavailable('115 分享文件信息不完整');
        }
        return const ShareLinkValidationResult.valid();
      })()
          .timeout(timeout);
    } on TimeoutException {
      return const ShareLinkValidationResult.unavailable('115 验证超时');
    } on FormatException {
      return const ShareLinkValidationResult.unavailable('115 验证响应格式异常');
    } catch (_) {
      return const ShareLinkValidationResult.unavailable('115 验证网络请求失败');
    }
  }

  Future<List<QuarkFileEntry>> listEntries(
      {required String cookie,
      String parentFid = '0',
      String parentPath = '/'}) async {
    final rows =
        await _list('/files', cookie, {'cid': parentFid, 'show_dir': '1'});
    return _parseEntries(rows, parentPath: parentPath);
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
      throw const QuarkSaveException('请先在网盘与转存设置里填写 115 Cookie');
    }
    final uri = Uri.https('webapi.115.com', path, post ? null : parameters);
    try {
      final request = http.Request(post ? 'POST' : 'GET', uri)
        ..followRedirects = false
        ..headers.addAll(_headers(cookie));
      if (post) request.bodyFields = parameters;
      final response = await (() async =>
              http.Response.fromStream(await _client.send(request)))()
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw QuarkSaveException(_httpFailure(path, response.statusCode));
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
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
      if (rows is! List || rows.any((row) => row is! Map<String, dynamic>)) {
        throw const QuarkSaveException('115 目录列表无效');
      }
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

  Future<Cloud115SaveResult> saveShareLink(
      {required String shareUrl,
      required String cookie,
      String folderId = '0',
      String folderPath = '/',
      String saveFolderName = '',
      String sanitizedNameCharacters = '',
      String password = ''}) async {
    final link = Cloud115ShareLink.parse(shareUrl);
    final parameters = {
      'share_code': link.code,
      'receive_code': link.password.isEmpty ? password.trim() : link.password
    };
    final entries = await _shareEntries(cookie, parameters, '0');
    if (entries.isEmpty) throw const QuarkSaveException('115 分享中没有可保存的内容');

    final targetId = folderId.trim().isEmpty ? '0' : folderId.trim();
    if (!RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(targetId)) {
      throw const QuarkSaveException('115 保存目录 ID 无效，请重新选择目录');
    }
    final planner = _savePlanner(cookie, parameters);
    final plan = await planner.build(
      entries: entries,
      folderId: targetId,
      folderPath: folderPath,
      saveFolderName: saveFolderName,
      sanitizedNameCharacters: sanitizedNameCharacters,
    );
    final savedEntries = sanitizedNameCharacters.trim().isEmpty
        ? const <CloudSavedEntry>[]
        : await planner.trackNewEntries(plan.batches, captureTree: true);
    var savedCount = 0;
    for (final batch in plan.batches) {
      try {
        // Do not retry mutations: a lost response can still mean success.
        await _request(
            '/share/receive',
            cookie,
            {
              ...parameters,
              'file_id': batch.entries.map((entry) => entry.fid).join(','),
              'cid': batch.targetDirectoryFid,
            },
            post: true);
      } catch (error) {
        final reason =
            error is QuarkSaveException ? error.message : '115 转存请求异常';
        throw QuarkSaveException(
            '${savedCount > 0 ? '115 转存部分完成，已确认保存 $savedCount 个文件或目录；' : ''}'
            '$reason；当前批次结果未确认，请先检查网盘再重试');
      }
      savedCount += batch.entries.length;
    }
    return Cloud115SaveResult(
      savedCount: savedCount,
      skippedCount: plan.skippedCount,
      targetFolderId: plan.targetFolderId,
      targetFolderPath: plan.targetFolderPath,
      savedEntries: List.unmodifiable(savedEntries),
    );
  }

  Future<CloudSavePreview> previewSave({
    required String shareUrl,
    required String cookie,
    String folderId = '0',
    String folderPath = '/',
    String saveFolderName = '',
    String sanitizedNameCharacters = '',
    String password = '',
  }) async {
    final targetId = folderId.trim().isEmpty ? '0' : folderId.trim();
    if (!RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(targetId)) {
      throw const CloudSaveException('115 保存目录 ID 无效，请重新选择目录');
    }
    final link = Cloud115ShareLink.parse(shareUrl);
    final parameters = {
      'share_code': link.code,
      'receive_code': link.password.isEmpty ? password.trim() : link.password
    };
    final entries = await _shareEntries(cookie, parameters, '0');
    if (entries.isEmpty) throw const CloudSaveException('115 分享中没有可保存的内容');
    return _savePlanner(cookie, parameters).preview(
        entries: entries,
        folderId: targetId,
        folderPath: folderPath,
        saveFolderName: saveFolderName,
        sanitizedNameCharacters: sanitizedNameCharacters);
  }

  CloudSavePlanner<QuarkFileEntry> _savePlanner(
          String cookie, Map<String, String> parameters) =>
      CloudSavePlanner<QuarkFileEntry>(
        driveName: '115',
        maxDepth: 25,
        listShared: (id) => _shareEntries(cookie, parameters, id),
        listStored: (id) => listEntries(cookie: cookie, parentFid: id),
        createDirectory: (parentId, name) async {
          final created = await _request(
              '/files/add',
              cookie,
              {
                'pid': parentId,
                'cname': name,
              },
              post: true);
          final createdId = '${created['cid'] ?? ''}'.trim();
          if (!RegExp(r'^[1-9][0-9]*$').hasMatch(createdId) ||
              createdId == parentId) {
            throw const QuarkSaveException(
                '115 创建保存目录后未返回有效目录 ID，未提交转存；请先检查网盘再重试');
          }
          return createdId;
        },
      );

  Future<List<QuarkFileEntry>> _shareEntries(
      String cookie, Map<String, String> parameters, String folderId) async {
    final rows = await _list(
        '/share/snap', cookie, {...parameters, 'cid': folderId},
        share: true);
    return _parseEntries(rows);
  }

  List<QuarkFileEntry> _parseEntries(List<Map<String, dynamic>> rows,
      {String parentPath = '/'}) {
    final entries = <QuarkFileEntry>[];
    final seenIds = <String>{};
    for (final row in rows) {
      final fileId = '${row['fid'] ?? ''}'.trim();
      final id = fileId.isEmpty ? '${row['cid'] ?? ''}'.trim() : fileId;
      if (!RegExp(r'^[1-9][0-9]*$').hasMatch(id) || !seenIds.add(id)) {
        throw const QuarkSaveException('115 目录文件标识不完整或重复，已停止操作');
      }
      final name = '${row['n'] ?? ''}';
      entries.add(QuarkFileEntry(
        fid: id,
        name: name,
        path: cloudChildPath(parentPath, name),
        isDirectory: fileId.isEmpty,
        extension: name.contains('.') ? name.split('.').last : '',
      ));
    }
    return entries;
  }

  Future<void> renameEntry(
      {required String cookie,
      required String fid,
      required String name}) async {
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(fid) ||
        name.trim().isEmpty ||
        name == '.' ||
        name == '..') {
      throw const CloudSaveException('115 改名目标无效');
    }
    await _request(
        '/files/batch_rename', cookie, {'files_new_name[$fid]': name},
        post: true);
  }

  Future<CloudNameSanitizeResult> sanitizeSavedEntries({
    required String cookie,
    required List<CloudSavedEntry> savedEntries,
    required String characters,
  }) =>
      CloudSavedNameSanitizer(
        listEntries: (id) => listEntries(cookie: cookie, parentFid: id),
        renameEntry: (id, name) =>
            renameEntry(cookie: cookie, fid: id, name: name),
        visibilityAttempts: 3,
        verifyRenames: true,
      ).sanitize(savedEntries: savedEntries, characters: characters);
}
