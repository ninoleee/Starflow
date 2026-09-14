import 'dart:async';
import 'dart:convert';
import 'package:starflow/features/search/domain/share_link_validation.dart';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/features/search/application/cloud_save_planner.dart';
import 'package:starflow/features/search/application/cloud_saved_name_sanitizer.dart';
import 'package:starflow/features/search/domain/cloud_save_rules.dart';

final quarkSaveClientProvider = Provider<QuarkSaveClient>((ref) {
  final client = ref.watch(starflowHttpClientProvider);
  return QuarkSaveClient(client);
});

String normalizeQuarkDirectoryPath(String rawPath) =>
    normalizeCloudDirectoryPath(rawPath);

String sanitizeQuarkDirectoryName(String rawName) =>
    sanitizeCloudDirectoryName(rawName);

/// Characters that survive the drive but break URL-addressed playback.
///
/// `#` opens a fragment, `?` opens a query and `%` opens a percent-escape, so a
/// path segment containing one can be truncated or re-encoded before the
/// request reaches the file — and any signature computed over the original path
/// then fails to match.
const String kQuarkUnsafeUrlNameCharacters = kCloudUnsafeUrlNameCharacters;

/// Strips [characters] out of [rawName], collapsing the whitespace they leave
/// behind. Returns an empty string when nothing usable remains, which callers
/// treat as "leave this entry alone".
String sanitizeQuarkNameForUrl(
  String rawName, {
  String characters = kQuarkUnsafeUrlNameCharacters,
}) =>
    sanitizeCloudNameForUrl(rawName, characters: characters);

class QuarkSaveClient {
  QuarkSaveClient(this._client);

