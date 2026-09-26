import 'package:starflow/core/logging/app_logger.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:starflow/app/theme/app_colors.dart';
import 'package:starflow/features/library/data/media_server_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/data/native_fntv_service.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_service.dart';
import 'package:starflow/features/playback/application/playback_episode_browser.dart';
import 'package:starflow/features/playback/application/playback_variant_resolver.dart';
import 'package:starflow/features/playback/application/playback_episode_queue_resolver.dart';
import 'package:starflow/features/playback/application/subtitle_content_decoder.dart';
import 'package:starflow/features/playback/data/native_playback_launcher.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart'
    hide isLoopbackPlaybackRelayUrl;
import 'package:starflow/features/playback/domain/playback_episode_queue.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

NativePlaybackLauncher createNativePlaybackLauncher(Ref ref) {
  return PlatformNativePlaybackLauncher(ref);
}

class PlatformNativePlaybackLauncher implements NativePlaybackLauncher {
  PlatformNativePlaybackLauncher(
    this._ref, {
    bool? isIOS,
    PlaybackStreamRelayService Function()? relayFactory,
  })  : _isIOS = isIOS ?? Platform.isIOS,
        _relayFactory = relayFactory ??
            (() => createPlaybackStreamRelayService(
                  diskCacheMiB:
                      _ref.read(appSettingsProvider).playbackDiskCacheMiB,
                )) {
    _resolverChannel.setMethodCallHandler(_handleResolverMethodCall);
    _ref.onDispose(() {
      _resolverSessionId = '';
      for (final service in _fntvSessions.values) {
        unawaited(service.close());
      }
      _fntvSessions.clear();
      for (final sessionId in _transports.keys.toList()) {
        unawaited(_closeTransports(sessionId));
      }
    });
  }

  static const _platformChannel = MethodChannel('starflow/platform');
  static const _resolverChannel =
      MethodChannel('starflow/native_playback_resolver');
  final Ref _ref;
  final bool _isIOS;
  final PlaybackStreamRelayService Function() _relayFactory;
  NativePlaybackEpisodeResolver? _episodeResolver;
  String _resolverSessionId = '';
  final Map<String, NativeFntvService> _fntvSessions = {};
  final Map<String, Map<String, PlaybackStreamRelayService>> _transports = {};
  final _transportUrls = <String, Set<String>>{};
  final _cacheCursors = <String, ({int generation, String url})>{};
  final _relayClosures = Expando<Future<void>>();
  int _nextTransport = 0;
  PlaybackEpisodeBrowser? _episodeBrowser;

  Future<void> _closeRelay(PlaybackStreamRelayService relay) =>
      _relayClosures[relay] ??= Future<void>.sync(relay.close);

  Future<PlaybackTarget> _prepareTransport(
      String sessionId, PlaybackTarget target) async {
    final transports = _transports[sessionId];
    if (transports == null) throw const PlaybackRelayException();
    final diskCache = _ref.read(appSettingsProvider).playbackDiskCacheMiB > 0;
    if (!diskCache && (!_isIOS || !requiresPlaybackStreamRelay(target))) {
      _transportUrls[sessionId]?.add(target.streamUrl);
      return target;
    }
    final relay = _relayFactory();
    final pendingKey = 'pending:${++_nextTransport}';
    transports[pendingKey] = relay;
    try {
      final prepared = await relay.prepareTarget(target);
      if (!identical(_transports[sessionId], transports)) {
        throw const PlaybackRelayException();
      }
      if (!isLoopbackPlaybackRelayUrl(prepared.streamUrl)) {
        await _closeRelay(relay);
        _transportUrls[sessionId]?.add(prepared.streamUrl);
        return prepared;
      }
      final previous = transports[prepared.streamUrl];
      if (previous != null && !identical(previous, relay)) {
        await _closeRelay(previous);
        if (!identical(_transports[sessionId], transports)) {
          throw const PlaybackRelayException();
        }
      }
      transports[prepared.streamUrl] = relay;
      _transportUrls[sessionId]?.add(prepared.streamUrl);
      return prepared;
    } catch (_) {
      await _closeRelay(relay);
      rethrow;
    } finally {
      transports.remove(pendingKey);
    }
  }

  Future<void> _closeTransports(String sessionId) async {
    _transportUrls.remove(sessionId);
    _cacheCursors.remove(sessionId);
    final transports = _transports.remove(sessionId);
    if (transports != null) {
      final relays = <PlaybackStreamRelayService>{...transports.values};
      transports.clear();
      await Future.wait(relays.map(_closeRelay));
    }
  }

