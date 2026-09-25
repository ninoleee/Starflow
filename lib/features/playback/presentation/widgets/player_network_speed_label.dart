import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:starflow/features/playback/data/mpv_playback_format.dart';
import 'package:starflow/features/playback/domain/playback_network_speed.dart';

import 'playback_network_speed_label.dart';

class MpvNetworkSpeedLabel extends StatelessWidget {
  const MpvNetworkSpeedLabel({
    super.key,
    required this.player,
    this.generation = 0,
    this.visible = true,
  });

  final Player player;
  final int generation;
  final bool visible;

  Future<int?> _readSpeed() async {
    final native = player.platform;
    if (native is! NativePlayer) return null;
    final raw = await native.getProperty('cache-speed');
    return parsePlaybackByteCount(raw);
  }

  Future<int?> _readCacheBytes() async {
    final native = player.platform;
    if (native is! NativePlayer) return null;
    return parsePlaybackByteCount(
      await native.getProperty('demuxer-cache-state/fw-bytes'),
    );
  }

  Future<int?> _readBufferDurationMs() async {
    final native = player.platform;
    if (native is! NativePlayer) return null;
    return parsePlaybackDurationMilliseconds(
      await native.getProperty('demuxer-cache-duration'),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    return PlaybackNetworkSpeedLabel(
      sampleKey: (player, generation),
      readSpeed: _readSpeed,
      readCacheBytes: _readCacheBytes,
      readBufferDurationMs: _readBufferDurationMs,
      readFormat: () async {
        final native = player.platform;
        return native is NativePlayer
            ? readMpvPlaybackFormat(native.getProperty)
            : null;
      },
      visible: visible,
    );
  }
}