  static const _baseUrl = 'https://drive-pc.quark.cn';
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) quark-cloud-drive/3.14.2 Chrome/112.0.5615.165 '
      'Electron/24.1.3.8 Safari/537.36 Channel/pckk_other_ch';

  final http.Client _client;

  Future<QuarkShareValidationResult> validateShareLink({
    required String shareUrl,
    required String cookie,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final parsed = _parseShareUrl(shareUrl);
    if (parsed == null) {
      return const QuarkShareValidationResult.invalid('不是可识别的夸克分享链接');
    }
    final trimmedCookie = cookie.trim();
    if (trimmedCookie.isEmpty) {
      return const QuarkShareValidationResult.unavailable('未配置夸克 Cookie');
    }

    try {
      await (() async {
        final stoken = await _fetchShareToken(
          pwdId: parsed.pwdId,
          passcode: parsed.passcode,
          cookie: trimmedCookie,
        );
        await _validateShareDetail(
          pwdId: parsed.pwdId,
          stoken: stoken,
          pdirFid: parsed.pdirFid,
          cookie: trimmedCookie,
        );
      })()
          .timeout(timeout);
      return const QuarkShareValidationResult.valid();
    } on QuarkSaveException catch (error) {
      if (_isPermanentlyInvalidShareMessage(error.message)) {
        return QuarkShareValidationResult.invalid(error.message);
      }
      return QuarkShareValidationResult.unavailable(error.message);
    } on TimeoutException {
      return const QuarkShareValidationResult.unavailable('验证超时');
    } catch (error) {
      return QuarkShareValidationResult.unavailable('$error');
    }
  }

  Future<QuarkSaveResult> saveShareLink({
    required String shareUrl,
    required String cookie,
    String toPdirFid = '0',
    String toPdirPath = '/',
    String saveFolderName = '',

    /// Non-empty when saved directories will be sanitised afterwards, so that
    /// deduplication compares the names the drive will actually end up with.
    String sanitizedNameCharacters = '',
  }) async {
    final trimmedCookie = cookie.trim();
    if (trimmedCookie.isEmpty) {
      throw const QuarkSaveException('请先在网盘与转存设置里填写夸克 Cookie');
    }

    final parsed = _parseShareUrl(shareUrl);
    if (parsed == null) {
      throw const QuarkSaveException('不是可识别的夸克分享链接');
    }

    final stoken = await _fetchShareToken(
      pwdId: parsed.pwdId,
      passcode: parsed.passcode,
      cookie: trimmedCookie,
    );
    final sharedEntries = await _fetchShareEntries(
      pwdId: parsed.pwdId,
      stoken: stoken,
      pdirFid: parsed.pdirFid,
      cookie: trimmedCookie,
    );
    if (sharedEntries.isEmpty) {
      throw const QuarkSaveException('分享链接里没有可保存的文件');
    }

    final planner = _savePlanner(parsed.pwdId, stoken, trimmedCookie);
    final savePlan = await planner.build(
      entries: sharedEntries,
      folderId: toPdirFid,
      folderPath: toPdirPath,
      saveFolderName: saveFolderName,
      sanitizedNameCharacters: sanitizedNameCharacters,
    );
    final resolvedTargetDirectoryId = savePlan.targetFolderId;
    final resolvedTargetDirectoryPath = savePlan.targetFolderPath;
    if (savePlan.batches.isEmpty) {
      return QuarkSaveResult(
        taskId: '',
        savedCount: 0,
        skippedCount: savePlan.skippedCount,
        targetFolderPath: resolvedTargetDirectoryPath,
        targetFolderId: resolvedTargetDirectoryId,
      );
    }

    final taskIds = <String>[];
    final savedEntries = sanitizedNameCharacters.trim().isNotEmpty
        ? await planner.trackNewEntries(savePlan.batches)
        : <QuarkSavedEntry>[
            for (final batch in savePlan.batches)
              for (final entry in batch.entries)
                QuarkSavedEntry(
                    parentFid: batch.targetDirectoryFid,
                    name: entry.name,
                    isDirectory: entry.isDirectory),
          ];
    var savedCount = 0;
    for (final batch in savePlan.batches) {
      if (batch.entries.isEmpty) {
        continue;
      }
      final taskId = await _saveShareEntries(
        pwdId: parsed.pwdId,
        stoken: stoken,
        cookie: trimmedCookie,
        targetDirectoryFid: batch.targetDirectoryFid,
        entries: batch.entries,
      );
      if (taskId.isNotEmpty) {
        taskIds.add(taskId);
      }
      savedCount += batch.entries.length;
    }

    // Quark copies in the background, so the entries are not listable the
    // instant the task is submitted. Anything that inspects what was just
    // saved — renaming it, for one — has to wait for the task to finish first.
    var settled = taskIds.isEmpty;
    if (sanitizedNameCharacters.trim().isNotEmpty && taskIds.isNotEmpty) {
      settled = true;
      for (final taskId in taskIds) {
        try {
          await _waitForTask(
            cookie: trimmedCookie,
            taskId: taskId,
            taskLabel: '转存',
          );
        } on QuarkSaveException {
          // The files were submitted successfully; a stalled or failed status
          // poll must not fail the save. Report it so callers can skip the
          // follow-up work that depends on the entries being listable.
          settled = false;
        }
      }
    }

    return QuarkSaveResult(
      taskId: taskIds.length == 1 ? taskIds.single : '',
      savedCount: savedCount,
      skippedCount: savePlan.skippedCount,
      targetFolderPath: resolvedTargetDirectoryPath,
      targetFolderId: resolvedTargetDirectoryId,
      savedEntries: List<QuarkSavedEntry>.unmodifiable(savedEntries),
      savedEntriesSettled: settled,
    );
  }

  Future<QuarkSharePreview> previewShareLink({
    required String shareUrl,
    required String cookie,
    String toPdirPath = '/',
    String saveFolderName = '',
  }) async {
    final trimmedCookie = cookie.trim();
    if (trimmedCookie.isEmpty) {
      throw const QuarkSaveException('请先在网盘与转存设置里填写夸克 Cookie');
    }

    final parsed = _parseShareUrl(shareUrl);
    if (parsed == null) {
      throw const QuarkSaveException('不是可识别的夸克分享链接');
    }

    final stoken = await _fetchShareToken(
      pwdId: parsed.pwdId,
      passcode: parsed.passcode,
      cookie: trimmedCookie,
    );
    final sharedEntries = await _fetchShareEntries(
      pwdId: parsed.pwdId,
      stoken: stoken,
      pdirFid: parsed.pdirFid,
      cookie: trimmedCookie,
    );
    if (sharedEntries.isEmpty) {
      throw const QuarkSaveException('分享链接里没有可保存的文件');
    }

    final sanitizedFolderName = sanitizeQuarkDirectoryName(saveFolderName);
    final effectiveSharedEntries = sanitizedFolderName.isEmpty
        ? sharedEntries
        : await _savePlanner(parsed.pwdId, stoken, trimmedCookie)
            .flattenTopDirectory(sharedEntries);

    final previewEntries = await _collectSharePreviewEntries(
      pwdId: parsed.pwdId,
      stoken: stoken,
      cookie: trimmedCookie,
      entries: effectiveSharedEntries,
    );
    return QuarkSharePreview(
      targetFolderPath: _resolveQuarkTargetFolderPath(
        toPdirPath: toPdirPath,
        saveFolderName: saveFolderName,
      ),
      entries: previewEntries,
    );
  }

  Future<CloudSavePreview> previewSave({
    required String shareUrl,
    required String cookie,
    String folderId = '0',
    String folderPath = '/',
    String saveFolderName = '',
    String sanitizedNameCharacters = '',
  }) async {
    if (cookie.trim().isEmpty) {
      throw const QuarkSaveException('请先在网盘与转存设置中填写夸克 Cookie');
    }
    final parsed = _parseShareUrl(shareUrl);
    if (parsed == null) throw const QuarkSaveException('不是可识别的夸克分享链接');
    final stoken = await _fetchShareToken(
        pwdId: parsed.pwdId, passcode: parsed.passcode, cookie: cookie);
    final entries = await _fetchShareEntries(
        pwdId: parsed.pwdId,
        stoken: stoken,
        pdirFid: parsed.pdirFid,
        cookie: cookie);
    if (entries.isEmpty) throw const QuarkSaveException('分享链接里没有可保存的文件');
    return _savePlanner(parsed.pwdId, stoken, cookie).preview(
        entries: entries,
        folderId: folderId,
        folderPath: folderPath,
        saveFolderName: saveFolderName,
        sanitizedNameCharacters: sanitizedNameCharacters);
  }

  Future<QuarkConnectionStatus> testConnection({
    required String cookie,
  }) async {
    final directories = await listDirectories(
      cookie: cookie,
      parentFid: '0',
    );
    return QuarkConnectionStatus(rootDirectoryCount: directories.length);
  }

  Future<List<QuarkFileEntry>> listEntries({
    required String cookie,
    String parentFid = '0',
  }) async {
    final entries = <QuarkFileEntry>[];
    final ids = <String>{};
    for (var page = 1; page <= 500; page++) {
      final payload = await _listEntriesPage(cookie, parentFid, page);
      final data = payload['data'];
      final rows = data is Map ? data['list'] : null;
      if (rows is! List) throw const QuarkSaveException('夸克目录响应不完整');
      for (final row in rows) {
        final entry =
            row is Map<String, dynamic> ? QuarkFileEntry.fromJson(row) : null;
        if (entry == null || !ids.add(entry.fid)) {
          throw const QuarkSaveException('夸克目录文件信息不完整或重复');
        }
        entries.add(entry);
      }
      final metadata = payload['metadata'];
      final total =
          metadata is Map ? int.tryParse('${metadata['_total']}') : null;
      if (total != null && entries.length >= total) return entries;
      if (rows.isEmpty && total != null && entries.length < total) {
        throw const QuarkSaveException('夸克目录分页不完整，已停止操作');
      }
      if (rows.isEmpty || (total == null && rows.length < 200)) return entries;
    }
    throw const QuarkSaveException('夸克目录过大，已停止操作');
  }

  Future<Map<String, dynamic>> _listEntriesPage(
      String cookie, String parentFid, int page) async {
    final trimmedCookie = cookie.trim();
    if (trimmedCookie.isEmpty) {
      throw const QuarkSaveException('请先填写夸克 Cookie');
    }

    final response = await _client.get(
      Uri.parse('$_baseUrl/1/clouddrive/file/sort').replace(
        queryParameters: {
          'pr': 'ucpro',
          'fr': 'pc',
          'uc_param_str': '',
          // Quark folder listings can otherwise lag behind recent saves.
          '__dt': '${(math.Random().nextDouble() * 4 + 1).round() * 60 * 1000}',
          '__t': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
          'pdir_fid': parentFid,
          '_page': '$page',
          '_size': '200',
          '_fetch_total': '1',
          '_fetch_sub_dirs': '0',
          '_sort': 'file_type:asc,updated_at:desc',
          '_fetch_full_path': '1',
          'fetch_all_file': '1',
          'fetch_risk_file_name': '1',
        },
      ),
      headers: _headers(trimmedCookie),
    );
    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw QuarkSaveException(
          _resolveErrorMessage(payload, response.statusCode));
    }
    final code = payload['code'] as int? ?? -1;
    if (code != 0) {
      throw QuarkSaveException(
          _resolveErrorMessage(payload, response.statusCode));
    }

    return payload;
  }

  /// Renames a single drive entry. Works for files and directories alike; the
  /// fid is stable across renames, so callers can rename a whole subtree in any
  /// order without re-listing.
  Future<void> renameEntry({
    required String cookie,
    required String fid,
    required String name,
  }) async {
    final trimmedFid = fid.trim();
    final trimmedName = name.trim();
    if (trimmedFid.isEmpty || trimmedName.isEmpty) {
      return;
    }
    final response = await _client.post(
      Uri.parse('$_baseUrl/1/clouddrive/file/rename').replace(
        queryParameters: const {
          'pr': 'ucpro',
          'fr': 'pc',
          'uc_param_str': '',
        },
      ),
      headers: _headers(cookie),
      body: jsonEncode({
        'fid': trimmedFid,
        'file_name': trimmedName,
      }),
    );
    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw QuarkSaveException(
          _resolveErrorMessage(payload, response.statusCode));
    }
    final code = payload['code'] as int? ?? -1;
    if (code != 0) {
      throw QuarkSaveException(
          _resolveErrorMessage(payload, response.statusCode));
    }
  }

  /// Renames the entries this save just created whose name contains one of
  /// [characters], so that URL-addressed playback keeps working.
  ///
  /// Scoped deliberately to [savedEntries] — what the save actually copied in.
  /// An incremental save that adds one episode must not re-walk the dozens of
  /// episode folders already sitting in the show directory, and must not touch
  /// content a media server has already matched and scraped. Everything in
  /// scope here is new: nothing downstream has seen it yet, which is why
  /// renaming files is safe at this point but would not be later.
  ///
  /// A failure on one entry (most often a name collision with a sibling) is
  /// recorded and the walk continues: the files are already saved, and aborting
  /// here would leave the tree half-renamed.
  Future<QuarkNameSanitizeResult> sanitizeSavedEntries({
    required String cookie,
    required List<QuarkSavedEntry> savedEntries,
    required String characters,
  }) async {
    return CloudSavedNameSanitizer(
      listEntries: (id) => listEntries(cookie: cookie, parentFid: id),
      renameEntry: (id, name) =>
          renameEntry(cookie: cookie, fid: id, name: name),
    ).sanitize(savedEntries: savedEntries, characters: characters);
  }

  Future<QuarkDeleteResult> deleteEntries({
    required String cookie,
    required List<String> fids,
  }) async {
    final trimmedCookie = cookie.trim();
    if (trimmedCookie.isEmpty) {
      throw const QuarkSaveException('请先填写夸克 Cookie');
    }

    final normalizedFids = fids
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedFids.isEmpty) {
      throw const QuarkSaveException('没有可删除的夸克文件');
    }

    final response = await _client.post(
      Uri.parse('$_baseUrl/1/clouddrive/file/delete').replace(
        queryParameters: const {
          'pr': 'ucpro',
          'fr': 'pc',
          'uc_param_str': '',
        },
      ),
      headers: _headers(trimmedCookie),
      body: jsonEncode({
        'action_type': 2,
        'filelist': normalizedFids,
        'exclude_fids': const <String>[],
      }),
    );
    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw QuarkSaveException(
          _resolveErrorMessage(payload, response.statusCode));
    }
    final code = payload['code'] as int? ?? -1;
    if (code != 0) {
      throw QuarkSaveException(
          _resolveErrorMessage(payload, response.statusCode));
    }

    final data = payload['data'] as Map<String, dynamic>? ?? const {};
    final taskId = '${data['task_id'] ?? ''}'.trim();
    var finished = data['finish'] == true;
    if (taskId.isNotEmpty && !finished) {
      finished = await _waitForTask(
        cookie: trimmedCookie,
        taskId: taskId,
      );
    }
    return QuarkDeleteResult(
      taskId: taskId,
      deletedCount: normalizedFids.length,
      finished: finished,
    );
  }

  CloudSavePlanner<_QuarkShareEntry> _savePlanner(
          String pwdId, String stoken, String cookie) =>
      CloudSavePlanner(
        driveName: '夸克',
        listShared: (id) => _fetchShareEntries(
            pwdId: pwdId, stoken: stoken, pdirFid: id, cookie: cookie),
        listStored: (id) => listEntries(cookie: cookie, parentFid: id),
        createDirectory: (id, name) =>
            _createDirectory(cookie: cookie, parentFid: id, folderName: name),
      );

  Future<String> _createDirectory({
    required String cookie,
    required String parentFid,
    required String folderName,
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/1/clouddrive/file').replace(
        queryParameters: const {
          'pr': 'ucpro',
          'fr': 'pc',
          'uc_param_str': '',
        },
      ),
      headers: _headers(cookie),
      body: jsonEncode({
        'pdir_fid': parentFid.trim().isEmpty ? '0' : parentFid.trim(),
        'file_name': folderName,
        // Quark already knows the parent folder from `pdir_fid`.
        // Passing the full absolute path here creates an extra wrapper level
        // such as `/分享/分享/家庭医生`, so only send the child directory name.
        'dir_path': '/$folderName',
        'dir_init_lock': false,
      }),
    );
    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw QuarkSaveException(
          _resolveErrorMessage(payload, response.statusCode));
    }
    final code = payload['code'] as int? ?? -1;
    if (code != 0) {
      throw QuarkSaveException(
          _resolveErrorMessage(payload, response.statusCode));
    }

    final createdFid =
        '${(payload['data'] as Map<String, dynamic>? ?? const {})['fid'] ?? ''}'
            .trim();
    if (createdFid.isNotEmpty) {
      return createdFid;
    }
    throw const QuarkSaveException('夸克文件夹创建后未返回目录 ID，未提交转存，请先检查网盘');
  }

  Future<List<QuarkDirectoryEntry>> listDirectories({
    required String cookie,
    String parentFid = '0',
  }) async {
    final entries = await listEntries(
      cookie: cookie,
      parentFid: parentFid,
    );
    return entries
        .where((item) => item.isDirectory)
        .map(QuarkDirectoryEntry.fromFileEntry)
        .whereType<QuarkDirectoryEntry>()
        .toList(growable: false);
  }

  Future<QuarkDirectoryEntry?> resolveDirectoryByPath({
    required String cookie,
    required String path,
  }) async {
    final normalizedPath = normalizeQuarkDirectoryPath(path);
    if (normalizedPath == '/') {
      return const QuarkDirectoryEntry(
        fid: '0',
        name: '',
        path: '/',
      );
    }

    var currentFid = '0';
    QuarkDirectoryEntry? resolvedDirectory;
    final segments = normalizedPath
        .split('/')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    for (final segment in segments) {
      final directories = await listDirectories(
        cookie: cookie,
        parentFid: currentFid,
      );
      final match = directories.firstWhere(
        (directory) =>
            _normalizeQuarkEntryNameKey(directory.name) ==
            _normalizeQuarkEntryNameKey(segment),
        orElse: () => const QuarkDirectoryEntry(
          fid: '',
          name: '',
          path: '',
        ),
      );
      if (match.fid.isEmpty) {
        return null;
      }
      currentFid = match.fid;
      resolvedDirectory = match;
    }
    return resolvedDirectory;
  }

  Future<List<QuarkFileEntry>> listEntriesRecursively({
    required String cookie,
    String parentFid = '0',
  }) async {
    final collected = <String, QuarkFileEntry>{};

    Future<void> visit(String currentParentFid) async {
      final entries = await listEntries(
        cookie: cookie,
        parentFid: currentParentFid,
      );
      for (final entry in entries) {
        collected.putIfAbsent(entry.fid, () => entry);
      }
      for (final entry in entries) {
        if (!entry.isDirectory) {
          continue;
        }
        await visit(entry.fid);
      }
    }

    await visit(parentFid.trim().isEmpty ? '0' : parentFid.trim());
    return collected.values.toList(growable: false);
  }

  Future<QuarkResolvedDownload> resolveDownload({
    required String cookie,
    required String fid,
  }) async {
    final trimmedCookie = cookie.trim();
    final normalizedFid = fid.trim();
    if (trimmedCookie.isEmpty) {
      throw const QuarkSaveException('请先填写夸克 Cookie');
    }
    if (normalizedFid.isEmpty) {
      throw const QuarkSaveException('没有可解析的夸克文件 ID');
    }

    final response = await _client.post(
      Uri.parse('$_baseUrl/1/clouddrive/file/download').replace(
        queryParameters: const {
          'pr': 'ucpro',
          'fr': 'pc',
          'uc_param_str': '',
        },
      ),
      headers: _headers(trimmedCookie),
      body: jsonEncode({
        'fids': [normalizedFid],
      }),
    );
    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw QuarkSaveException(
        _resolveErrorMessage(payload, response.statusCode),
      );
    }
    final code = payload['code'] as int? ?? -1;
    if (code != 0) {
      throw QuarkSaveException(
        _resolveErrorMessage(payload, response.statusCode),
      );
    }

    final entries = _downloadCandidates(payload['data']);
    Map<String, dynamic>? matched;
    for (final entry in entries) {
      if ('${entry['fid'] ?? ''}'.trim() == normalizedFid) {
        matched = entry;
        break;
      }
    }
    matched ??= entries.isEmpty ? null : entries.first;
    final downloadUrl = _extractDownloadUrl(matched ?? const {});
    if (downloadUrl.isEmpty) {
      throw const QuarkSaveException('夸克没有返回可用的下载地址');
    }

    final mergedCookie = _mergeCookies(
      trimmedCookie,
      response.headers['set-cookie'] ?? '',
    );
    return QuarkResolvedDownload(
      url: downloadUrl,
      headers: {
        if (mergedCookie.isNotEmpty) 'Cookie': mergedCookie,
        'User-Agent': _userAgent,
        'Referer': _baseUrl,
        'Origin': _baseUrl,
      },
      fileSizeBytes: _tryParseInt(
        '${(matched ?? const {})['size'] ?? (matched ?? const {})['file_size'] ?? ''}',
      ),
    );
  }

  Future<String> readTextFile({
    required String cookie,
    required String fid,
  }) async {
    final resolved = await resolveDownload(
      cookie: cookie,
      fid: fid,
    );
    final response = await _client.get(
      Uri.parse(resolved.url),
      headers: resolved.headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw QuarkSaveException('夸克文件读取失败：HTTP ${response.statusCode}');
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Future<bool> _waitForTask({
    required String cookie,
    required String taskId,
    String taskLabel = '删除',
  }) async {
    for (var attempt = 0; attempt < 80; attempt++) {
      final response = await _client.get(
        Uri.parse('$_baseUrl/1/clouddrive/task').replace(
          queryParameters: {
            'pr': 'ucpro',
            'fr': 'pc',
            'uc_param_str': '',
            'task_id': taskId,
            'retry_index': '$attempt',
            '__dt':
                '${(math.Random().nextDouble() * 4 + 1).round() * 60 * 1000}',
            '__t': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
          },
        ),
        headers: _headers(cookie),
      );
      final payload = _decode(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw QuarkSaveException(
          _resolveErrorMessage(payload, response.statusCode),
        );
      }
      final code = payload['code'] as int? ?? -1;
      if (code != 0) {
        throw QuarkSaveException(
          _resolveErrorMessage(payload, response.statusCode),
        );
      }

      final data = payload['data'] as Map<String, dynamic>? ?? const {};
      final status = (data['status'] as num?)?.toInt() ?? 0;
      if (status == 2) {
        return true;
      }
      if (status < 0) {
        final message = '${data['message'] ?? data['msg'] ?? ''}'.trim();
        throw QuarkSaveException(
          message.isNotEmpty ? message : '夸克$taskLabel任务执行失败',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw QuarkSaveException('夸克$taskLabel任务执行超时，请稍后确认结果');
  }

  Future<String> _fetchShareToken({
    required String pwdId,
    required String passcode,
    required String cookie,
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/1/clouddrive/share/sharepage/token').replace(
        queryParameters: const {
          'pr': 'ucpro',
          'fr': 'pc',
        },
      ),
      headers: _headers(cookie),
      body: jsonEncode({
        'pwd_id': pwdId,
        'passcode': passcode,
      }),
    );
    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw QuarkSaveException(
          _resolveErrorMessage(payload, response.statusCode));
    }
    final code = payload['code'] as int? ?? -1;
    if (code != 0) {
      throw QuarkSaveException(
          _resolveErrorMessage(payload, response.statusCode));
    }
    final data = payload['data'] as Map<String, dynamic>? ?? const {};
    final stoken = '${data['stoken'] ?? ''}'.trim();
    if (stoken.isEmpty) {
      throw const QuarkSaveException('夸克返回了空的 stoken');
    }
    return stoken;
  }

  Future<List<_QuarkShareEntry>> _fetchShareEntries({
    required String pwdId,
    required String stoken,
    required String pdirFid,
    required String cookie,
  }) async {
    final entries = <_QuarkShareEntry>[];
    final ids = <String>{};

    for (var page = 1; page <= 2000; page++) {
      final response = await _client.get(
        _buildShareDetailUri(
          pwdId: pwdId,
          stoken: stoken,
          pdirFid: pdirFid,
          page: page,
          size: 50,
        ),
        headers: _headers(cookie),
      );
      final payload = _decode(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw QuarkSaveException(
            _resolveErrorMessage(payload, response.statusCode));
      }
      final code = payload['code'] as int? ?? -1;
      if (code != 0) {
        throw QuarkSaveException(
            _resolveErrorMessage(payload, response.statusCode));
      }

      final data = payload['data'];
      final rows = data is Map ? data['list'] : null;
      if (rows is! List) throw const QuarkSaveException('夸克分享目录响应不完整');
      for (final row in rows) {
        final entry =
            row is Map<String, dynamic> ? _QuarkShareEntry.fromJson(row) : null;
        if (entry == null || !ids.add(entry.fid)) {
          throw const QuarkSaveException('夸克分享文件信息不完整或重复');
        }
        entries.add(entry);
      }
      final metadata = payload['metadata'];
      final total =
          metadata is Map ? int.tryParse('${metadata['_total']}') : null;
      if (total != null && entries.length >= total) return entries;
      if (rows.isEmpty && total != null && entries.length < total) {
        throw const QuarkSaveException('夸克分享目录分页不完整，已停止操作');
      }
      if (rows.isEmpty || (total == null && rows.length < 50)) return entries;
    }
    throw const QuarkSaveException('夸克分享目录过大，已停止操作');
  }

  Future<void> _validateShareDetail({
    required String pwdId,
    required String stoken,
    required String pdirFid,
    required String cookie,
  }) async {
    final response = await _client.get(
      _buildShareDetailUri(
        pwdId: pwdId,
        stoken: stoken,
        pdirFid: pdirFid,
        page: 1,
        size: 1,
      ),
      headers: _headers(cookie),
    );
    if (response.statusCode == 404 || response.statusCode == 410) {
      throw const QuarkSaveException('分享地址不存在或已失效');
    }
    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw QuarkSaveException(
        _resolveErrorMessage(payload, response.statusCode),
      );
    }
    final code = payload['code'] as int? ?? -1;
    if (code != 0) {
      throw QuarkSaveException(
        _resolveErrorMessage(payload, response.statusCode),
      );
    }
    final data = payload['data'] as Map<String, dynamic>? ?? const {};
    final list = data['list'] as List<dynamic>? ?? const [];
    if (list.isEmpty) {
      throw const QuarkSaveException('分享内容为空');
    }
  }

  Uri _buildShareDetailUri({
    required String pwdId,
    required String stoken,
    required String pdirFid,
    required int page,
    required int size,
  }) {
    return Uri.parse('$_baseUrl/1/clouddrive/share/sharepage/detail').replace(
      queryParameters: {
        'pr': 'ucpro',
        'fr': 'pc',
        'pwd_id': pwdId,
        'stoken': stoken,
        'pdir_fid': pdirFid,
        'force': '0',
        '_page': '$page',
        '_size': '$size',
        '_fetch_banner': '0',
        '_fetch_share': '0',
        '_fetch_total': '1',
        '_sort': 'file_type:asc,updated_at:desc',
        'ver': '2',
        'fetch_share_full_path': '0',
      },
    );
  }

  Future<List<QuarkSharePreviewEntry>> _collectSharePreviewEntries({
    required String pwdId,
    required String stoken,
    required String cookie,
    required List<_QuarkShareEntry> entries,
    String parentRelativePath = '',
  }) async {
    final previewEntries = <QuarkSharePreviewEntry>[];
    for (final entry in entries) {
      final relativePath = parentRelativePath.isEmpty
          ? entry.name
          : '$parentRelativePath/${entry.name}';
      previewEntries.add(
        QuarkSharePreviewEntry(
          name: entry.name,
          relativePath: relativePath,
          isDirectory: entry.isDirectory,
        ),
      );
      if (!entry.isDirectory) {
        continue;
      }
      final nestedEntries = await _fetchShareEntries(
        pwdId: pwdId,
        stoken: stoken,
        pdirFid: entry.fid,
        cookie: cookie,
      );
      if (nestedEntries.isEmpty) {
        continue;
      }
      previewEntries.addAll(
        await _collectSharePreviewEntries(
          pwdId: pwdId,
          stoken: stoken,
          cookie: cookie,
          entries: nestedEntries,
          parentRelativePath: relativePath,
        ),
      );
    }
    return previewEntries;
  }

  Future<String> _saveShareEntries({
    required String pwdId,
    required String stoken,
    required String cookie,
    required String targetDirectoryFid,
    required List<_QuarkShareEntry> entries,
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/1/clouddrive/share/sharepage/save').replace(
        queryParameters: {
          'pr': 'ucpro',
          'fr': 'pc',
          'uc_param_str': '',
          'app': 'clouddrive',
          '__dt': '${(math.Random().nextDouble() * 4 + 1).round() * 60 * 1000}',
          '__t': '${DateTime.now().millisecondsSinceEpoch / 1000}',
        },
      ),
      headers: _headers(cookie),
      body: jsonEncode({
        'fid_list': entries.map((item) => item.fid).toList(),
        'fid_token_list': entries.map((item) => item.shareFidToken).toList(),
        'to_pdir_fid': targetDirectoryFid,
        'pwd_id': pwdId,
        'stoken': stoken,
        'pdir_fid': '0',
        'scene': 'link',
      }),
    );

    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw QuarkSaveException(
        _resolveErrorMessage(payload, response.statusCode),
      );
    }
    final code = payload['code'] as int? ?? -1;
    if (code != 0) {
      throw QuarkSaveException(
        _resolveErrorMessage(payload, response.statusCode),
      );
    }

    final data = payload['data'] as Map<String, dynamic>? ?? const {};
    return '${data['task_id'] ?? ''}'.trim();
  }

  Map<String, String> _headers(String cookie) {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Cookie': cookie,
      'User-Agent': _userAgent,
    };
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.trim().isEmpty) {
      return const {};
    }
    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return const {};
  }

  List<Map<String, dynamic>> _downloadCandidates(Object? raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    }
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final nested = map['list'] ?? map['files'] ?? map['download_list'];
      if (nested is List) {
        return nested
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
      }
      return [map];
    }
    return const [];
  }

  String _extractDownloadUrl(Map<String, dynamic> json) {
    for (final key in const [
      'download_url',
      'downloadUrl',
      'url',
      'file_url',
      'fileUrl',
    ]) {
      final raw = '${json[key] ?? ''}'.trim();
      if (raw.isNotEmpty) {
        return raw;
      }
    }
    final nested = json['download_info'] ?? json['downloadInfo'];
    if (nested is Map) {
      return _extractDownloadUrl(Map<String, dynamic>.from(nested));
    }
    return '';
  }

  String _mergeCookies(String baseCookie, String setCookieHeader) {
    final cookies = <String, String>{};

    void collectCookieFragment(String raw) {
      for (final fragment in raw.split(';')) {
        final separatorIndex = fragment.indexOf('=');
        if (separatorIndex <= 0) {
          continue;
        }
        final key = fragment.substring(0, separatorIndex).trim();
        final value = fragment.substring(separatorIndex + 1).trim();
        if (key.isEmpty || value.isEmpty) {
          continue;
        }
        cookies[key] = value;
      }
    }

    if (baseCookie.trim().isNotEmpty) {
      collectCookieFragment(baseCookie);
    }
    if (setCookieHeader.trim().isNotEmpty) {
      for (final entry in setCookieHeader.split(',')) {
        final firstPart = entry.split(';').first.trim();
        collectCookieFragment(firstPart);
      }
    }

    return cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  int? _tryParseInt(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return int.tryParse(trimmed);
  }

  String _resolveErrorMessage(Map<String, dynamic> payload, int statusCode) {
    final message = '${payload['message'] ?? payload['msg'] ?? ''}'.trim();
    if (message.isNotEmpty) {
      return message;
    }
    return '夸克保存失败：HTTP $statusCode';
  }

  bool _isPermanentlyInvalidShareMessage(String rawMessage) {
    final message = rawMessage.trim().toLowerCase();
    if (message.isEmpty) {
      return false;
    }
    return const <String>[
      '取消分享',
      '已取消',
      '分享已取消',
      '分享已被取消',
      '分享被取消',
      '链接不存在',
      '分享不存在',
      '文件不存在',
      '已失效',
      '链接失效',
      '分享失效',
      '已过期',
      '链接过期',
      '分享过期',
      '分享内容为空',
      '已删除',
      '被删除',
      '违规',
      '提取码错误',
      '密码错误',
      'invalid share',
      'share not found',
      'share expired',
    ].any(message.contains);
  }

  _ParsedQuarkShare? _parseShareUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) {
      return null;
    }
    final segments = uri.pathSegments;
    final shareIndex = segments.indexOf('s');
    if (shareIndex < 0 || shareIndex + 1 >= segments.length) {
      return null;
    }
    final pwdId = segments[shareIndex + 1].trim();
    if (pwdId.isEmpty) {
      return null;
    }

    var pdirFid = '0';
    for (var index = shareIndex + 2; index < segments.length; index++) {
      final segment = Uri.decodeComponent(segments[index]).trim();
      final match = RegExp(r'^([a-zA-Z0-9]{32})').firstMatch(segment);
      if (match != null) {
        pdirFid = match.group(1)!;
      }
    }

    return _ParsedQuarkShare(
      pwdId: pwdId,
      passcode: uri.queryParameters['pwd']?.trim() ?? '',
      pdirFid: pdirFid,
    );
  }
}

