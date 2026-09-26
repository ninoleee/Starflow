import 'dart:convert';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/features/search/application/cloud115_save_workflow_service.dart';
import 'package:starflow/features/search/application/cloud_save_postprocessing.dart';
import 'package:starflow/features/search/application/cloud_save_planner.dart';
import 'package:starflow/features/search/data/aliyun_transfer_client.dart';
import 'package:starflow/features/search/data/aliyun_transfer_journal.dart';
import 'package:starflow/features/search/data/cloud115_instant_upload_client.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/domain/cloud_save_feedback.dart';
import 'package:starflow/features/search/domain/cloud_save_rules.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final aliyunTo115WorkflowProvider = Provider((ref) => AliyunTo115Workflow(
      journal: ref.watch(aliyunTransferJournalProvider),
      aliyun: AliyunTransferClient(ref.watch(starflowHttpClientProvider)),
      upload:
          Cloud115InstantUploadClient(ref.watch(starflowHttpClientProvider)),
      destination: ref.watch(cloud115SaveClientProvider),
      postprocessing: ref.watch(cloud115SaveWorkflowProvider),
      persistToken: (previous, next) async {
        final config = ref.read(appSettingsProvider).networkStorage;
        if (config.activeAliyunRefreshToken == next) return;
        if (config.activeAliyunRefreshToken != previous) {
          throw const QuarkSaveException('阿里账号配置已变化，请重新发起转存');
        }
        await ref
            .read(settingsControllerProvider.notifier)
            .rotateAliyunCredential(previous, next);
      },
    ));

class AliyunTo115Workflow {
  AliyunTo115Workflow(
      {required this.aliyun,
      required this.upload,
      required this.destination,
      required this.postprocessing,
      this.journal,
      required this.persistToken});
  final AliyunTransferClient aliyun;
  final Cloud115InstantUploadClient upload;
  final Cloud115SaveClient destination;
  final Cloud115SaveWorkflowService postprocessing;
  final Future<void> Function(String, String) persistToken;
  bool _running = false;
  final AliyunTransferJournal? journal;
  bool _cancelRequested = false;
  String? activeTaskId;
  bool get isRunning => _running;
  void requestStop() {
    _cancelRequested = true;
  }

  void _checkpoint() {
    if (_cancelRequested) throw const QuarkSaveException('任务已停止，未确认的阿里副本保留');
  }

  Future<String> resume(String id, NetworkStorageConfig current,
      {bool cleanupOnly = false}) async {
    final rows = await journal!.list();
    final record = rows.singleWhere((r) => r['id'] == id);
    final snapshot = NetworkStorageConfig.fromJson(
        Map<String, dynamic>.from(record['config'] as Map));
    return _save(
        shareUrl: record['shareUrl'] as String,
        password: record['password'] as String,
        saveFolderName: record['saveName'] as String,
        config: current.copyWith(
            cloud115SaveFolderId: snapshot.cloud115SaveFolderId,
            cloud115SaveFolderPath: snapshot.cloud115SaveFolderPath),
        deleteAliyunCopies: cleanupOnly || record['deleteCopies'] == true,
        resumeRecord: record,
        cleanupOnly: cleanupOnly);
  }

  Future<AliyunTransferSession> connect(NetworkStorageConfig config) =>
      aliyun.login(config.activeAliyunRefreshToken,
          persistToken: (next) =>
              persistToken(config.activeAliyunRefreshToken, next),
          open: config.aliyunAuthMode == AliyunAuthMode.open);

  Future<CloudSavePreview> preview(
      {required String shareUrl,
      required String password,
      required NetworkStorageConfig config,
      required String saveFolderName}) async {
    final link = AliyunShareLink.parse(shareUrl, password: password);
    final token = await aliyun.shareToken(link);
    final is115 = config.aliyunTo115Enabled;
    final characters = is115
        ? config.effective115NameCharacters
        : config.effectiveAliyunNameCharacters;
    final entries =
        targetTree(await aliyun.listSharedTree(link, token), characters);
    final session = is115 ? null : await connect(config);
    final planner = CloudSavePlanner<AliyunTransferFile>(
        driveName: is115 ? '115' : '阿里',
        listShared: (id) async =>
            entries.where((e) => e.parentId == id).toList(),
        listStored: (id) async => is115
            ? destination.listEntries(
                cookie: config.cloud115Cookie, parentFid: id)
            : aliyun.listOwned(session!, id),
        createDirectory: (_, __) async => throw StateError('Read-only preview'),
        maxDepth: 25);
    // Save retains the shared top directory; preview must do the same.
    final result = await planner.preview(
        entries: entries.where((e) => e.path.isEmpty).toList(),
        folderId:
            is115 ? config.cloud115SaveFolderId : config.aliyunSaveFolderId,
        folderPath:
            is115 ? config.cloud115SaveFolderPath : config.aliyunSaveFolderPath,
        saveFolderName: saveFolderName,
        sanitizedNameCharacters: characters,
        flattenTopDirectory: false);
    // Both Aliyun save modes deduplicate even without a named child folder.
    return CloudSavePreview(
        targetFolderPath: result.targetFolderPath,
        localFolderExists: result.localFolderExists,
        onlineEntries: result.onlineEntries,
        localEntries: result.localEntries,
        sanitizedNameCharacters: result.sanitizedNameCharacters);
  }

