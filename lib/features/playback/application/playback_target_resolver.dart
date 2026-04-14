import 'package:riverpod/misc.dart';
import 'package:starflow/core/utils/playback_trace.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
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
    PlaybackTarget preparedTarget = _resetStaleQuarkRelayIfNeeded(target);
    try {
      _traceQuarkResolve(
        'quark.resolve.begin',
        target: preparedTarget,
        fields: {
          'needsResolution': preparedTarget.needsResolution,
          'hasStreamUrl': preparedTarget.streamUrl.trim().isNotEmpty,
          'hasHeaders': preparedTarget.headers.isNotEmpty,
          'itemId': preparedTarget.itemId,
        },
      );
      preparedTarget = await _prepareDirectTargetIfNeeded(preparedTarget);
      if (!preparedTarget.needsResolution) {
        _traceQuarkResolve(
          'quark.resolve.skip',
          target: preparedTarget,
          fields: {
            'reason': 'no-resolution-needed',
            'streamUrl': preparedTarget.streamUrl,
            'headers': preparedTarget.headers.length,
          },
        );
        return preparedTarget;
      }

      final settings = read(appSettingsProvider);
      final source =
          settings.mediaSources.cast<MediaSourceConfig?>().firstWhere(
                (item) => item?.id == preparedTarget.sourceId,
                orElse: () => null,
              );
      if (source == null) {
        throw const _TargetResolutionException('媒体源不存在或已被移除');
      }

      if (source.kind == MediaSourceKind.emby) {
        if (!source.hasActiveSession) {
          throw const _TargetResolutionException('Emby 会话已失效，请重新登录');
        }
        return read(embyApiClientProvider).resolvePlaybackTarget(
          source: source,
          target: preparedTarget,
        );
      }

      if (source.kind == MediaSourceKind.quark) {
        final cookie = settings.networkStorage.quarkCookie.trim();
        if (cookie.isEmpty) {
          throw const _TargetResolutionException('请先填写夸克 Cookie');
        }
        final resolvedFid = _resolveQuarkPlaybackFid(preparedTarget);
        if (resolvedFid.isEmpty) {
          throw const _TargetResolutionException('没有可解析的夸克文件 ID');
        }
        final resolved = await read(quarkSaveClientProvider).resolveDownload(
          cookie: cookie,
          fid: resolvedFid,
        );
        _traceQuarkResolve(
          'quark.resolve.download-ready',
          target: preparedTarget,
          fields: {
            'fid': resolvedFid,
            'downloadUrl': resolved.url,
            'headers': resolved.headers.keys.join('|'),
            'fileSizeBytes':
                resolved.fileSizeBytes ?? preparedTarget.fileSizeBytes ?? 0,
          },
        );
        final directTarget = preparedTarget.copyWith(
          streamUrl: resolved.url,
          actualAddress: resolved.url,
          headers: resolved.headers,
          itemId: resolvedFid,
          fileSizeBytes: resolved.fileSizeBytes ?? preparedTarget.fileSizeBytes,
        );
        _traceQuarkResolve(
          'quark.resolve.direct-ready',
          target: directTarget,
          fields: {
            'streamUrl': directTarget.streamUrl,
            'headers': directTarget.headers.keys.join('|'),
          },
        );
        return directTarget;
      }

      return read(webDavNasClientProvider).resolvePlaybackTarget(
        source: source,
        target: preparedTarget,
      );
    } catch (error, stackTrace) {
      _traceQuarkResolve(
        'quark.resolve.failed',
        target: preparedTarget,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  PlaybackTarget _resetStaleQuarkRelayIfNeeded(PlaybackTarget target) {
    final sanitized = sanitizeLoopbackPlaybackRelayTarget(target);
    if (identical(sanitized, target)) {
      return target;
    }
    _traceQuarkResolve(
      'quark.resolve.stale-relay-reset',
      target: target,
      fields: {
        'relayUrl': target.streamUrl,
        'actualAddress': target.actualAddress,
        'itemId': target.itemId,
      },
    );
    return sanitized;
  }

  Future<PlaybackTarget> _prepareDirectTargetIfNeeded(PlaybackTarget target) {
    if (target.sourceKind != MediaSourceKind.quark) {
      return Future<PlaybackTarget>.value(target);
    }
    if (target.streamUrl.trim().isEmpty || target.headers.isEmpty) {
      return Future<PlaybackTarget>.value(target);
    }
    _traceQuarkResolve(
      'quark.resolve.direct-pass-through',
      target: target,
      fields: {
        'streamUrl': target.streamUrl,
        'headers': target.headers.keys.join('|'),
      },
    );
    return Future<PlaybackTarget>.value(
      target.copyWith(
        actualAddress: target.actualAddress.trim().isNotEmpty
            ? target.actualAddress
            : target.streamUrl,
      ),
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

void _traceQuarkResolve(
  String stage, {
  required PlaybackTarget target,
  Map<String, Object?> fields = const <String, Object?>{},
  Object? error,
  StackTrace? stackTrace,
}) {
  if (target.sourceKind != MediaSourceKind.quark) {
    return;
  }
  playbackTrace(
    stage,
    fields: <String, Object?>{
      'title': target.title.trim().isEmpty ? 'Starflow' : target.title.trim(),
      'sourceKind': target.sourceKind.name,
      'container': target.container,
      'actualAddress': target.actualAddress,
      ...fields,
    },
    error: error,
    stackTrace: stackTrace,
  );
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
