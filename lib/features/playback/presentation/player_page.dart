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

      final player = Player();
      final videoController = VideoController(player);
      _playerErrorSubscription = player.stream.error.listen((message) {
        if (!mounted || message.trim().isEmpty) {
          return;
        }
        setState(() {
          _error = message.trim();
        });
      });

      await player.open(
        Media(
          resolvedTarget.streamUrl,
          httpHeaders: resolvedTarget.headers,
        ),
        play: true,
      );

      if (!mounted) {
        await _playerErrorSubscription?.cancel();
        await player.dispose();
        return;
      }

      setState(() {
        _player = player;
        _videoController = videoController;
        _isReady = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
      });
    }
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
    int? totalBytes;

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
          fileSizeBytes: totalBytes,
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
      totalBytes = _resolveResponseTotalBytes(
        response.headers,
        fallbackContentLength: response.contentLength,
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
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.28),
                              ),
                              child: _PlayerStartupOverlay(
                                target: _resolvedTarget ?? widget.target,
                                probe: _startupProbe,
                                bufferingProgress: progressSnapshot.data,
                              ),
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
    final theme = Theme.of(context);
    final infoItems = <_StartupInfoItem>[
      _StartupInfoItem(
        label: '网速',
        value: probe.speedLabel.isEmpty ? '测速中' : probe.speedLabel,
      ),
      _StartupInfoItem(
        label: '格式',
        value: _buildFormatValue(target),
      ),
      _StartupInfoItem(
        label: '大小',
        value: _buildSizeValue(target, probe),
      ),
    ];
    final progressValue = _normalizeBufferProgress(bufferingProgress);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0x78101723),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '正在准备播放',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    target.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${target.sourceKind.label} · ${target.sourceName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xCCFFFFFF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (progressValue != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 4,
                        value: progressValue,
                        color: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final item in infoItems)
                        _StartupMetricChip(item: item),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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

  static String _buildSizeValue(
    PlaybackTarget target,
    _StartupProbeResult probe,
  ) {
    final label = target.fileSizeLabel.isNotEmpty
        ? target.fileSizeLabel
        : probe.fileSizeLabel;
    return label.isEmpty ? '未知' : label;
  }
}

class _StartupMetricChip extends StatelessWidget {
  const _StartupMetricChip({required this.item});

  final _StartupInfoItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 96, maxWidth: 164),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.label,
            style: const TextStyle(
              color: Color(0xB3FFFFFF),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _StartupInfoItem {
  const _StartupInfoItem({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

class _StartupProbeResult {
  const _StartupProbeResult({
    this.estimatedSpeedBytesPerSecond,
    this.fileSizeBytes,
  });

  final int? estimatedSpeedBytesPerSecond;
  final int? fileSizeBytes;

  String get speedLabel {
    final speed = estimatedSpeedBytesPerSecond ?? 0;
    if (speed <= 0) {
      return '';
    }
    return '${formatByteSize(speed)}/s';
  }

  String get fileSizeLabel => formatByteSize(fileSizeBytes);
}

int? _resolveResponseTotalBytes(
  Map<String, String> headers, {
  int? fallbackContentLength,
}) {
  final contentRange = headers['content-range'] ?? headers['Content-Range'];
  if (contentRange != null) {
    final slashIndex = contentRange.lastIndexOf('/');
    if (slashIndex >= 0 && slashIndex < contentRange.length - 1) {
      final total = int.tryParse(contentRange.substring(slashIndex + 1).trim());
      if (total != null && total > 0) {
        return total;
      }
    }
  }

  final contentLength = fallbackContentLength ?? 0;
  if (contentLength > 0) {
    return contentLength;
  }

  final rawHeader = headers['content-length'] ?? headers['Content-Length'];
  final parsedHeader = int.tryParse((rawHeader ?? '').trim());
  if (parsedHeader != null && parsedHeader > 0) {
    return parsedHeader;
  }

  return null;
}
