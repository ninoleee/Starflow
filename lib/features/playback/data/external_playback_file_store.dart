import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:starflow/features/playback/data/external_playback_playlist.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

class ExternalPlaybackFileStore {
  ExternalPlaybackFileStore({Directory? directory, DateTime Function()? now})
      : directory = directory ??
            Directory(p.join(Directory.systemTemp.path, 'starflow-playlists')),
        _now = now ?? DateTime.now;

  final Directory directory;
  final DateTime Function() _now;
  DateTime? _lastCleanup;
  Future<void>? _cleanupInFlight;

  Future<File> create(PlaybackTarget target) async {
    await directory.create(recursive: true);
    await cleanup();
    final title = target.title
        .replaceAll(RegExp(r'[\\/:*?"<>|&^%!]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final safeTitle = title.isEmpty ? 'playback' : title;
    final prefix =
        safeTitle.length > 48 ? safeTitle.substring(0, 48) : safeTitle;
    // Exclusive creation prevents concurrent launches from sharing a playlist.
    final allocation = await directory.createTemp('starflow-');
    final file = File(p.join(allocation.path, '$prefix.m3u'));
    try {
      await file.writeAsString(buildExternalPlaybackPlaylist(target),
          flush: true);
      return file;
    } catch (_) {
      await allocation.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> delete(File file) async {
    if (p.dirname(file.parent.path) != directory.path ||
        !p.basename(file.parent.path).startsWith('starflow-')) {
      return;
    }
    try {
      await file.parent.delete(recursive: true);
    } on FileSystemException {
      // The stale-file pass may already have removed this allocation.
    }
  }

  Future<void> cleanup() {
    final running = _cleanupInFlight;
    if (running != null) return running;
    final now = _now();
    final previous = _lastCleanup;
    if (previous != null &&
        !now.isBefore(previous) &&
        now.difference(previous) < const Duration(minutes: 10)) {
      return Future<void>.value();
    }
    _lastCleanup = now;
    return _cleanupInFlight = _removeStale(now).whenComplete(() {
      _cleanupInFlight = null;
    });
  }

  Future<void> _removeStale(DateTime now) async {
    final cutoff = now.subtract(const Duration(hours: 1));
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! Directory ||
            !p.basename(entity.path).startsWith('starflow-')) {
          continue;
        }
        try {
          if ((await entity.stat()).modified.isBefore(cutoff)) {
            await entity.delete(recursive: true);
          }
        } on FileSystemException {
          // A concurrent launch cleanup must not prevent opening a new file.
        }
      }
    } on FileSystemException {
      // Cleanup is best effort; creating the current playlist is independent.
    }
  }
}
