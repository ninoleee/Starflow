import 'package:starflow/features/search/domain/cloud_save_rules.dart';

class CloudSaveBatch<T extends CloudSaveEntry> {
  const CloudSaveBatch(
      {required this.targetDirectoryFid, required this.entries});
  final String targetDirectoryFid;
  final List<T> entries;
}

class CloudSavePlan<T extends CloudSaveEntry> {
  const CloudSavePlan({
    required this.targetFolderId,
    required this.targetFolderPath,
    required this.batches,
    this.skippedCount = 0,
  });
  final String targetFolderId;
  final String targetFolderPath;
  final List<CloudSaveBatch<T>> batches;
  final int skippedCount;
}

/// A single save operation owns the listing cache; it is never reused later.
class CloudSavePlanner<T extends CloudSaveEntry> {
  CloudSavePlanner({
    required this.driveName,
    required this.listShared,
    required this.listStored,
    required this.createDirectory,
    this.maxDepth = 64,
  });

  final String driveName;
  final Future<List<T>> Function(String) listShared;
  final Future<List<CloudSaveEntry>> Function(String) listStored;
  final Future<String> Function(String parentId, String name) createDirectory;
  final int maxDepth;
  final _stored = <String, List<CloudSaveEntry>>{};

  Future<List<CloudSaveEntry>> _listStored(String id) async =>
      _stored[id] ??= await listStored(id);

  Future<List<T>> flattenTopDirectory(List<T> entries) async {
    if (entries.length != 1 || !entries.single.isDirectory) return entries;
    final nested = await listShared(entries.single.fid);
    return nested.isEmpty ? entries : nested;
  }

  Future<CloudSavePlan<T>> build({
    required List<T> entries,
    required String folderId,
    required String folderPath,
    required String saveFolderName,
    String sanitizedNameCharacters = '',
  }) async {
    final name = sanitizeCloudDirectoryName(saveFolderName);
    if (name.isNotEmpty) {
      entries = await flattenTopDirectory(entries);
      _validate(entries, characters: sanitizedNameCharacters, unique: true);
    }
    final target =
        await _resolveTarget(folderId, folderPath, name, createIfMissing: true);
    final targetId = target.id!;
    final batches = <CloudSaveBatch<T>>[];
    final skipped = target.deduplicate
        ? await _merge(targetId, entries, sanitizedNameCharacters, batches, 0)
        : 0;
    if (!target.deduplicate && entries.isNotEmpty) {
      batches
          .add(CloudSaveBatch(targetDirectoryFid: targetId, entries: entries));
    }
    return CloudSavePlan(
      targetFolderId: targetId,
      targetFolderPath: target.path,
      batches: batches,
      skippedCount: skipped,
    );
  }

  Future<({String? id, String path, bool deduplicate})> _resolveTarget(
      String folderId, String folderPath, String name,
      {required bool createIfMissing}) async {
    final id = folderId.trim().isEmpty ? '0' : folderId.trim();
    final path = normalizeCloudDirectoryPath(folderPath);
    if (!cloudSaveNeedsChild(path, name)) {
      return (id: id, path: path, deduplicate: name.isNotEmpty);
    }
    final children = await _listStored(id);
    _validate(children);
    final matches = children
        .where(
            (entry) => cloudSaveNameKey(entry.name) == cloudSaveNameKey(name))
        .toList();
    if (matches.length > 1 ||
        (matches.isNotEmpty &&
            (!matches.single.isDirectory || matches.single.fid == id))) {
      throw CloudSaveException('$driveName 保存目录同名冲突，未提交转存，请先检查网盘');
    }
    if (matches.isNotEmpty) {
      return (
        id: matches.single.fid,
        path: cloudChildPath(path, matches.single.name),
        deduplicate: true
      );
    }
    final targetPath = cloudChildPath(path, name);
    if (!createIfMissing) {
      return (id: null, path: targetPath, deduplicate: false);
    }
    final createdId = await createDirectory(id, name);
    if (createdId.isEmpty || createdId == '0' || createdId == id) {
      throw CloudSaveException('$driveName 创建目录后未返回有效目录 ID，未提交转存');
    }
    _stored[createdId] = const [];
    return (id: createdId, path: targetPath, deduplicate: false);
  }

