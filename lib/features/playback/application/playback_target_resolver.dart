import 'package:riverpod/misc.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_service.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

typedef PlaybackTargetResolverReader = T Function<T>(
  ProviderListenable<T> provider,
);

class PlaybackTargetResolver {
  PlaybackTargetResolver({
    required this.read,
  });

  final PlaybackTargetResolverReader read;

  Future<PlaybackTarget> resolve(PlaybackTarget target) async {
    if (!target.needsResolution) {
      return target;
    }

    final settings = read(appSettingsProvider);
    final source = settings.mediaSources
        .cast<MediaSourceConfig?>()
        .firstWhere((item) => item?.id == target.sourceId, orElse: () => null);
    if (source == null) {
      throw const _TargetResolutionException('媒体源不存在或已被移除');
    }

    if (source.kind == MediaSourceKind.emby) {
      if (!source.hasActiveSession) {
        throw const _TargetResolutionException('Emby 会话已失效，请重新登录');
      }
      return read(embyApiClientProvider).resolvePlaybackTarget(
        source: source,
        target: target,
      );
    }

    if (source.kind == MediaSourceKind.quark) {
      final cookie = settings.networkStorage.quarkCookie.trim();
      if (cookie.isEmpty) {
        throw const _TargetResolutionException('请先填写夸克 Cookie');
      }
      final resolvedFid = _resolveQuarkPlaybackFid(target);
      if (resolvedFid.isEmpty) {
        throw const _TargetResolutionException('没有可解析的夸克文件 ID');
      }
      final resolved = await read(quarkSaveClientProvider).resolveDownload(
        cookie: cookie,
        fid: resolvedFid,
      );
      final directTarget = target.copyWith(
        streamUrl: resolved.url,
        actualAddress: resolved.url,
        headers: resolved.headers,
        itemId: resolvedFid,
        fileSizeBytes: resolved.fileSizeBytes ?? target.fileSizeBytes,
      );
      return read(playbackStreamRelayServiceProvider).prepareTarget(
        directTarget,
      );
    }

    return read(webDavNasClientProvider).resolvePlaybackTarget(
      source: source,
      target: target,
    );
  }
}

String _resolveQuarkPlaybackFid(PlaybackTarget target) {
  final directItemId = target.itemId.trim();
  if (directItemId.isNotEmpty && !directItemId.startsWith('quark://')) {
    return directItemId;
  }

  for (final candidate in [target.itemId, target.actualAddress]) {
    final parsed = _parseQuarkResourceId(candidate);
    if (parsed != null) {
      return parsed.fid;
    }
  }
  return directItemId;
}

_ParsedQuarkResourceId? _parseQuarkResourceId(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme != 'quark') {
    return null;
  }
  final segments = uri.pathSegments
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (segments.isEmpty) {
    return null;
  }
  final fid = Uri.decodeComponent(segments.last);
  if (fid.isEmpty) {
    return null;
  }
  return _ParsedQuarkResourceId(fid: fid);
}

class _ParsedQuarkResourceId {
  const _ParsedQuarkResourceId({required this.fid});

  final String fid;
}

class _TargetResolutionException implements Exception {
  const _TargetResolutionException(this.message);

  final String message;

  @override
  String toString() => message;
}
