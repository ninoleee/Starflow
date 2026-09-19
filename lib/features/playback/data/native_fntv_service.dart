import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:starflow/features/library/data/media_server_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/subtitle_content_decoder.dart';
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
    if (stream.isBitmap ||
        const [
          'pgs',
          'sup',
          'hdmv_pgs_subtitle',
          'dvd_subtitle',
          'vobsub',
          'idx',
        ].contains(stream.codec.toLowerCase())) {
      throw const SubtitleContentException('位图字幕不能作为文本外挂字幕加载');
    }
    final bytes = await client.downloadExternalSubtitleBytes(
      source: source,
      subtitleId: subtitleId,
    );
    final content = decodeSubtitleBytes(isSubtitleZipBytes(bytes)
        ? extractSubtitleBytesFromZip(bytes, preferredName: stream.title)
        : bytes);
    final text = content.trimLeft();
    final extension = text.startsWith('WEBVTT')
        ? 'vtt'
        : text.contains('[Script Info]') || text.contains('[Events]')
            ? 'ass'
            : text.contains('-->')
                ? 'srt'
                : null;
    if (extension == null || content.trim().isEmpty) {
      throw const SubtitleContentException('没有可加载的 SRT / ASS / SSA / VTT 字幕');
    }
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
