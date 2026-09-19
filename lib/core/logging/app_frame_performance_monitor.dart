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
  final List<int> _buildSamples = [];
  final List<int> _rasterSamples = [];
  DateTime _sampleStarted = DateTime.now();

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
    for (final timing in timings) {
      _buildSamples.add(timing.buildDuration.inMicroseconds);
      _rasterSamples.add(timing.rasterDuration.inMicroseconds);
    }
    final now = DateTime.now();
    if (_buildSamples.length >= 600 ||
        now.difference(_sampleStarted) >= const Duration(seconds: 30)) {
      _buildSamples.sort();
      _rasterSamples.sort();
      double percentile(List<int> values, double fraction) =>
          values[((values.length * fraction).ceil() - 1).clamp(0, values.length - 1)] / 1000;
      if (_buildSamples.isNotEmpty) {
        appLogInfo('app.performance', 'Flutter frame sample', fields: {
          'frameCount': _buildSamples.length,
          'buildP50Ms': percentile(_buildSamples, 0.5),
          'buildP95Ms': percentile(_buildSamples, 0.95),
          'rasterP50Ms': percentile(_rasterSamples, 0.5),
          'rasterP95Ms': percentile(_rasterSamples, 0.95),
          'buildOver16ms': _buildSamples.where((value) => value > 16667).length,
          'rasterOver16ms': _rasterSamples.where((value) => value > 16667).length,
          'buildOver33ms': _buildSamples.where((value) => value > 33333).length,
          'rasterOver33ms': _rasterSamples.where((value) => value > 33333).length,
        });
      }
      _buildSamples.clear();
      _rasterSamples.clear();
      _sampleStarted = now;
    }
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
