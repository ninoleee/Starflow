import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

class MpvNetworkSpeedLabel extends StatefulWidget {
  const MpvNetworkSpeedLabel({
    super.key,
    required this.player,
    this.visible = true,
  });

  final Player player;
  final bool visible;

  @override
  State<MpvNetworkSpeedLabel> createState() => _MpvNetworkSpeedLabelState();
}

class _MpvNetworkSpeedLabelState extends State<MpvNetworkSpeedLabel> {
  Timer? _timer;
  String _label = '--';
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _syncPolling();
  }

  @override
  void didUpdateWidget(covariant MpvNetworkSpeedLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.player, widget.player) ||
        oldWidget.visible != widget.visible) {
      _syncPolling();
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  void _syncPolling() {
    _stopPolling();
    if (kIsWeb || !widget.visible) {
      return;
    }
    unawaited(_poll());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_poll());
    });
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    if (_polling || !widget.visible) {
      return;
    }
    _polling = true;
    try {
      final native = widget.player.platform;
      final raw = native == null
          ? null
          : await (native as dynamic).getProperty('cache-speed');
      final bytesPerSecond = double.tryParse('$raw')?.round() ?? 0;
      final nextLabel =
          bytesPerSecond > 0 ? '${formatByteSize(bytesPerSecond)}/s' : '0 B/s';
      if (mounted && nextLabel != _label) {
        setState(() {
          _label = nextLabel;
        });
      }
    } catch (_) {
      if (mounted && _label != '--') {
        setState(() {
          _label = '--';
        });
      }
    } finally {
      _polling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const SizedBox.shrink();
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xB310141A),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          _label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
