import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starflow/features/playback/domain/playback_network_speed.dart';

class PlaybackNetworkSpeedLabel extends StatefulWidget {
  const PlaybackNetworkSpeedLabel({
    super.key,
    required this.sampleKey,
    required this.readSpeed,
    this.readCacheBytes,
    this.readDiskCacheBytes,
    this.readBufferDurationMs,
    this.readFormat,
    this.memoryCacheLabel = '',
    this.visible = true,
  });

  final Object sampleKey;
  final Future<int?> Function()? readSpeed;
  final Future<int?> Function()? readCacheBytes;
  final Future<int?> Function()? readDiskCacheBytes;
  final Future<int?> Function()? readBufferDurationMs;
  final Future<String?> Function()? readFormat;
  final String memoryCacheLabel;
  final bool visible;

  @override
  State<PlaybackNetworkSpeedLabel> createState() =>
      _PlaybackNetworkSpeedLabelState();
}

class _PlaybackNetworkSpeedLabelState extends State<PlaybackNetworkSpeedLabel>
    with WidgetsBindingObserver {
  static const double _metricsWidth = 160;
  static const double _metricsFontSize = 10;

  bool _foreground = true;
  bool _routeVisible = true;
  Timer? _timer;
  int _revision = 0;
  int? _pollingRevision;
  String _label = '-- · -- · --';
  String _format = '识别中';
  PlaybackNetworkSpeedWindow _window = PlaybackNetworkSpeedWindow();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _restart();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.isCurrentOf(context) ?? true;
    if (_routeVisible != visible) {
      _routeVisible = visible;
      _restart();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _restart();
  }

  @override
  void didUpdateWidget(covariant PlaybackNetworkSpeedLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sampleKey != widget.sampleKey ||
        oldWidget.visible != widget.visible ||
        (oldWidget.readSpeed == null) != (widget.readSpeed == null) ||
        (oldWidget.readCacheBytes == null) != (widget.readCacheBytes == null) ||
        (oldWidget.readDiskCacheBytes == null) !=
            (widget.readDiskCacheBytes == null) ||
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
    if (!widget.visible ||
        !_foreground ||
        !_routeVisible ||
        widget.readSpeed == null) {
      return;
    }
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
    if (!widget.visible ||
        !_foreground ||
        !_routeVisible ||
        readSpeed == null) {
      return;
    }
    _pollingRevision = revision;
    List<Object?> samples;
    try {
      samples = await Future.wait<Object?>([
        _readOptional(readSpeed),
        _readOptional(widget.readCacheBytes),
        _readOptional(widget.readDiskCacheBytes),
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
      samples[3] as int?,
      diskCacheBytes: samples[2] as int?,
      showDiskCache: widget.readDiskCacheBytes != null,
      memoryCacheLabel: widget.memoryCacheLabel,
    );
    final rawFormat = (samples[4] as String?)?.trim();
    final format = rawFormat == null || rawFormat.isEmpty ? '识别中' : rawFormat;
    if (label != _label || format != _format) {
      setState(() {
        _label = label;
        _format = format;
      });
    }
  }

  TextStyle _metricsTextStyle() {
    return DefaultTextStyle.of(context).style.merge(const TextStyle(
          color: Colors.white,
          fontSize: _metricsFontSize,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ));
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
    WidgetsBinding.instance.removeObserver(this);
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
        width: _metricsWidth,
        height: 36,
        child: DefaultTextStyle(
          style: _metricsTextStyle(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                  child: Center(
                      child: Text(
                _label,
                style: _metricsTextStyle(),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                textAlign: TextAlign.center,
              ))),
              Expanded(
                  child: Center(
                      child: Text(
                _format,
                style: _metricsTextStyle(),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                textAlign: TextAlign.center,
              ))),
            ],
          ),
        ),
      ),
    );
  }
}
