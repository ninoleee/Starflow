import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key, required this.target});

  final PlaybackTarget target;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  static const int _maxPlaybackAttempts = 3;

  Player? _player;
  VideoController? _videoController;
  StreamSubscription<String>? _playerErrorSubscription;
  PlaybackTarget? _resolvedTarget;
  _StartupProbeResult _startupProbe = const _StartupProbeResult();
  Object? _error;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    unawaited(_playerErrorSubscription?.cancel());
    final player = _player;
    _player = null;
    unawaited(player?.dispose());
    super.dispose();
  }

  Future<void> _initialize() async {
    if (!widget.target.canPlay) {
      setState(() {
        _error = '没有可播放的流地址';
      });
      return;
    }

    try {
      final resolvedTarget = await _resolveTarget(widget.target);
      if (mounted) {
        setState(() {
          _resolvedTarget = resolvedTarget;
        });
      }
      unawaited(_runStartupProbe(resolvedTarget));
      final timeoutSeconds = ref
          .read(appSettingsProvider)
          .playbackOpenTimeoutSeconds
          .clamp(1, 600);
      final playback = await _openWithRetry(
        resolvedTarget,
        timeout: Duration(seconds: timeoutSeconds),
      );

      if (!mounted) {
        await playback.errorSubscription.cancel();
        await playback.player.dispose();
        return;
      }

      _playerErrorSubscription = playback.errorSubscription;
      setState(() {
        _player = playback.player;
        _videoController = playback.videoController;
        _isReady = true;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _buildPlaybackErrorMessage(error);
      });
    }
  }

  Future<_OpenedPlayback> _openWithRetry(
    PlaybackTarget resolvedTarget, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    Object? lastError;

    for (var attempt = 1; attempt <= _maxPlaybackAttempts; attempt++) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        break;
      }

      try {
        return await _openSingleAttempt(
          resolvedTarget,
          timeout: remaining,
        );
      } catch (error) {
        lastError = error;
        if (attempt >= _maxPlaybackAttempts) {
          break;
        }
      }
    }

    if (deadline.difference(DateTime.now()) <= Duration.zero) {
      throw TimeoutException('超过最大等待时间，已停止尝试播放');
    }
    throw lastError ?? const _PlayerOpenException('播放打开失败');
  }

  Future<_OpenedPlayback> _openSingleAttempt(
    PlaybackTarget resolvedTarget, {
    required Duration timeout,
  }) async {
    final player = Player(
      configuration: const PlayerConfiguration(
        title: 'Starflow',
        logLevel: MPVLogLevel.warn,
      ),
    );
    final videoController = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        hwdec: 'auto-safe',
        enableHardwareAcceleration: true,
      ),
    );
    final startupError = Completer<String>();
    var awaitingStartup = true;
    late final StreamSubscription<String> errorSubscription;
    errorSubscription = player.stream.error.listen((message) {
      final normalized = message.trim();
      if (normalized.isEmpty) {
        return;
      }
      if (awaitingStartup && !startupError.isCompleted) {
        startupError.complete(normalized);
        return;
      }
      if (!mounted || _player != player) {
        return;
      }
      setState(() {
        _error = normalized;
      });
    });

    try {
      await Future.any<void>([
        player.open(
          Media(
            resolvedTarget.streamUrl,
            httpHeaders: resolvedTarget.headers,
          ),
          play: true,
        ),
        startupError.future.then<void>((message) {
          throw _PlayerOpenException(message);
        }),
      ]).timeout(timeout);
      awaitingStartup = false;
      return _OpenedPlayback(
        player: player,
        videoController: videoController,
        errorSubscription: errorSubscription,
      );
    } catch (_) {
      await errorSubscription.cancel();
      await player.dispose();
      rethrow;
    }
  }

  String _buildPlaybackErrorMessage(Object error) {
    if (error is TimeoutException) {
      return error.message ?? '超过最大等待时间，已停止尝试播放';
    }
    if (error is _PlayerOpenException) {
      return error.message;
    }
    return '$error';
  }

  Future<PlaybackTarget> _resolveTarget(PlaybackTarget target) async {
    if (!target.needsResolution) {
      return target;
    }

    final settings = ref.read(appSettingsProvider);
    MediaSourceConfig? source;
    for (final candidate in settings.mediaSources) {
      if (candidate.id == target.sourceId) {
        source = candidate;
        break;
      }
    }

    if (source == null || !source.hasActiveSession) {
      throw const EmbyApiException('Emby 会话已失效，请重新登录');
    }

    return ref.read(embyApiClientProvider).resolvePlaybackTarget(
          source: source,
          target: target,
        );
  }

  Future<void> _runStartupProbe(PlaybackTarget target) async {
    final probe = await _probeStartup(target);
    if (!mounted) {
      return;
    }
    setState(() {
      _startupProbe = probe;
    });
  }

  Future<_StartupProbeResult> _probeStartup(PlaybackTarget target) async {
    final streamUrl = target.streamUrl.trim();
    if (streamUrl.isEmpty) {
      return const _StartupProbeResult();
    }

    final uri = Uri.tryParse(streamUrl);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return const _StartupProbeResult();
    }

    final client = http.Client();
    StreamSubscription<List<int>>? subscription;
    final completer = Completer<_StartupProbeResult>();
    final stopwatch = Stopwatch();
    var completed = false;
    var bytesRead = 0;

    Future<void> finish() async {
      if (completed) {
        return;
      }
      completed = true;
      stopwatch.stop();
      await subscription?.cancel();
      client.close();

      final elapsedSeconds = stopwatch.elapsedMilliseconds <= 0
          ? 0.0
          : stopwatch.elapsedMilliseconds / 1000;
      final speedBytesPerSecond = elapsedSeconds <= 0 || bytesRead <= 0
          ? null
          : (bytesRead / elapsedSeconds).round();

      completer.complete(
        _StartupProbeResult(
          estimatedSpeedBytesPerSecond: speedBytesPerSecond,
        ),
      );
    }

    try {
      final request = http.Request('GET', uri)
        ..headers.addAll(target.headers)
        ..headers['Range'] = 'bytes=0-262143';
      stopwatch.start();
      final response = await client.send(request).timeout(
            const Duration(seconds: 4),
          );

      subscription = response.stream.listen(
        (chunk) {
          bytesRead += chunk.length;
          if (bytesRead >= 192 * 1024 ||
              stopwatch.elapsedMilliseconds >= 1400) {
            unawaited(finish());
          }
        },
        onError: (_) {
          unawaited(finish());
        },
        onDone: () {
          unawaited(finish());
        },
        cancelOnError: true,
      );

      return completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () async {
          await finish();
          return completer.future;
        },
      );
    } catch (_) {
      await subscription?.cancel();
      client.close();
      return const _StartupProbeResult();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeTarget = _resolvedTarget ?? widget.target;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: Colors.black,
            child: Center(
              child: AspectRatio(
                aspectRatio: _currentAspectRatio(),
                child: _buildVideoSurface(theme),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.62),
                    Colors.black.withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: OverlayToolbar(
                onBack: () => context.pop(),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.16),
                      Colors.black.withValues(alpha: 0.62),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 40, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          activeTarget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${activeTarget.sourceKind.label} · ${activeTarget.sourceName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xCCFFFFFF),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _currentAspectRatio() {
    final player = _player;
    if (!_isReady || player == null) {
      return 16 / 9;
    }

    final width = player.state.width ?? 0;
    final height = player.state.height ?? 0;
    if (width <= 0 || height <= 0) {
      return 16 / 9;
    }
    return width / height;
  }

  Widget _buildVideoSurface(ThemeData theme) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '播放失败：$_error',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white),
          ),
        ),
      );
    }

    final player = _player;
    final videoController = _videoController;
    if (!_isReady || player == null || videoController == null) {
      return _PlayerStartupOverlay(
        target: _resolvedTarget ?? widget.target,
        probe: _startupProbe,
      );
    }

    return StreamBuilder<int?>(
      stream: player.stream.width,
      initialData: player.state.width,
      builder: (context, widthSnapshot) {
        return StreamBuilder<int?>(
          stream: player.stream.height,
          initialData: player.state.height,
          builder: (context, heightSnapshot) {
            final width = widthSnapshot.data ?? 0;
            final height = heightSnapshot.data ?? 0;
            final aspectRatio =
                width > 0 && height > 0 ? width / height : 16 / 9;
            return ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: aspectRatio,
                      child: Video(
                        controller: videoController,
                        controls: AdaptiveVideoControls,
                        fill: Colors.black,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  StreamBuilder<bool>(
                    stream: player.stream.buffering,
                    initialData: player.state.buffering,
                    builder: (context, bufferingSnapshot) {
                      final isBuffering = bufferingSnapshot.data ?? false;
                      if (!isBuffering) {
                        return const SizedBox.shrink();
                      }
                      return StreamBuilder<double>(
                        stream: player.stream.bufferingPercentage,
                        initialData: player.state.bufferingPercentage,
                        builder: (context, progressSnapshot) {
                          return IgnorePointer(
                            child: _PlayerStartupOverlay(
                              target: _resolvedTarget ?? widget.target,
                              probe: _startupProbe,
                              bufferingProgress: progressSnapshot.data,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _PlayerStartupOverlay extends StatelessWidget {
  const _PlayerStartupOverlay({
    required this.target,
    required this.probe,
    this.bufferingProgress,
  });

  final PlaybackTarget target;
  final _StartupProbeResult probe;
  final double? bufferingProgress;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Colors.white,
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
          right: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StartupMetricText(
                label: '网速',
                value: probe.speedLabel.isEmpty ? '测速中' : probe.speedLabel,
              ),
              const SizedBox(height: 6),
              _StartupMetricText(
                label: '格式',
                value: _buildFormatValue(target),
              ),
              if (_normalizeBufferProgress(bufferingProgress)
                  case final progress?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: 108,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 2.5,
                        value: progress,
                        color: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static double? _normalizeBufferProgress(double? value) {
    final progress = value ?? 0;
    if (progress <= 0) {
      return null;
    }
    if (progress > 1) {
      return (progress / 100).clamp(0.0, 1.0);
    }
    return progress.clamp(0.0, 1.0);
  }

  static String _buildFormatValue(PlaybackTarget target) {
    final parts = <String>[
      if (target.resolutionLabel.isNotEmpty) target.resolutionLabel,
      if (target.formatLabel.isNotEmpty) target.formatLabel,
      if (target.bitrateLabel.isNotEmpty) target.bitrateLabel,
    ];
    if (parts.isEmpty) {
      return '识别中';
    }
    return parts.join(' · ');
  }
}

class _StartupMetricText extends StatelessWidget {
  const _StartupMetricText({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      textAlign: TextAlign.right,
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              shadows: const [
                Shadow(
                  color: Color(0xA6000000),
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              shadows: [
                Shadow(
                  color: Color(0xB8000000),
                  blurRadius: 12,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StartupProbeResult {
  const _StartupProbeResult({
    this.estimatedSpeedBytesPerSecond,
  });

  final int? estimatedSpeedBytesPerSecond;

  String get speedLabel {
    final speed = estimatedSpeedBytesPerSecond ?? 0;
    if (speed <= 0) {
      return '';
    }
    return '${formatByteSize(speed)}/s';
  }
}

class _OpenedPlayback {
  const _OpenedPlayback({
    required this.player,
    required this.videoController,
    required this.errorSubscription,
  });

  final Player player;
  final VideoController videoController;
  final StreamSubscription<String> errorSubscription;
}

class _PlayerOpenException implements Exception {
  const _PlayerOpenException(this.message);

  final String message;

  @override
  String toString() => message;
}