class QuarkSaveResult {
  const QuarkSaveResult({
    required this.taskId,
    required this.savedCount,
    this.skippedCount = 0,
    required this.targetFolderPath,
    this.targetFolderId = '',
    this.savedEntries = const [],
    this.savedEntriesSettled = true,
  });

  final String taskId;
  final int savedCount;
  final int skippedCount;
  final String targetFolderPath;

  /// Directory the entries landed in. Needed to walk what was just saved.
  final String targetFolderId;

  /// Entries this save actually copied in, so follow-up work can act on just
  /// them instead of re-walking everything already in the target.
  final List<QuarkSavedEntry> savedEntries;

  /// Whether Quark reported the copy tasks as finished, i.e. whether
  /// [savedEntries] can actually be listed in the drive yet.
  final bool savedEntriesSettled;

  String get summary => '保存 $savedCount 个，略过 $skippedCount 个';
}

typedef QuarkShareValidationStatus = ShareLinkValidationStatus;
typedef QuarkShareValidationResult = ShareLinkValidationResult;

class QuarkSharePreview {
  const QuarkSharePreview({
    required this.targetFolderPath,
    this.entries = const [],
  });

  final String targetFolderPath;
  final List<QuarkSharePreviewEntry> entries;

  List<QuarkSharePreviewEntry> get videoEntries {
    return entries.where((entry) => entry.isVideo).toList(growable: false);
  }
}

