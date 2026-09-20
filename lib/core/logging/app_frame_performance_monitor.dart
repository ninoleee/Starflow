import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:starflow/core/logging/app_log_api.dart';
import 'package:starflow/core/logging/app_logger.dart';

const Duration kDefaultLongFrameThreshold = Duration(milliseconds: 250);

class AppFramePerformanceMonitor {
  AppFramePerformanceMonitor({
    required this.startupStopwatch,
    this.longFrameThreshold = kDefaultLongFrameThreshold,
    AppLogService? logger,
    DateTime Function()? clock,
  })  : _logger = logger ?? appLogger,
        _clock = clock ?? DateTime.now;

  final Stopwatch startupStopwatch;
  final Duration longFrameThreshold;
  final AppLogService _logger;
  final DateTime Function() _clock;
  bool _installed = false;
  final List<int> _buildSamples = [];
  final List<int> _rasterSamples = [];
  DateTime? _sampleStarted;

  void install() {
    if (_installed) {
      return;
    }
    _installed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_installed || !_logger.isRecording(AppLogLevel.info)) return;
      _logger.log(
        AppLogLevel.info,
        'app.performance',
        'First Flutter frame rendered',
        fields: <String, Object?>{
          'startupElapsedMs': startupStopwatch.elapsedMilliseconds,
        },
      );
    });
    WidgetsBinding.instance.addTimingsCallback(recordTimings);
  }

  void dispose() {
    if (!_installed) return;
    _installed = false;
    WidgetsBinding.instance.removeTimingsCallback(recordTimings);
    _clearSamples();
  }

  void _clearSamples() {
    _buildSamples.clear();
    _rasterSamples.clear();
    _sampleStarted = null;
  }

  @visibleForTesting
  void recordTimings(List<FrameTiming> timings) {
    if (_logger.isRecording(AppLogLevel.info)) {
      _recordSamples(timings);
    } else {
      _clearSamples();
    }
    if (!_logger.isRecording(AppLogLevel.warning)) return;
    var longFrameCount = 0;
    FrameTiming? worst;
    for (final timing in timings) {
      if (timing.totalSpan < longFrameThreshold) continue;
      longFrameCount++;
      if (worst == null || timing.totalSpan > worst.totalSpan) worst = timing;
    }
    if (worst == null) return;
    _logger.log(
      AppLogLevel.warning,
      'app.performance',
      'Long Flutter frame detected',
      fields: <String, Object?>{
        'longFrameCount': longFrameCount,
        'sampledFrameCount': timings.length,
        'thresholdMs': longFrameThreshold.inMilliseconds,
        'worstTotalMs': worst.totalSpan.inMicroseconds / 1000,
        'worstBuildMs': worst.buildDuration.inMicroseconds / 1000,
        'worstRasterMs': worst.rasterDuration.inMicroseconds / 1000,
      },
    );
  }

  void _recordSamples(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    final now = _clock();
    _sampleStarted ??= now;
    for (final timing in timings) {
      _buildSamples.add(timing.buildDuration.inMicroseconds);
      _rasterSamples.add(timing.rasterDuration.inMicroseconds);
    }
    if (_buildSamples.length >= 600 ||
        now.difference(_sampleStarted!) >= const Duration(seconds: 30)) {
      _buildSamples.sort();
      _rasterSamples.sort();
      double percentile(List<int> values, double fraction) =>
          values[((values.length * fraction).ceil() - 1)
              .clamp(0, values.length - 1)] /
          1000;
      if (_buildSamples.isNotEmpty) {
        _logger.log(AppLogLevel.info, 'app.performance', 'Flutter frame sample',
            fields: {
              'frameCount': _buildSamples.length,
              'buildP50Ms': percentile(_buildSamples, 0.5),
              'buildP95Ms': percentile(_buildSamples, 0.95),
              'rasterP50Ms': percentile(_rasterSamples, 0.5),
              'rasterP95Ms': percentile(_rasterSamples, 0.95),
              'buildOver16ms':
                  _buildSamples.where((value) => value > 16667).length,
              'rasterOver16ms':
                  _rasterSamples.where((value) => value > 16667).length,
              'buildOver33ms':
                  _buildSamples.where((value) => value > 33333).length,
              'rasterOver33ms':
                  _rasterSamples.where((value) => value > 33333).length,
            });
      }
      _clearSamples();
    }
  }
}
