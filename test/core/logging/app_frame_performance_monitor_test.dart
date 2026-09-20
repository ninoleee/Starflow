import 'dart:collection';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/logging/app_frame_performance_monitor.dart';
import 'package:starflow/core/logging/app_log_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('disabled logging and error-only recording do not inspect frames', () {
    final logger = _Logger()..isEnabled = false;
    final monitor = AppFramePerformanceMonitor(
      startupStopwatch: Stopwatch(),
      logger: logger,
      clock: () => throw StateError('Unneeded sampling clock'),
    );
    monitor.recordTimings(_UnreadableFrames());
    logger.isEnabled = true;
    logger.recordedLevels = {AppLogLevel.error};
    monitor.recordTimings(_UnreadableFrames());
    expect(logger.entries, isEmpty);
  });

  test('warning-only recording does not sample and preserves long-frame alert',
      () {
    final logger = _Logger()..recordedLevels = {AppLogLevel.warning};
    final monitor = AppFramePerformanceMonitor(
      startupStopwatch: Stopwatch(),
      logger: logger,
      clock: () => throw StateError('Unneeded sampling clock'),
    );
    monitor.recordTimings([_frame(300000, 1000), _frame(1000, 2000)]);
    expect(logger.entries.single.level, AppLogLevel.warning);
    expect(logger.entries.single.fields['longFrameCount'], 1);
    expect(logger.entries.single.fields['worstBuildMs'], 300);
  });

  test('info samples clear on disable and resume with a fresh window', () {
    final logger = _Logger()..recordedLevels = {AppLogLevel.info};
    var now = DateTime(2026, 9, 20);
    final monitor = AppFramePerformanceMonitor(
      startupStopwatch: Stopwatch(),
      logger: logger,
      clock: () => now,
    );
    monitor.recordTimings(List.filled(599, _frame(300000, 1000)));
    logger.isEnabled = false;
    monitor.recordTimings(_UnreadableFrames());
    now = now.add(const Duration(minutes: 1));
    logger.isEnabled = true;
    monitor.recordTimings([_frame(1000, 2000)]);
    expect(logger.entries, isEmpty);
    now = now.add(const Duration(seconds: 30));
    monitor.recordTimings([_frame(3000, 4000)]);
    expect(logger.entries.single.fields['frameCount'], 2);
    expect(logger.entries.single.fields['buildP95Ms'], 3);
    expect(logger.entries.single.fields['rasterP50Ms'], 2);
    expect(logger.entries.single.fields['buildOver16ms'], 0);
  });

  test('600 frames emit a sample without a warning when warning is disabled',
      () {
    final logger = _Logger()..recordedLevels = {AppLogLevel.info};
    final monitor = AppFramePerformanceMonitor(
      startupStopwatch: Stopwatch(),
      logger: logger,
    );
    monitor.recordTimings(List.filled(600, _frame(300000, 34000)));
    expect(logger.entries.single.fields['frameCount'], 600);
    expect(logger.entries.single.fields['rasterOver33ms'], 600);
    expect(logger.entries.single.level, AppLogLevel.info);
  });

  testWidgets('dispose suppresses a pending startup record', (tester) async {
    final logger = _Logger();
    final monitor = AppFramePerformanceMonitor(
      startupStopwatch: Stopwatch(),
      logger: logger,
    );
    monitor.install();
    monitor.dispose();
    await tester.pump();
    expect(logger.entries, isEmpty);
  });
}

FrameTiming _frame(int build, int raster) => FrameTiming(
      vsyncStart: 0,
      buildStart: 0,
      buildFinish: build,
      rasterStart: build,
      rasterFinish: build + raster,
      rasterFinishWallTime: 0,
    );

class _UnreadableFrames extends ListBase<FrameTiming> {
  @override
  int get length => throw StateError('Frames should not be inspected');
  @override
  set length(int value) => throw UnimplementedError();
  @override
  FrameTiming operator [](int index) => throw UnimplementedError();
  @override
  void operator []=(int index, FrameTiming value) => throw UnimplementedError();
}

class _Logger implements AppLogService {
  @override
  bool isEnabled = true;
  @override
  Set<AppLogLevel> recordedLevels = AppLogLevel.values.toSet();
  final entries = <AppLogEntry>[];
  @override
  void log(
    AppLogLevel level,
    String category,
    String message, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    entries.add(AppLogEntry(
        timestamp: DateTime.now(),
        level: level,
        category: category,
        message: message,
        fields: fields));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
