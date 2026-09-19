import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:starflow/features/library/data/media_server_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/subtitle_content_decoder.dart';
import 'package:starflow/features/playback/application/subtitle_content_processing.dart';
import 'package:starflow/features/playback/application/fntv_session_owner.dart';
import 'package:starflow/features/playback/application/subtitle_render_policy.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

/// Protocol work stays in Dart; native playback only consumes resolved results.
class NativeFntvService {
  NativeFntvService({
    required this.client,
    required this.source,
    this.temporaryDirectory = getTemporaryDirectory,
  });

  final MediaServerClient client;
  final MediaSourceConfig source;
  final Future<Directory> Function() temporaryDirectory;
  final List<Directory> _subtitleDirectories = [];
  bool _closed = false;
  late final sessions = FntvSessionOwner((target) async {
    final sessionClient = client;
    if (sessionClient is MediaServerSessionClient) {
      await (sessionClient as MediaServerSessionClient)
          .releasePlaybackSession(source: source, target: target);
    }
  });

  Future<Map<String, Object?>> downloadSubtitle(
    PlaybackTarget target,
    String subtitleId,
  ) async {
    if (_closed ||
        target.sourceKind != MediaSourceKind.fntv ||
        target.sourceId != source.id) {
      throw StateError('播放会话已变化');
    }
    final stream = target.subtitleStreams.firstWhere(
      (stream) => stream.id == subtitleId && stream.isExternal,
    );
    if (isBitmapSubtitle(image: stream.isBitmap, codec: stream.codec)) {
      throw const SubtitleContentException('位图字幕不能作为文本外挂字幕加载');
    }
    final bytes = await client.downloadExternalSubtitleBytes(
      source: source,
      subtitleId: subtitleId,
    );
    final content =
        await processSubtitleContent(bytes, preferredName: stream.title);
    final extension = detectSubtitleFormat(content);
    final root = await temporaryDirectory();
    if (_closed) throw StateError('播放会话已结束');
    final directory = await root.createTemp('starflow-fntv-');
    if (_closed) {
      await directory.delete(recursive: true);
      throw StateError('播放会话已结束');
    }
    _subtitleDirectories.add(directory);
    try {
      final file = File('${directory.path}/subtitle.$extension');
      await file.writeAsString(content, encoding: utf8, flush: true);
      if (_closed) throw StateError('播放会话已结束');
      return {'ok': true, 'path': file.path, 'displayName': stream.title};
    } catch (_) {
      if (await directory.exists()) await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> close() async {
    _closed = true;
    await sessions.close();
    final directories = List<Directory>.of(_subtitleDirectories);
    _subtitleDirectories.clear();
    for (final directory in directories) {
      try {
        if (await directory.exists()) await directory.delete(recursive: true);
      } catch (_) {
        // Temporary files may already have been reclaimed by the OS.
      }
    }
  }
}