  Future<CloudSavePreview> preview({
    required List<T> entries,
    required String folderId,
    required String folderPath,
    required String saveFolderName,
    String sanitizedNameCharacters = '',
    bool flattenTopDirectory = true,
  }) async {
    final name = sanitizeCloudDirectoryName(saveFolderName);
    if (name.isNotEmpty && flattenTopDirectory) {
      entries = await this.flattenTopDirectory(entries);
    }
    final target = await _resolveTarget(folderId, folderPath, name,
        createIfMissing: false);

    Future<List<CloudSavePreviewEntry>> collect(List<CloudSaveEntry> initial,
        Future<List<CloudSaveEntry>> Function(String) list) async {
      final collected = <CloudSavePreviewEntry>[];
      final visited = <String>{};
      Future<void> visit(
          List<CloudSaveEntry> children, String parent, int depth) async {
        if (depth >= maxDepth || collected.length + children.length > 100000) {
          throw CloudSaveException('$driveName 目录过大或层级异常，无法检查更新');
        }
        _validate(children, characters: sanitizedNameCharacters, unique: true);
        for (final entry in children) {
          if (!visited.add(entry.fid) ||
              entry.name.contains('/') ||
              entry.name.contains('\\')) {
            throw CloudSaveException('$driveName 目录路径异常，无法检查更新');
          }
          final path = parent.isEmpty ? entry.name : '$parent/${entry.name}';
          collected.add(CloudSavePreviewEntry(
              name: entry.name,
              relativePath: path,
              isDirectory: entry.isDirectory));
          if (entry.isDirectory) {
            await visit(await list(entry.fid), path, depth + 1);
          }
        }
      }

      await visit(initial, '', 0);
      return List.unmodifiable(collected);
    }

    final online = await collect(entries, listShared);
    final local = target.id == null
        ? const <CloudSavePreviewEntry>[]
        : await collect(await _listStored(target.id!), _listStored);
    final localByKey = {
      for (final entry in local)
        entry.comparisonKey(sanitizedNameCharacters): entry,
    };
    for (final entry in online) {
      final match = localByKey[entry.comparisonKey(sanitizedNameCharacters)];
      if (match != null && match.isDirectory != entry.isDirectory) {
        throw CloudSaveException('$driveName 目标存在文件与目录冲突，无法检查更新');
      }
    }
    return CloudSavePreview(
        targetFolderPath: target.path,
        localFolderExists: target.id != null,
        onlineEntries: online,
        localEntries: local,
        sanitizedNameCharacters: sanitizedNameCharacters,
        deduplicate: target.deduplicate);
  }

  Future<List<CloudSavedEntry>> trackNewEntries(List<CloudSaveBatch<T>> batches,
      {bool captureTree = false}) async {
    Future<List<CloudCopyEntry>> snapshot(String id, int depth) async {
      if (depth >= maxDepth) {
        throw CloudSaveException('$driveName 分享目录层级异常，未提交转存');
      }
      final entries = await listShared(id);
      _validate(entries, unique: true);
      return [
        for (final entry in entries)
          CloudCopyEntry(
            name: entry.name,
            isDirectory: entry.isDirectory,
            children: entry.isDirectory
                ? await snapshot(entry.fid, depth + 1)
                : const [],
          )
      ];
    }

    final saved = <CloudSavedEntry>[];
    for (final batch in batches) {
      final existing = await _listStored(batch.targetDirectoryFid);
      _validate(existing);
      final previousIds =
          Set<String>.unmodifiable(existing.map((entry) => entry.fid));
      for (final entry in batch.entries) {
        saved.add(CloudSavedEntry(
          parentFid: batch.targetDirectoryFid,
          name: entry.name,
          isDirectory: entry.isDirectory,
          previousFids: previousIds,
          expectedChildren: captureTree && entry.isDirectory
              ? await snapshot(entry.fid, 0)
              : null,
        ));
      }
    }
    return saved;
  }

  void _validate(List<CloudSaveEntry> entries,
      {String characters = '', bool unique = false}) {
    final ids = <String>{};
    final names = <String>{};
    for (final entry in entries) {
      final key = cloudSaveNameKey(entry.name,
          characters: characters, isDirectory: entry.isDirectory);
      if (entry.fid.isEmpty || entry.fid == '0' || !ids.add(entry.fid)) {
        throw CloudSaveException('$driveName 目录文件标识不完整或重复，未提交转存');
      }
      if (key.isEmpty || key == '.' || key == '..') {
        throw CloudSaveException('$driveName 目录名称不完整，无法安全去重，未提交转存');
      }
      if (unique && !names.add(key)) {
        throw CloudSaveException('$driveName 分享中存在同名冲突，未提交转存，请先检查分享');
      }
    }
  }

  Future<int> _merge(String targetId, List<T> entries, String characters,
      List<CloudSaveBatch<T>> batches, int depth) async {
    if (depth >= maxDepth) {
      throw CloudSaveException('$driveName 目录层级异常，未提交转存');
    }
    _validate(entries, characters: characters, unique: true);
    final existing = await _listStored(targetId);
    _validate(existing);
    final byName = <String, List<CloudSaveEntry>>{};
    for (final entry in existing) {
      byName
          .putIfAbsent(
              cloudSaveNameKey(entry.name,
                  characters: characters, isDirectory: entry.isDirectory),
              () => [])
          .add(entry);
    }
    final pending = <T>[];
    final nestedBatches = <CloudSaveBatch<T>>[];
    var skipped = 0;
    for (final entry in entries) {
      final matches = byName[cloudSaveNameKey(entry.name,
              characters: characters, isDirectory: entry.isDirectory)] ??
          const [];
      if (matches.isEmpty) {
        pending.add(entry);
      } else if (matches.length > 1 ||
          matches.single.isDirectory != entry.isDirectory ||
          matches.single.fid == targetId) {
        throw CloudSaveException('$driveName 目标存在同名冲突，无法安全合并，未提交转存');
      } else if (!entry.isDirectory) {
        skipped++;
      } else {
        final nested = await listShared(entry.fid);
        skipped += nested.isEmpty
            ? 1
            : await _merge(matches.single.fid, nested, characters,
                nestedBatches, depth + 1);
      }
    }
    if (pending.isNotEmpty) {
      batches
          .add(CloudSaveBatch(targetDirectoryFid: targetId, entries: pending));
    }
    batches.addAll(nestedBatches);
    return skipped;
  }
}
