import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

import '../application/live_playback_controller.dart';

class LiveNetworkSpeedLabel extends StatefulWidget {
  const LiveNetworkSpeedLabel(
      {super.key, this.source, required this.generation});

  final LiveNetworkSpeedSource? source;
  final int generation;

  @override
  State<LiveNetworkSpeedLabel> createState() => _LiveNetworkSpeedLabelState();
}

class _LiveNetworkSpeedLabelState extends State<LiveNetworkSpeedLabel> {
  Timer? _timer;
  int _revision = 0;
  int? _pollingRevision;
  String _label = '--';

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(covariant LiveNetworkSpeedLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.source, oldWidget.source) ||
        widget.generation != oldWidget.generation) {
      _restart();
    }
  }

  void _restart() {
    _timer?.cancel();
    ++_revision;
    _label = '--';
    if (widget.source == null) return;
    unawaited(_poll());
    _timer =
        Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_poll()));
  }

  Future<void> _poll() async {
    final revision = _revision;
    if (_pollingRevision == revision) return;
    _pollingRevision = revision;
    int? speed;
    try {
      speed = await widget.source?.readNetworkSpeed(widget.generation);
    } catch (_) {
      // Telemetry is optional and must never interrupt playback.
    } finally {
      if (_pollingRevision == revision) _pollingRevision = null;
    }
    if (!mounted || revision != _revision) return;
    final label = speed == null || speed < 0
        ? '--'
        : speed == 0
            ? '0 B/s'
            : '${formatByteSize(speed)}/s';
    if (label != _label) setState(() => _label = label);
  }

  @override
  void dispose() {
    ++_revision;
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: '网速',
        child: SizedBox(
          width: 104,
          child: Text(_label,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      );
}