class QuarkSharePreviewEntry {
  const QuarkSharePreviewEntry({
    required this.name,
    required this.relativePath,
    required this.isDirectory,
  });

  final String name;
  final String relativePath;
  final bool isDirectory;

  String get extension => _resolveQuarkExtension(name);

  bool get isVideo {
    return !isDirectory && _quarkVideoExtensions.contains(extension);
  }
}

class QuarkConnectionStatus {
  const QuarkConnectionStatus({
    required this.rootDirectoryCount,
  });

  final int rootDirectoryCount;

  String get summary => '根目录文件夹 $rootDirectoryCount 个';
}

/// An entry a save copied in, and the directory it landed in.
typedef QuarkSavedEntry = CloudSavedEntry;
typedef QuarkNameSanitizeResult = CloudNameSanitizeResult;

class QuarkDeleteResult {
  const QuarkDeleteResult({
    required this.taskId,
    required this.deletedCount,
    required this.finished,
  });

  final String taskId;
  final int deletedCount;
  final bool finished;
}

class QuarkResolvedDownload {
  const QuarkResolvedDownload({
    required this.url,
    this.headers = const {},
    this.fileSizeBytes,
  });

  final String url;
  final Map<String, String> headers;
  final int? fileSizeBytes;
}

typedef QuarkSaveException = CloudSaveException;

