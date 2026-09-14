import 'package:starflow/features/search/domain/cloud_save_rules.dart';

class CloudSavedNameSanitizer {
  const CloudSavedNameSanitizer({
    required this.listEntries,
    required this.renameEntry,
    this.visibilityAttempts = 1,
    this.verifyRenames = false,
    this.wait = Future<void>.delayed,
  });

  final Future<List<CloudSaveEntry>> Function(String parentId) listEntries;
  final Future<void> Function(String id, String name) renameEntry;
  final int visibilityAttempts;
  final bool verifyRenames;
  final Future<void> Function(Duration) wait;

  Future<CloudNameSanitizeResult> sanitize({
    required List<CloudSavedEntry> savedEntries,
    required String characters,
  }) async {
    if (savedEntries.isEmpty || characters.trim().isEmpty) {
      return const CloudNameSanitizeResult();
    }
    final listings = <String, List<CloudSaveEntry>>{};
    final failed = <String>[];
    final changes =
        <({String id, String parentId, String original, String name})>[];
    final visited = <String>{};
    var listedCount = 0;
    var incomplete = false;

    Future<List<CloudSaveEntry>> list(String parentId) async {
      if (listings.containsKey(parentId)) return listings[parentId]!;
      listedCount++;
      return listings[parentId] = await listEntries(parentId);
    }

    Future<void> collect(
        CloudSaveEntry entry,
        List<CloudSaveEntry> siblings,
        String parentId,
        int depth,
        List<CloudCopyEntry>? expectedChildren) async {
      if (depth >= 64 || !visited.add(entry.fid)) {
        incomplete = true;
        failed.add(entry.name);
        return;
      }
      final name = sanitizeCloudSavedEntryName(entry.name,
          isDirectory: entry.isDirectory, characters: characters);
      if (name.isNotEmpty && name != entry.name) {
        final key = cloudSaveNameKey(name);
        final conflict = siblings.any((sibling) =>
            sibling.fid != entry.fid &&
            (cloudSaveNameKey(sibling.name) == key ||
                cloudSaveNameKey(sibling.name,
                        characters: characters,
                        isDirectory: sibling.isDirectory) ==
                    key));
        if (conflict) {
          failed.add(entry.name);
        } else {
          changes.add((
            id: entry.fid,
            parentId: parentId,
            original: entry.name,
            name: name
          ));
        }
      }
      if (entry.isDirectory) {
        final children = await list(entry.fid);
        if (expectedChildren != null &&
            (children.length != expectedChildren.length ||
                expectedChildren.any((expected) =>
                    children
                        .where((child) =>
                            child.name == expected.name &&
                            child.isDirectory == expected.isDirectory)
                        .length !=
                    1))) {
          incomplete = true;
          failed.add(entry.name);
          return;
        }
        for (final child in children) {
          await collect(
              child,
              children,
              entry.fid,
              depth + 1,
              expectedChildren
                  ?.firstWhere((e) => e.name == child.name)
                  .children);
        }
      }
    }

    // Resolve the entire new-content scope before any rename is submitted.
    try {
      for (var attempt = 0; attempt < visibilityAttempts; attempt++) {
        listings.clear();
        changes.clear();
        visited.clear();
        failed.clear();
        incomplete = false;
        for (final saved in savedEntries) {
          final siblings = await list(saved.parentFid);
          final matches = siblings
              .where((entry) =>
                  entry.name.trim() == saved.name.trim() &&
                  (saved.isDirectory == null ||
                      saved.isDirectory == entry.isDirectory) &&
                  !saved.previousFids.contains(entry.fid))
              .toList();
          if (matches.length != 1) {
            failed.add(saved.name);
            incomplete = true;
            continue;
          }
          await collect(matches.single, siblings, saved.parentFid, 0,
              saved.expectedChildren);
        }
        if (!incomplete || attempt + 1 >= visibilityAttempts) break;
        await wait(const Duration(seconds: 1));
      }
    } catch (_) {
      return CloudNameSanitizeResult(
        listedDirectoryCount: listedCount,
        failedNames: [...failed, '新增内容读取未确认'],
      );
    }
    if (incomplete) {
      return CloudNameSanitizeResult(
          listedDirectoryCount: listedCount,
          failedNames: List.unmodifiable(failed));
    }
    var renamedCount = 0;
    final accepted =
        <String, List<({String id, String original, String name})>>{};
    for (final change in changes) {
      try {
        await renameEntry(change.id, change.name);
        if (verifyRenames) {
          accepted.putIfAbsent(change.parentId, () => []).add(
              (id: change.id, original: change.original, name: change.name));
        } else {
          renamedCount++;
        }
      } catch (_) {
        // A lost write response is not retried and blocks downstream generation.
        failed.add(change.original);
      }
    }
    for (final group in accepted.entries) {
      try {
        final children = await listEntries(group.key);
        listedCount++;
        for (final change in group.value) {
          if (children
                  .where((entry) =>
                      entry.fid == change.id && entry.name == change.name)
                  .length ==
              1) {
            renamedCount++;
          } else {
            failed.add(change.original);
          }
        }
      } catch (_) {
        failed.addAll(group.value.map((change) => change.original));
      }
    }
    return CloudNameSanitizeResult(
      renamedCount: renamedCount,
      listedDirectoryCount: listedCount,
      failedNames: List.unmodifiable(failed),
    );
  }
}

class CloudSavedNameOutcome {
  const CloudSavedNameOutcome({this.result, this.warning = ''});
  final CloudNameSanitizeResult? result;
  final String warning;
  bool get canTriggerSmartStrm => warning.isEmpty;
}

Future<CloudSavedNameOutcome> processCloudSavedNames({
  required String characters,
  required int savedCount,
  required List<CloudSavedEntry> savedEntries,
  required bool settled,
  required Future<CloudNameSanitizeResult> Function() sanitize,
  void Function()? onStart,
}) async {
  if (characters.trim().isEmpty || savedCount == 0) {
    return const CloudSavedNameOutcome();
  }
  if (!settled || savedEntries.isEmpty) {
    return const CloudSavedNameOutcome(
        warning: '新增内容尚未确认，未改名，未触发 STRM，请检查网盘并手动处理');
  }
  onStart?.call();
  try {
    final result = await sanitize();
    return CloudSavedNameOutcome(
      result: result,
      warning: result.completed ? '' : '部分名称修正未确认，未触发 STRM，请检查网盘',
    );
  } catch (_) {
    return const CloudSavedNameOutcome(warning: '名称修正未确认，未触发 STRM，请检查网盘');
  }
}
