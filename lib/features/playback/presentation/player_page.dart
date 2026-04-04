import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:video_player/video_player.dart';

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key, required this.target});

  final PlaybackTarget target;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  VideoPlayerController? _controller;
  PlaybackTarget? _resolvedTarget;
  Object? _error;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
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
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(resolvedTarget.streamUrl),
        httpHeaders: resolvedTarget.headers,
      );
      controller.addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
      await controller.initialize();
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _resolvedTarget = resolvedTarget;
        _controller = controller;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;
    final activeTarget = _resolvedTarget ?? widget.target;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          AppPageBackground(
            child: ListView(
          padding: const EdgeInsets.only(top: kToolbarHeight),
          children: [
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFF081120),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Builder(
                builder: (context) {
                  final aspectRatio = controller != null &&
                          controller.value.isInitialized &&
                          controller.value.aspectRatio > 0
                      ? controller.value.aspectRatio
                      : 16 / 9;
                  return AspectRatio(
                    aspectRatio: aspectRatio,
                    child: _buildVideoSurface(theme, controller),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SectionPanel(
              title: '播放目标',
              subtitle: '当前会直接使用系统播放器播放流地址',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    label: '来源',
                    value:
                        '${activeTarget.sourceKind.label} · ${activeTarget.sourceName}',
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    label: '流地址',
                    value: activeTarget.streamUrl.trim().isEmpty
                        ? '正在向 Emby 申请播放地址'
                        : activeTarget.streamUrl,
                  ),
                  if (activeTarget.subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _InfoRow(label: '简介', value: activeTarget.subtitle),
                  ],
                ],
              ),
            ),
          ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: OverlayToolbar(
              onBack: () => context.pop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoSurface(
    ThemeData theme,
    VideoPlayerController? controller,
  ) {
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

    if (!_isReady || controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        Positioned.fill(child: VideoPlayer(controller)),
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  if (controller.value.isPlaying) {
                    controller.pause();
                  } else {
                    controller.play();
                  }
                });
              },
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: controller.value.isPlaying ? 0 : 1,
                child: Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 42,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Column(
            children: [
              VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: theme.colorScheme.primary,
                  bufferedColor: Colors.white38,
                  backgroundColor: Colors.white24,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      setState(() {
                        if (controller.value.isPlaying) {
                          controller.pause();
                        } else {
                          controller.play();
                        }
                      });
                    },
                    icon: Icon(
                      controller.value.isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_formatDuration(controller.value.position)} / ${_formatDuration(controller.value.duration)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inMilliseconds <= 0) {
      return '00:00';
    }
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        SelectableText(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
        ),
      ],
    );
  }
}