  Future<void> _closeSession(String sessionId) async {
    if (_resolverSessionId == sessionId) {
      _resolverSessionId = '';
      _episodeResolver = null;
      _episodeBrowser = null;
    }
    final service = _fntvSessions.remove(sessionId);
    await Future.wait<void>([
      _closeTransports(sessionId),
      if (service != null) service.close(),
    ]);
  }

  @override
  Future<NativePlaybackLaunchResult> launch(
    PlaybackTarget target, {
    required PlaybackDecodeMode decodeMode,
    required NativeAudioOutputMode audioOutputMode,
    required double subtitleScale,
    double primarySubtitlePosition = kPlaybackPrimarySubtitlePositionDefault,
    double secondarySubtitlePosition =
        kPlaybackSecondarySubtitlePositionDefault,
    double secondarySubtitleScale = kPlaybackSecondarySubtitleScaleDefault,
    required bool backgroundPlaybackEnabled,
    required PlaybackSubtitlePreference subtitlePreference,
    required PlaybackDefaultSubtitle defaultSubtitle,
    required PlaybackSubtitleLanguage dualSubtitlePrimaryLanguage,
    required PlaybackSubtitleLanguage dualSubtitleSecondaryLanguage,
    PlaybackEpisodeQueue? episodeQueue,
    String mediaMimeType = '',
    NativePlaybackEpisodeResolver? episodeResolver,
  }) async {
    if (!Platform.isAndroid && !_isIOS) {
      return const NativePlaybackLaunchResult(
        launched: false,
        message: '原生播放器（实验性）当前仅支持 Android 和 iOS。',
      );
    }

    final uri = Uri.tryParse(target.streamUrl.trim());
    if (uri == null || !uri.hasScheme) {
      return const NativePlaybackLaunchResult(
        launched: false,
        message: '播放地址无效，无法启动原生播放器。',
      );
    }

    // The launcher owns one native container at a time. A fast reopen can
    // otherwise replace the active session id before the old controller sends
    // its close callback, leaving its relay and FNTV session alive.
    final previousSession = _resolverSessionId;
    if (previousSession.isNotEmpty) {
      await _closeSession(previousSession);
    }
    _episodeResolver = episodeResolver;
    _episodeBrowser = PlaybackEpisodeBrowser(
      resolver: PlaybackEpisodeQueueResolver(read: _ref.read),
      target: target,
    );
    _resolverSessionId = DateTime.now().microsecondsSinceEpoch.toString();
    final sessionId = _resolverSessionId;
    _transports[sessionId] = {};
    _transportUrls[sessionId] = {};
    try {
      if (target.sourceKind == MediaSourceKind.fntv) {
        final source = _ref
            .read(appSettingsProvider)
            .mediaSources
            .firstWhere((source) => source.id == target.sourceId);
        _fntvSessions[sessionId] = NativeFntvService(
          client: _ref.read(mediaServerClientProvider(MediaSourceKind.fntv)),
          source: source,
        );
        await _fntvSessions[sessionId]!.sessions.retain(target);
      }
      final transport = await _prepareTransport(sessionId, target);
      if (_resolverSessionId != sessionId ||
          !_transports.containsKey(sessionId)) {
        throw const PlaybackRelayException();
      }
      final launched = await _platformChannel.invokeMethod<bool>(
        'launchNativePlaybackContainer',
        {
          'url': transport.streamUrl.trim(),
          'title': target.title,
          'headersJson': jsonEncode(transport.headers),
          'decodeMode': decodeMode.name,
          'audioOutputMode': audioOutputMode.name,
          'memoryCacheMiB': _ref.read(appSettingsProvider).playbackMemoryCacheMiB,
          'subtitleScale': clampPlaybackSubtitleScale(subtitleScale),
          'primarySubtitlePosition':
              clampPlaybackSubtitlePosition(primarySubtitlePosition),
          'secondarySubtitlePosition':
              clampPlaybackSubtitlePosition(secondarySubtitlePosition),
          'secondarySubtitleScale':
              clampPlaybackSecondarySubtitleScale(secondarySubtitleScale),
          'backgroundPlaybackEnabled': backgroundPlaybackEnabled,
          'subtitlePreference': subtitlePreference.name,
          'defaultSubtitle': defaultSubtitle.name,
          'dualSubtitlePrimaryLanguage': dualSubtitlePrimaryLanguage.name,
          'dualSubtitleSecondaryLanguage': dualSubtitleSecondaryLanguage.name,
          'mediaMimeType': transport.container == 'hls'
              ? 'application/x-mpegURL'
              : mediaMimeType,
          'resolverSessionId': sessionId,
          'playbackTargetJson': jsonEncode(target.toJson()),
          'playbackItemKey': buildPlaybackItemKey(target),
          'seriesKey': buildSeriesKeyForTarget(target),
          'episodeQueueJson':
              episodeQueue == null ? '' : jsonEncode(episodeQueue.toJson()),
          'episodeAccentColor':
              _ref.read(appSettingsProvider).appAccent.primary.toARGB32(),
          'uiTextScale': _ref.read(appSettingsProvider).uiTextScale,
        },
      );
      if (launched != true) {
        await _closeSession(sessionId);
      }
      return NativePlaybackLaunchResult(
        launched: launched == true,
        message: launched == true ? '' : '原生播放器启动失败。',
      );
    } catch (error, stackTrace) {
      await _closeSession(sessionId);
      _traceQuarkNativeLaunch(
        'quark.native-launch.invoke.failed',
        target: target,
        fields: {
          'decodeMode': decodeMode.name,
          'audioOutputMode': audioOutputMode.name,
        },
        error: error,
        stackTrace: stackTrace,
      );
      return NativePlaybackLaunchResult(
        launched: false,
        message: error is PlaybackRelayException ? error.message : '原生播放器启动失败。',
      );
    }
  }