  Future<String> saveToAliyun(
      {required String shareUrl,
      required String password,
      required NetworkStorageConfig config,
      required String saveFolderName,
      CloudSaveProgressCallback? onProgress,
      void Function(String)? onBackgroundRefreshFailure}) async {
    if (_running) throw const QuarkSaveException('已有阿里保存任务，请等待完成');
    if (config.aliyunSaveFolderId.isEmpty) {
      throw const QuarkSaveException('阿里账号已变化，请重新选择保存目录');
    }
    _running = true;
    var folderName = '';
    var saved = 0;
    try {
      onProgress?.call(const CloudSaveProgress.saving(CloudSaveDrive.aliyun));
      final link = AliyunShareLink.parse(shareUrl, password: password);
      final token = await aliyun.shareToken(link);
      final entries = targetTree(await aliyun.listSharedTree(link, token),
          config.effectiveAliyunNameCharacters);
      if (entries.isEmpty) throw const QuarkSaveException('阿里分享内容为空');
      final session = await aliyun.login(config.activeAliyunRefreshToken,
          persistToken: (next) =>
              persistToken(config.activeAliyunRefreshToken, next),
          open: config.aliyunAuthMode == AliyunAuthMode.open);
      final name = sanitizeCloudDirectoryName(saveFolderName);
      Future<String> folder(String parent, String name) async {
        final rows = await aliyun.listOwned(session, parent);
        final matches = rows
            .where((e) => cloudSaveNameKey(e.name) == cloudSaveNameKey(name))
            .toList();
        if (matches.length > 1 || matches.any((e) => !e.isDirectory)) {
          throw const QuarkSaveException('阿里同名目录冲突');
        }
        return matches.isEmpty
            ? aliyun.createSaveDirectory(session, parent, name)
            : matches.single.id;
      }

      folderName = normalizeCloudDirectoryPath(config.aliyunSaveFolderPath);
      var root = config.aliyunSaveFolderId;
      if (cloudSaveNeedsChild(folderName, name)) {
        root = await folder(root, name);
        folderName = cloudChildPath(folderName, name);
      }
      final folders = <String, String>{jsonEncode([]): root};
      var skipped = 0;
      for (final entry in entries) {
        final parent = folders[jsonEncode(entry.path)];
        if (parent == null) throw const QuarkSaveException('阿里保存目录结构不完整');
        if (entry.isDirectory) {
          folders[jsonEncode([...entry.path, entry.name])] =
              await folder(parent, entry.name);
        } else {
          final matches = (await aliyun.listOwned(session, parent))
              .where((e) =>
                  cloudSaveNameKey(e.name) == cloudSaveNameKey(entry.name))
              .toList();
          if (matches.isNotEmpty) {
            if (matches.length != 1 ||
                matches.single.isDirectory ||
                matches.single.sha1 != entry.sha1 ||
                matches.single.size != entry.size) {
              throw const QuarkSaveException('阿里有内容不同的同名文件，未覆盖');
            }
            skipped++;
            continue;
          }
          final copy =
              await aliyun.stageFile(session, link, token, parent, entry);
          if (copy.name != entry.name) {
            await aliyun.renameOwned(session, copy, entry.name);
          }
          saved++;
        }
      }
      var strmFailure = '';
      var triggered = false;
      if (saved > 0 &&
          config.smartStrmWebhookUrl.isNotEmpty &&
          config.aliyunSmartStrmTaskName.isNotEmpty) {
        final outcome = await triggerSavedCloudStrm(
            drive: CloudSaveDrive.aliyun,
            trigger: () => postprocessing.smartStrm.triggerTask(
                webhookUrl: config.smartStrmWebhookUrl,
                taskName: config.aliyunSmartStrmTaskName,
                storagePath: folderName == '/' ? '' : folderName,
                delay: cloudSaveDelaySeconds(config.smartStrmDelaySeconds)));
        strmFailure = outcome.failure;
        triggered = outcome.result != null;
      }
      if (saved > 0 && config.refreshMediaSourceIds.isNotEmpty) {
        unawaited(refreshSavedCloudMedia(
            drive: CloudSaveDrive.aliyun,
            onFailure: onBackgroundRefreshFailure,
            refresh: () => postprocessing.refresh(config.refreshMediaSourceIds,
                cloudSaveDelaySeconds(config.refreshDelaySeconds))));
      }
      return '已保存到阿里，文件 $saved 个，略过 $skipped 个；保存目录：$folderName'
          '${triggered ? '；已触发阿里 STRM' : ''}'
          '${strmFailure.isEmpty ? '' : '；STRM 失败：$strmFailure'}';
    } catch (error) {
      final reason = error is QuarkSaveException ? error.message : '阿里保存结果未确认';
      throw QuarkSaveException('$reason；已确认保存 $saved 个，未删除任何文件'
          '${folderName.isEmpty ? '' : '；请检查 $folderName'}');
    } finally {
      _running = false;
    }
  }

