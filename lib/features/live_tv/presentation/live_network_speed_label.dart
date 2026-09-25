import 'package:flutter/material.dart';
import 'package:starflow/features/playback/presentation/widgets/playback_network_speed_label.dart';

import '../application/live_playback_controller.dart';

class LiveNetworkSpeedLabel extends StatelessWidget {
  const LiveNetworkSpeedLabel({
    super.key,
    this.source,
    required this.generation,
  });

  final LiveNetworkSpeedSource? source;
  final int generation;

  @override
  Widget build(BuildContext context) => PlaybackNetworkSpeedLabel(
        sampleKey: (source, generation),
        readSpeed:
            source == null ? null : () => source!.readNetworkSpeed(generation),
        readCacheBytes: () async {
          final cacheSource = source;
          return cacheSource is LiveCacheSizeSource
              ? (cacheSource as LiveCacheSizeSource).readCacheBytes(generation)
              : null;
        },
        readBufferDurationMs: () async {
          final cacheSource = source;
          return cacheSource is LiveCacheSizeSource
              ? (cacheSource as LiveCacheSizeSource)
                  .readBufferDurationMs(generation)
              : null;
        },
        readFormat: () async {
          final formatSource = source;
          return formatSource is LiveVideoFormatSource
              ? (formatSource as LiveVideoFormatSource)
                  .readVideoFormat(generation)
              : null;
        },
      );
}