class _ParsedQuarkShare {
  const _ParsedQuarkShare({
    required this.pwdId,
    required this.passcode,
    required this.pdirFid,
  });

  final String pwdId;
  final String passcode;
  final String pdirFid;
}

class QuarkDirectoryEntry {
  const QuarkDirectoryEntry({
    required this.fid,
    required this.name,
    required this.path,
  });

  final String fid;
  final String name;
  final String path;

  static QuarkDirectoryEntry? fromFileEntry(QuarkFileEntry entry) {
    if (!entry.isDirectory) {
      return null;
    }
    return QuarkDirectoryEntry(
      fid: entry.fid,
      name: entry.name,
      path: entry.path,
    );
  }
}

class QuarkFileEntry implements CloudSaveEntry {
  const QuarkFileEntry({
    required this.fid,
    required this.name,
    required this.path,
    required this.isDirectory,
    this.sizeBytes,
    this.updatedAt,
    this.mimeType = '',
    this.category = '',
    this.extension = '',
  });

  @override
  final String fid;
  @override
  final String name;
  final String path;
  @override
  final bool isDirectory;
  final int? sizeBytes;
  final DateTime? updatedAt;
  final String mimeType;
  final String category;
  final String extension;

  bool get isVideo {
    if (isDirectory) {
      return false;
    }
    final normalizedMimeType = mimeType.trim().toLowerCase();
    if (normalizedMimeType.startsWith('video/')) {
      return true;
    }
    final normalizedCategory = category.trim().toLowerCase();
    if (normalizedCategory == 'video') {
      return true;
    }
    final normalizedExtension = extension.trim().toLowerCase();
    return _quarkVideoExtensions.contains(normalizedExtension);
  }

