import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starflow/app/theme/app_typography.dart';
import 'package:starflow/features/playback/domain/playback_network_speed.dart';

class PlaybackNetworkSpeedLabel extends StatefulWidget {
  const PlaybackNetworkSpeedLabel({
    super.key,
    required this.sampleKey,
    required this.readSpeed,
    this.readCacheBytes,
    this.readBufferDurationMs,
    this.readFormat,
    this.visible = true,
  });

  final Object sampleKey;
  final Future<int?> Function()? readSpeed;
  final Future<int?> Function()? readCacheBytes;
  final Future<int?> Function()? readBufferDurationMs;
  final Future<String?> Function()? readFormat;
  final bool visible;

  @override
  State<PlaybackNetworkSpeedLabel> createState() =>
      _PlaybackNetworkSpeedLabelState();
}

class _PlaybackNetworkSpeedLabelState extends State<PlaybackNetworkSpeedLabel> {
  Timer? _timer;
  int _revision = 0;
  int? _pollingRevision;
  String _label = '-- · -- · --';
  String _format = '识别中';
  PlaybackNetworkSpeedWindow _window = PlaybackNetworkSpeedWindow();

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(covariant PlaybackNetworkSpeedLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sampleKey != widget.sampleKey ||
        oldWidget.visible != widget.visible ||
        (oldWidget.readSpeed == null) != (widget.readSpeed == null) ||
        (oldWidget.readCacheBytes == null) != (widget.readCacheBytes == null) ||
        (oldWidget.readBufferDurationMs == null) !=
            (widget.readBufferDurationMs == null) ||
        (oldWidget.readFormat == null) != (widget.readFormat == null)) {
      _restart();
    }
  }

  void _restart() {
    _timer?.cancel();
    ++_revision;
    _label = '-- · -- · --';
    _format = '识别中';
    _window = PlaybackNetworkSpeedWindow();
    if (!widget.visible || widget.readSpeed == null) return;
    unawaited(_poll());
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_poll()),
    );
  }

  Future<void> _poll() async {
    final revision = _revision;
    if (_pollingRevision == revision) return;
    final readSpeed = widget.readSpeed;
    if (!widget.visible || readSpeed == null) return;
    _pollingRevision = revision;
    List<Object?> samples;
    try {
      samples = await Future.wait<Object?>([
        _readOptional(readSpeed),
        _readOptional(widget.readCacheBytes),
        _readOptional(widget.readBufferDurationMs),
        _readOptional(widget.readFormat),
      ]);
    } finally {
      if (_pollingRevision == revision) _pollingRevision = null;
    }
    if (!mounted || revision != _revision) return;
    final label = formatPlaybackMetrics(
      _window.add(samples[0] as int?),
      samples[1] as int?,
      samples[2] as int?,
    );
    final rawFormat = (samples[3] as String?)?.trim();
    final format = rawFormat == null || rawFormat.isEmpty ? '识别中' : rawFormat;
    if (label != _label || format != _format) {
      setState(() {
        _label = label;
        _format = format;
      });
    }
  }

  Future<T?> _readOptional<T>(Future<T?> Function()? read) async {
    try {
      return await read?.call().timeout(const Duration(seconds: 2));
    } catch (_) {
      // A failed optional metric must not erase another valid metric.
      return null;
    }
  }

  @override
  void dispose() {
    ++_revision;
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    return Semantics(
      label: '网速、缓存和视频格式',
      child: SizedBox(
        width: 160,
        height: 36,
        child: DefaultTextStyle(
          style: DefaultTextStyle.of(context).style.merge(const TextStyle(
                color: Colors.white,
                fontSize: AppTextSizes.caption,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              )),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                  child: Center(
                      child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_label, maxLines: 1, textAlign: TextAlign.center),
              ))),
              Expanded(
                  child: Center(
                      child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_format, maxLines: 1, textAlign: TextAlign.center),
              ))),
            ],
          ),
        ),
      ),
    );
  }
}
