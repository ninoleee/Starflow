import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:starflow/core/logging/app_logger.dart';

const Duration kDefaultLongFrameThreshold = Duration(milliseconds: 250);

class AppFramePerformanceMonitor {
  AppFramePerformanceMonitor({
    required this.startupStopwatch,
    this.longFrameThreshold = kDefaultLongFrameThreshold,
  });

  final Stopwatch startupStopwatch;
  final Duration longFrameThreshold;
  bool _installed = false;

  void install() {
    if (_installed) {
      return;
    }
    _installed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appLogInfo(
        'app.performance',
        'First Flutter frame rendered',
        fields: <String, Object?>{
          'startupElapsedMs': startupStopwatch.elapsedMilliseconds,
        },
      );
    });
    WidgetsBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    final longFrames = timings
        .where((timing) => timing.totalSpan >= longFrameThreshold)
        .toList(growable: false);
    if (longFrames.isEmpty) {
      return;
    }
    final worst = longFrames.reduce(
      (left, right) => left.totalSpan >= right.totalSpan ? left : right,
    );
    appLogWarning(
      'app.performance',
      'Long Flutter frame detected',
      fields: <String, Object?>{
        'longFrameCount': longFrames.length,
        'sampledFrameCount': timings.length,
        'thresholdMs': longFrameThreshold.inMilliseconds,
        'worstTotalMs': worst.totalSpan.inMicroseconds / 1000,
        'worstBuildMs': worst.buildDuration.inMicroseconds / 1000,
        'worstRasterMs': worst.rasterDuration.inMicroseconds / 1000,
      },
    );
  }
}