  static QuarkFileEntry? fromJson(Map<String, dynamic> json) {
    final fid = '${json['fid'] ?? ''}'.trim();
    final name = '${json['file_name'] ?? json['name'] ?? ''}'.trim();
    final rawPath = '${json['file_path'] ?? ''}'.trim();
    final normalizedPath = rawPath.isEmpty
        ? '/$name'
        : rawPath.startsWith('/')
            ? rawPath
            : '/$rawPath';
    if (fid.isEmpty || name.isEmpty) {
      return null;
    }
    return QuarkFileEntry(
      fid: fid,
      name: name,
      path: normalizedPath,
      isDirectory: json['dir'] == true,
      sizeBytes: _parseQuarkInt(json['size'] ?? json['file_size']),
      updatedAt: _parseQuarkDateTime(
        json['updated_at'] ?? json['update_time'] ?? json['updatedAt'],
      ),
      mimeType: '${json['mime_type'] ?? json['mimeType'] ?? ''}'.trim(),
      category:
          '${json['obj_category'] ?? json['category'] ?? json['type'] ?? ''}'
              .trim(),
      extension: _resolveQuarkExtension(name),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'fid': fid,
      'file_name': name,
      'file_path': path,
      'dir': isDirectory,
      if (sizeBytes != null) 'size': sizeBytes,
      if (updatedAt != null) 'updated_at': updatedAt!.millisecondsSinceEpoch,
      'mime_type': mimeType,
      'obj_category': category,
    };
  }
}