  Future<Object?> _handleResolverMethodCall(MethodCall call) async {
    if (const {
      'nativePlaybackCacheSnapshot',
      'setNativePlaybackActive',
      'setNativePlaybackBufferState',
      'cancelNativePlaybackReadAhead',
    }.contains(call.method)) {
      return _handleCacheMethodCall(call);
    }
    if (call.method == 'closeNativePlaybackTransports') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      await _closeTransports(args['resolverSessionId'] as String? ?? '');
      return {'ok': true};
    }
    if (call.method == 'releaseNativePlaybackTransport') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final sessionId = args['resolverSessionId'] as String? ?? '';
      final url = args['transportUrl'] as String? ?? '';
      _transportUrls[sessionId]?.remove(url);
      final relay = _transports[sessionId]?.remove(url);
      if (relay != null) await _closeRelay(relay);
      return {'ok': true};
    }
    if (call.method == 'nativePlaybackMemoryChanged') {
      _ref.read(playbackMemoryRepositoryProvider).invalidateSnapshotCache();
      _ref.read(playbackHistoryRevisionProvider.notifier).state++;
      return {'ok': true};
    }
    if (call.method == 'closeNativeFntvSession') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final sessionId = args['resolverSessionId'] as String? ?? '';
      if (sessionId == _resolverSessionId) {
        _episodeResolver = null;
        _episodeBrowser = null;
        _resolverSessionId = '';
      }
      await _closeSession(sessionId);
      return {'ok': true};
    }
    if (const [
      'downloadNativeFntvSubtitle',
      'reportNativeFntvProgress',
      'releaseNativeFntvPlayback',
    ].contains(call.method)) {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final sessionId = args['resolverSessionId'] as String? ?? '';
      final service = _fntvSessions[sessionId];
      if (service == null) return {'ok': false, 'message': '飞牛播放会话已失效'};
      try {
        final target = PlaybackTarget.fromJson(Map<String, dynamic>.from(
          jsonDecode(args['playbackTargetJson'] as String) as Map,
        ));
        if (target.sourceKind != MediaSourceKind.fntv ||
            target.sourceId != service.source.id) {
          return {'ok': false, 'message': '媒体源已变化'};
        }
        if (call.method == 'downloadNativeFntvSubtitle') {
          return await service.downloadSubtitle(
              target, args['subtitleId'] as String);
        }
        if (call.method == 'releaseNativeFntvPlayback') {
          await service.sessions.release(target);
          return {'ok': true};
        }
        await service.client.reportPlaybackProgress(
          source: service.source,
          target: target,
          position: Duration(milliseconds: (args['positionMs'] as num).toInt()),
          duration: Duration(milliseconds: (args['durationMs'] as num).toInt()),
        );
        return {'ok': true};
      } on SubtitleContentException catch (error) {
        return {'ok': false, 'message': error.message};
      } catch (_) {
        return {'ok': false, 'message': '飞牛请求未成功，请检查连接或重新登录'};
      }
    }
    if (call.method == 'saveNativePlaybackSubtitleStyle') {
      final arguments = Map<String, Object?>.from(
        call.arguments as Map<dynamic, dynamic>? ?? const {},
      );
      await _ref
          .read(settingsControllerProvider.notifier)
          .savePlaybackSubtitleStylePreferences(
            subtitleScale: _readDouble(
              arguments,
              'subtitleScale',
              kPlaybackSubtitleScaleDefault,
            ),
            primarySubtitlePosition: _readDouble(
              arguments,
              'primarySubtitlePosition',
              kPlaybackPrimarySubtitlePositionDefault,
            ),
            secondarySubtitlePosition: _readDouble(
              arguments,
              'secondarySubtitlePosition',
              kPlaybackSecondarySubtitlePositionDefault,
            ),
            secondarySubtitleScale: _readDouble(
              arguments,
              'secondarySubtitleScale',
              kPlaybackSecondarySubtitleScaleDefault,
            ),
          );
      return true;
    }
    if (call.method != 'resolveNativePlaybackEpisode' &&
        call.method != 'browseNativePlaybackVersions' &&
        call.method != 'browseNativePlaybackEpisodes') {
      throw MissingPluginException('Unsupported native playback resolver call');
    }
    final arguments = Map<String, Object?>.from(
      call.arguments as Map<dynamic, dynamic>? ?? const {},
    );
    final resolverSessionId =
        arguments['resolverSessionId']?.toString().trim() ?? '';
    final rawTargetJson = arguments['playbackTargetJson']?.toString() ?? '';
    final resolver = _episodeResolver;
    if (resolver == null ||
        resolverSessionId.isEmpty ||
        resolverSessionId != _resolverSessionId ||
        rawTargetJson.trim().isEmpty) {
      return const <String, Object?>{
        'ok': false,
        'message': '原生播放会话已变化，请重新选择剧集。',
      };
    }
    PlaybackTarget? retainedTarget;
    String? preparedTransportUrl;
    NativeFntvService? retainedService;
    try {
      final target = PlaybackTarget.fromJson(
        Map<String, dynamic>.from(jsonDecode(rawTargetJson) as Map),
      );
      if (call.method == 'browseNativePlaybackVersions') {
        final choices = await PlaybackVariantResolver(read: _ref.read)
            .load(target)
            .timeout(const Duration(seconds: 30));
        if (resolverSessionId != _resolverSessionId) {
          return {'ok': false, 'message': '播放会话已失效'};
        }
        return {
          'ok': true,
          'versions': [
            for (final choice in choices)
              {
                'label': playbackVariantLabel(choice),
                'selected': isSamePlaybackVariant(choice, target),
                'playbackTargetJson': jsonEncode(choice.toJson()),
              },
          ],
        };
      }
      if (call.method == 'browseNativePlaybackEpisodes') {
        final browser = _episodeBrowser;
        if (browser == null ||
            target.sourceId != browser.target.sourceId ||
            buildSeriesKeyForTarget(target) !=
                buildSeriesKeyForTarget(browser.target)) {
          return {'ok': false, 'message': '剧集会话已变化'};
        }
        final seasons =
            await browser.loadSeasons().timeout(const Duration(seconds: 30));
        final seasonId = arguments['seasonId']?.toString();
        if (seasonId == null) {
          return {
            'ok': true,
            'seasons': seasons.map((s) => s.toJson()).toList()
          };
        }
        final season = seasons.where((s) => s.id == seasonId).firstOrNull;
        if (season == null) return {'ok': false, 'message': '找不到该季'};
        final queue = await browser
            .loadSeason(season)
            .timeout(const Duration(seconds: 30));
        return {'ok': true, 'queueJson': jsonEncode(queue.toJson())};
      }
      // Keep the owner alive across async resolution so a late result is
      // released even if the native activity closed in the meantime.
      final fntv = _fntvSessions[resolverSessionId];
      if (target.sourceKind == MediaSourceKind.fntv &&
          (fntv == null || fntv.source.id != target.sourceId)) {
        return {'ok': false, 'message': '飞牛播放会话已失效'};
      }
      final resolved = await resolver(target);
      retainedTarget = resolved.target;
      retainedService = fntv;
      await fntv?.sessions.retain(resolved.target);
      if (resolverSessionId != _resolverSessionId ||
          (fntv != null &&
              !identical(_fntvSessions[resolverSessionId], fntv))) {
        await fntv?.sessions.release(resolved.target);
        return {'ok': false, 'message': '播放会话已失效'};
      }
      final resolvedPlaybackItemKey = buildPlaybackItemKey(resolved.target);
      final transport =
          await _prepareTransport(resolverSessionId, resolved.target);
      preparedTransportUrl = transport.streamUrl;
      if (resolverSessionId != _resolverSessionId ||
          !_transports.containsKey(resolverSessionId)) {
        final relay =
            _transports[resolverSessionId]?.remove(transport.streamUrl);
        if (relay != null) await _closeRelay(relay);
        await fntv?.sessions.release(resolved.target);
        retainedTarget = null;
        retainedService = null;
        preparedTransportUrl = null;
        return {'ok': false, 'message': '播放会话已失效'};
      }
      retainedTarget = null;
      retainedService = null;
      preparedTransportUrl = null;
      return <String, Object?>{
        'ok': true,
        'playbackTargetJson': jsonEncode(resolved.target.toJson()),
        'playbackItemKey': resolvedPlaybackItemKey,
        'seriesKey': buildSeriesKeyForTarget(resolved.target),
        'mediaMimeType': transport.container == 'hls'
            ? 'application/x-mpegURL'
            : resolved.mediaMimeType,
        'transportUrl': transport.streamUrl,
        'transportHeaders': transport.headers,
      };
    } catch (error) {
      if (preparedTransportUrl != null) {
        final relay =
            _transports[resolverSessionId]?.remove(preparedTransportUrl);
        if (relay != null) await _closeRelay(relay);
      }
      if (retainedTarget != null) {
        await retainedService?.sessions.release(retainedTarget);
      }
      return <String, Object?>{
        'ok': false,
        'message': '解析剧集失败：$error',
      };
    }
  }

  Map<String, Object?> _handleCacheMethodCall(MethodCall call) {
    final args = Map<String, Object?>.from(call.arguments as Map? ?? const {});
    final sessionId = args['resolverSessionId'];
    final url = args['currentURL'];
    final generation = args['generation'];
    if (sessionId is! String ||
        sessionId.isEmpty ||
        sessionId != _resolverSessionId ||
        url is! String ||
        generation is! int ||
        generation < 0 ||
        _transportUrls[sessionId]?.contains(url) != true) {
      return const {'ok': false};
    }
    final previous = _cacheCursors[sessionId];
    if (previous != null &&
        (generation < previous.generation ||
            (generation == previous.generation && url != previous.url))) {
      return const {'ok': false};
    }
    if (call.method == 'setNativePlaybackActive' && args['active'] is! bool) {
      return const {'ok': false};
    }
    if (call.method == 'setNativePlaybackBufferState' &&
        args['memoryReady'] is! bool) {
      return const {'ok': false};
    }
    _cacheCursors[sessionId] = (generation: generation, url: url);
    final service = _transports[sessionId]?[url];
    final control = service is PlaybackRelayCacheControl
        ? service as PlaybackRelayCacheControl
        : null;
    // Local metadata only: never probe a transport URL to obtain a metric.
    if (call.method == 'setNativePlaybackActive') {
      control?.setPlaybackActive(args['active'] as bool, url: url);
    } else if (call.method == 'setNativePlaybackBufferState') {
      if (service is PlaybackRelayBufferControl) {
        (service as PlaybackRelayBufferControl).updateBufferState(
            memoryReady: args['memoryReady'] as bool, url: url);
      }
    } else if (call.method == 'cancelNativePlaybackReadAhead') {
      control?.cancelReadAhead(url: url);
    }
    final snapshot = call.method == 'nativePlaybackCacheSnapshot'
        ? control?.cacheSnapshot(url: url)
        : null;
    return {
      'ok': true,
      'resolverSessionId': sessionId,
      'currentURL': url,
      'generation': generation,
      'showDiskCache':
          _ref.read(appSettingsProvider).playbackDiskCacheMiB > 0,
      if (snapshot != null) 'storedBytes': snapshot.storedBytes,
      if (snapshot?.forwardBytes != null)
        'forwardBytes': snapshot!.forwardBytes,
      if (snapshot?.disabledReason != null)
        'disabledReason': snapshot!.disabledReason,
    };
  }
}

double _readDouble(
  Map<String, Object?> values,
  String key,
  double fallback,
) {
  return (values[key] as num?)?.toDouble() ?? fallback;
}

void _traceQuarkNativeLaunch(
  String stage, {
  required PlaybackTarget target,
  Map<String, Object?> fields = const <String, Object?>{},
  Object? error,
  StackTrace? stackTrace,
}) {
  if (target.sourceKind.name != 'quark') {
    return;
  }
  appLogError('playback', stage,
      fields: <String, Object?>{
        'title': target.title.trim().isEmpty ? 'Starflow' : target.title.trim(),
        'sourceKind': target.sourceKind.name,
        'container': target.container,
        ...fields,
      },
      error: error,
      stackTrace: stackTrace);
}