  Future<String> save(
          {required String shareUrl,
          required String password,
          required NetworkStorageConfig config,
          required String saveFolderName,
          bool deleteAliyunCopies = false,
          CloudSaveProgressCallback? onProgress,
          void Function(String)? onBackgroundRefreshFailure}) =>
      _save(
          shareUrl: shareUrl,
          password: password,
          config: config,
          saveFolderName: saveFolderName,
          deleteAliyunCopies: deleteAliyunCopies,
          onProgress: onProgress,
          onBackgroundRefreshFailure: onBackgroundRefreshFailure);

  Future<String> _save(
      {required String shareUrl,
      required String password,
      required NetworkStorageConfig config,
      required String saveFolderName,
      bool deleteAliyunCopies = false,
      Map<String, dynamic>? resumeRecord,
      bool cleanupOnly = false,
      CloudSaveProgressCallback? onProgress,
      void Function(String)? onBackgroundRefreshFailure}) async {
    if (_running) throw const QuarkSaveException('已有阿里转 115 任务，请等待完成');
    if (config.cloud115SaveFolderId.isEmpty) {
      throw const QuarkSaveException('115 账号已变化，请重新选择保存目录');
    }
    _running = true;
    _cancelRequested = false;
    Map<String, dynamic>? record = resumeRecord;
    Future<void> saveRecord(String stage) async {
      if (record == null || journal == null) return;
      record['stage'] = stage;
      record['updated'] = DateTime.now().toIso8601String();
      await journal!.put(record);
    }

    var stagingName = '';
    var confirmed = 0;
    var cleaned = 0;
    try {
      onProgress?.call(const CloudSaveProgress.transferring('正在读取阿里分享...'));
      final link = AliyunShareLink.parse(shareUrl, password: password);
      final token = cleanupOnly ? '' : await aliyun.shareToken(link);
      final entries = record != null
          ? (record['entries'] as List)
              .map((e) => transferFileFromJson(
                  Map<String, dynamic>.from(e as Map),
                  allowMissingSha1: true))
              .toList()
          : targetTree(await aliyun.listSharedTree(link, token),
              config.effective115NameCharacters);
      final files = entries.where((e) => !e.isDirectory).toList();
      if (files.isEmpty) throw const QuarkSaveException('阿里分享中没有可转存文件');
      final account = await upload.account(config.cloud115Cookie);
      if (files.any((f) => f.size > account.sizeLimit)) {
        throw const QuarkSaveException('分享中有文件超过 115 单文件上传限制');
      }
      final session = await aliyun.login(config.activeAliyunRefreshToken,
          persistToken: (next) =>
              persistToken(config.activeAliyunRefreshToken, next),
          open: config.aliyunAuthMode == AliyunAuthMode.open);
      _checkpoint();
      if (record != null &&
          (record['aliyunAccount'] != '${session.userId}:${session.driveId}' ||
              record['cloud115Account'] != account.userId)) {
        throw const QuarkSaveException('任务绑定的网盘账号与当前账号不同');
      }
      record ??= {
        'id': AliyunTransferClient.newStagingName(),
        'shareUrl': shareUrl,
        'password': password,
        'saveName': saveFolderName,
        'config': {
          'cloud115SaveFolderId': config.cloud115SaveFolderId,
          'cloud115SaveFolderPath': config.cloud115SaveFolderPath
        },
        'deleteCopies': deleteAliyunCopies,
        'aliyunAccount': '${session.userId}:${session.driveId}',
        'cloud115Account': account.userId,
        'entries': entries.map(transferFileJson).toList(),
        'files': <String, dynamic>{},
        'folders': <String, dynamic>{}
      };
      activeTaskId = record['id'] as String;
      stagingName = record['stagingName'] as String? ??
          AliyunTransferClient.newStagingName();
      record['stagingName'] = stagingName;
      String stagingId;
      if (record['stagingId'] != null) {
        stagingId = record['stagingId'] as String;
      } else {
        if (record['stagingIntent'] == true) {
          throw const QuarkSaveException('暂存目录创建结果未确认，请检查阿里目录后另建任务');
        }
        record['stagingIntent'] = true;
        await saveRecord('创建暂存目录');
        _checkpoint();
        stagingId = await aliyun.createStagingFolder(session, stagingName);
        record['stagingId'] = stagingId;
        await saveRecord('阿里暂存');
      }
      var targetId = config.cloud115SaveFolderId;
      var targetPath =
          normalizeCloudDirectoryPath(config.cloud115SaveFolderPath);
      if (!RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(targetId)) {
        throw const QuarkSaveException('115 保存目录无效');
      }
      Future<String> folder(String parent, String name) async {
        _checkpoint();
        final rows = await destination.listEntries(
            cookie: config.cloud115Cookie, parentFid: parent);
        final matches = rows.where((e) => e.name == name).toList();
        if (matches.length > 1 || matches.any((e) => !e.isDirectory)) {
          throw const QuarkSaveException('115 同名目录存在歧义，未覆盖');
        }
        if (cleanupOnly && matches.isEmpty) {
          throw const QuarkSaveException('115 目标目录不存在，未清理');
        }
        final key = jsonEncode([parent, name]);
        final known = (record!['folders'] as Map)[key];
        if (known != null &&
            (matches.length != 1 || matches.single.fid != known)) {
          throw const QuarkSaveException('115 任务目标目录身份已变化');
        }
        final id = matches.isEmpty
            ? destination.createDirectory(
                cookie: config.cloud115Cookie, parentId: parent, name: name)
            : Future.value(matches.single.fid);
        final resolved = await id;
        (record['folders'] as Map)[key] = resolved;
        await saveRecord('目标目录');
        return resolved;
      }

      final saveName = sanitizeCloudDirectoryName(saveFolderName);
      if (cloudSaveNeedsChild(targetPath, saveName)) {
        targetId = await folder(targetId, saveName);
        targetPath = cloudChildPath(targetPath, saveName);
      }
      final folders = <String, String>{jsonEncode([]): targetId};
      final staged = <AliyunTransferFile>[];
      final receipts = <({String parent, AliyunTransferFile file})>[];
      var skipped = 0;
      var notMatched = 0;
      for (final entry in entries) {
        _checkpoint();
        final parent = folders[jsonEncode(entry.path)];
        if (parent == null) throw const QuarkSaveException('转存目录结构不完整');
        if (entry.isDirectory) {
          folders[jsonEncode([...entry.path, entry.name])] =
              await folder(parent, entry.name);
          continue;
        }
        onProgress?.call(CloudSaveProgress.transferring(
            '阿里转 115：${confirmed + skipped + notMatched}/${files.length}'));
        final rows = await destination.listEntries(
            cookie: config.cloud115Cookie, parentFid: parent);
        final sameName = rows.where((f) => f.name == entry.name).toList();
        final records = record['files'] as Map;
        final item = Map<String, dynamic>.from(records[entry.id] as Map? ?? {});
        records[entry.id] = item;
        if (item['parent'] != null && item['parent'] != parent) {
          throw const QuarkSaveException('115 文件目标目录身份已变化');
        }
        item['parent'] = parent;
        AliyunTransferFile? recordedCopy;
        if (item['copy'] is Map) {
          recordedCopy = transferFileFromJson(
              Map<String, dynamic>.from(item['copy'] as Map));
          if (recordedCopy.isDirectory ||
              recordedCopy.parentId != stagingId ||
              recordedCopy.size != entry.size ||
              entry.sha1.isNotEmpty && recordedCopy.sha1 != entry.sha1) {
            throw const QuarkSaveException('阿里暂存记录与源文件不一致，任务停止');
          }
        }
        var existingCopy = item['cleaned'] == true ? null : recordedCopy;
        Future<AliyunTransferFile> stageCopy() async {
          if (item['copyIntent'] == true) {
            throw const QuarkSaveException('阿里复制结果未确认，请检查暂存目录；未重复复制');
          }
          item['copyIntent'] = true;
          await saveRecord('阿里暂存');
          _checkpoint();
          final copy =
              await aliyun.stageFile(session, link, token, stagingId, entry);
          item['copy'] = transferFileJson(copy);
          await saveRecord('阿里暂存');
          return copy;
        }

        Future<AliyunTransferFile> verifyCopy(
            AliyunTransferFile expected) async {
          final owned = await aliyun.listOwned(session, stagingId);
          final same = owned.where((f) => f.id == expected.id).toList();
          if (same.length != 1 ||
              same.single.sha1 != expected.sha1 ||
              same.single.size != expected.size ||
              same.single.name != expected.name) {
            throw const QuarkSaveException('阿里暂存副本已变化，任务停止');
          }
          return same.single;
        }

        if (entry.sha1.isEmpty && !cleanupOnly && item['cleaned'] != true) {
          existingCopy = existingCopy == null
              ? await stageCopy()
              : await verifyCopy(existingCopy);
        }
        final knownCopy = existingCopy ?? recordedCopy;
        var resolved = entry.sha1.isEmpty && knownCopy != null
            ? entry.withSha1(knownCopy.sha1)
            : entry;
        if (sameName.isNotEmpty) {
          if (resolved.sha1.isEmpty) {
            throw const QuarkSaveException('阿里文件缺少 SHA1，无法核对已有 115 文件');
          }
          if (sameName.length != 1 ||
              sameName.single.isDirectory ||
              !await destination.verifyTransferredFile(
                  cookie: config.cloud115Cookie,
                  parentId: parent,
                  name: entry.name,
                  size: entry.size,
                  sha1: resolved.sha1)) {
            throw const QuarkSaveException('115 有内容不同的同名文件，未覆盖');
          }
          skipped++;
          if (existingCopy != null) staged.add(existingCopy);
          receipts.add((parent: parent, file: resolved));
          item['verified'] = true;
          await saveRecord('目标校验');
          continue;
        }
        if (cleanupOnly || item['cleaned'] == true) {
          throw const QuarkSaveException('115 目标缺失，未清理阿里副本');
        }
        if (existingCopy == null && item['copyIntent'] == true) {
          throw const QuarkSaveException('阿里复制结果未确认，请检查暂存目录；未重复复制');
        }
        if (existingCopy == null) {
          existingCopy = await stageCopy();
        } else {
          existingCopy = await verifyCopy(existingCopy);
        }
        final copy = existingCopy;
        resolved = entry.sha1.isEmpty ? entry.withSha1(copy.sha1) : entry;
        if (resolved.sha1.isEmpty) {
          throw const QuarkSaveException('阿里暂存副本未返回 SHA1，已停止秒传');
        }
        staged.add(copy);
        _checkpoint();
        if (item['uploadIntent'] == true) {
          throw const QuarkSaveException('上次秒传结果未确认且目标尚不可见，未重复提交');
        }
        item['uploadIntent'] = true;
        await saveRecord('115 秒传');
        _checkpoint();
        final hit = await upload.upload(
            cookie: config.cloud115Cookie,
            account: account,
            parentId: parent,
            name: entry.name,
            size: entry.size,
            fileSha1: resolved.sha1,
            readRange: (start, end) =>
                aliyun.readRange(session, copy, start, end));
        if (!hit) {
          item['uploadIntent'] = false;
          await saveRecord('秒传未命中');
          notMatched++;
          continue;
        }
        var verified = false;
        for (var attempt = 0; attempt < 3; attempt++) {
          if (attempt > 0) {
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          verified = await destination.verifyTransferredFile(
              cookie: config.cloud115Cookie,
              parentId: parent,
              name: entry.name,
              size: entry.size,
              sha1: resolved.sha1);
          if (verified) break;
        }
        if (!verified) throw const QuarkSaveException('115 目标文件校验未通过');
        receipts.add((parent: parent, file: resolved));
        item['verified'] = true;
        await saveRecord('目标校验');
        confirmed++;
      }
      if (notMatched > 0) {
        throw QuarkSaveException('$notMatched 个文件未命中秒传，不自动下载整文件');
      }
      var cleanupFailed = false;
      if (deleteAliyunCopies && staged.isNotEmpty) {
        _checkpoint();
        for (final receipt in receipts) {
          if (!await destination.verifyTransferredFile(
              cookie: config.cloud115Cookie,
              parentId: receipt.parent,
              name: receipt.file.name,
              size: receipt.file.size,
              sha1: receipt.file.sha1)) {
            throw const QuarkSaveException('清理前 115 文件复核失败，未删除阿里副本');
          }
        }
        onProgress
            ?.call(const CloudSaveProgress.transferring('115 已校验，正在清理阿里副本...'));
        for (final copy in staged) {
          _checkpoint();
          try {
            final items = record['files'] as Map;
            final item = items.values.cast<Map>().singleWhere((i) =>
                i['copy'] is Map && (i['copy'] as Map)['file_id'] == copy.id);
            if (item['deleteIntent'] == true) {
              final owned = await aliyun.listOwned(session, stagingId);
              if (!owned.any((f) => f.id == copy.id)) {
                item['cleaned'] = true;
                cleaned++;
                await saveRecord('阿里清理');
                continue;
              }
              throw const QuarkSaveException('上次清理结果未确认，保留副本等待人工检查');
            }
            item['deleteIntent'] = true;
            await saveRecord('阿里清理');
            _checkpoint();
            await aliyun.recycleStagedFile(session, stagingId, copy);
            item['cleaned'] = true;
            cleaned++;
            await saveRecord('阿里清理');
          } catch (_) {
            cleanupFailed = true;
            break;
          }
        }
      }
      _checkpoint();
      if (cleanupOnly) {
        await saveRecord(cleanupFailed ? '清理待检查' : '已完成');
        return '已核验 115，清理阿里副本 $cleaned 个${cleanupFailed ? '，其余待检查' : ''}';
      }
      await saveRecord('后处理');
      if (record['postprocessIntent'] == true) {
        await saveRecord('后处理待检查');
        return '文件已核验，上次后处理结果未确认；未重复触发 Webhook，请手动检查';
      }
      record['postprocessIntent'] = true;
      await saveRecord('后处理');
      _checkpoint();
      // Target names were normalized before creation/upload and verified.
      // Do not run a second rename pass over unrelated destination content.
      final summary = await postprocessing.finishSavedResult(
          result: Cloud115SaveResult(
              savedCount: (record['files'] as Map)
                  .values
                  .where((v) => (v as Map)['copy'] != null)
                  .length,
              skippedCount: skipped,
              targetFolderId: targetId,
              targetFolderPath: targetPath),
          config: config.copyWith(commonSanitizeSavedNamesEnabled: false),
          onBackgroundRefreshFailure: onBackgroundRefreshFailure);
      await saveRecord(cleanupFailed ? '清理待检查' : '已完成');
      return '阿里转 115 完成，$summary；'
          '${deleteAliyunCopies ? '阿里副本已移入回收站 $cleaned 个' : '阿里副本已保留'}'
          '${cleanupFailed ? '，清理未全部确认，请手动检查' : ''}；阿里暂存目录：/$stagingName';
    } catch (error) {
      await saveRecord(_cancelRequested ? '已停止' : '待恢复');
      final reason =
          error is QuarkSaveException ? error.message : '转存发生异常，结果未确认';
      throw QuarkSaveException('$reason；115 已确认 $confirmed 个；'
          '${stagingName.isEmpty ? '未执行阿里文件清理' : '阿里暂存目录 /$stagingName，已清理 $cleaned 个，其余保留'}');
    } finally {
      _running = false;
      activeTaskId = null;
    }
  }

  static List<AliyunTransferFile> targetTree(
      List<AliyunTransferFile> entries, String characters) {
    final seen = <String>{};
    String clean(String name, bool directory) {
      final value = sanitizeCloudSavedEntryName(name,
          isDirectory: directory, characters: characters);
      if (value.isEmpty) throw const QuarkSaveException('名称修正后为空，未保存');
      return value;
    }

    return entries.map((entry) {
      final path = entry.path.map((s) => clean(s, true)).toList();
      final name = clean(entry.name, entry.isDirectory);
      if (!seen
          .add(jsonEncode([...path, name].map(cloudSaveNameKey).toList()))) {
        throw const QuarkSaveException('名称修正后存在同名冲突，未保存');
      }
      return entry.withTargetName(name, path);
    }).toList();
  }
}