const Set<String> _quarkVideoExtensions = cloudVideoExtensions;

int? _parseQuarkInt(Object? raw) {
  final text = '$raw'.trim();
  if (text.isEmpty || text == 'null') {
    return null;
  }
  return int.tryParse(text);
}

DateTime? _parseQuarkDateTime(Object? raw) {
  final text = '$raw'.trim();
  if (text.isEmpty || text == 'null') {
    return null;
  }
  final numeric = int.tryParse(text);
  if (numeric != null) {
    if (numeric > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(numeric);
    }
    if (numeric > 1000000000) {
      return DateTime.fromMillisecondsSinceEpoch(numeric * 1000);
    }
  }
  return DateTime.tryParse(text);
}

String _resolveQuarkExtension(String name) {
  final normalized = name.trim();
  final dotIndex = normalized.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex >= normalized.length - 1) {
    return '';
  }
  return normalized.substring(dotIndex + 1).toLowerCase();
}

class _QuarkShareEntry implements CloudSaveEntry {
  const _QuarkShareEntry({
    required this.fid,
    required this.name,
    required this.shareFidToken,
    required this.isDirectory,
  });

  @override
  final String fid;
  @override
  final String name;
  final String shareFidToken;
  @override
  final bool isDirectory;

  static _QuarkShareEntry? fromJson(Map<String, dynamic> json) {
    final fid = '${json['fid'] ?? ''}'.trim();
    final name = '${json['file_name'] ?? json['name'] ?? ''}'.trim();
    final shareFidToken = '${json['share_fid_token'] ?? ''}'.trim();
    if (fid.isEmpty || name.isEmpty || shareFidToken.isEmpty) {
      return null;
    }
    return _QuarkShareEntry(
      fid: fid,
      name: name,
      shareFidToken: shareFidToken,
      isDirectory: json['dir'] == true,
    );
  }
}

String _normalizeQuarkEntryNameKey(String raw) {
  return cloudSaveNameKey(raw);
}

String _resolveQuarkTargetFolderPath({
  required String toPdirPath,
  required String saveFolderName,
}) =>
    resolveCloudSaveFolderPath(toPdirPath, saveFolderName);
