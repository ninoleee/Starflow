import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:starflow/app/app.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/logging/app_frame_performance_monitor.dart';
import 'package:starflow/core/network/network_proxy_runtime.dart';
import 'package:starflow/core/state/riverpod_retry.dart';
import 'package:starflow/features/bootstrap/application/startup_crash_recovery.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

Future<void> main() async {
  final startupStopwatch = Stopwatch()..start();
  final startup = runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      Object? settingsLoadError;
      StackTrace? settingsLoadStackTrace;
      try {
        final initialSettings = await LocalAppSettingsRepository().load();
        networkProxyRuntime.configure(initialSettings.networkProxy);
        await appLogger.configure(
          enabled: initialSettings.localLoggingEnabled,
          maxBytes: initialSettings.localLogMaxSizeMb * 1024 * 1024,
          recordedLevels: initialSettings.localLogRecordedLevels,
        );
      } catch (error, stackTrace) {
        settingsLoadError = error;
        settingsLoadStackTrace = stackTrace;
        await appLogger
            .configure(
              enabled: true,
              maxBytes: kLocalLogMaxSizeMbDefault * 1024 * 1024,
              recordedLevels: kDefaultLocalLogRecordedLevels,
            )
            .catchError((Object _) {});
      }
      _installGlobalErrorLogging();
      AppFramePerformanceMonitor(
        startupStopwatch: startupStopwatch,
      ).install();
      appLogInfo(
        'app.lifecycle',
        'Application startup',
        fields: await _resolveBuildInfoFields(),
      );
      if (settingsLoadError != null) {
        appLogWarning(
          'app.startup',
          'Could not load logging preferences; defaults are active',
          error: settingsLoadError,
          stackTrace: settingsLoadStackTrace,
        );
      }

      final recoveredFromUncleanStartup =
          await startupCrashRecovery.beginStartup().catchError((Object error) {
        appLogWarning(
          'app.startup',
          'Startup crash recovery could not begin',
          error: error,
        );
        return false;
      });
      if (recoveredFromUncleanStartup) {
        appLogWarning(
          'app.startup',
          'Temporary startup recovery activated',
          fields: const <String, Object?>{
            'savedSettingsChanged': false,
            'startupRefreshSkipped': true,
          },
        );
      }
      MediaKit.ensureInitialized();
      runApp(
        ProviderScope(
          overrides: [
            startupCrashRecoveryActiveProvider.overrideWithValue(
              recoveredFromUncleanStartup,
            ),
          ],
          retry: disableRiverpodRetry,
          child: const StarflowApp(),
        ),
      );
    },
    (error, stackTrace) {
      unawaited(
        appLogCritical(
          'app.uncaught-zone',
          'Uncaught asynchronous error',
          error: error,
          stackTrace: stackTrace,
        ),
      );
    },
  );
  if (startup != null) {
    await startup;
  }
}

String get _buildMode {
  if (kDebugMode) {
    return 'debug';
  }
  if (kProfileMode) {
    return 'profile';
  }
  return 'release';
}

/// Stamps every log file with the build it came from, so a captured log can be
/// attributed to a specific version instead of guessing from timestamps.
Future<Map<String, Object?>> _resolveBuildInfoFields() async {
  try {
    final info =
        await PackageInfo.fromPlatform().timeout(const Duration(seconds: 2));
    return <String, Object?>{
      'version': info.version,
      'buildNumber': info.buildNumber,
      'packageName': info.packageName,
      'buildMode': _buildMode,
    };
  } catch (_) {
    return <String, Object?>{'buildMode': _buildMode};
  }
}

void _installGlobalErrorLogging() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      appLogCritical(
        'app.flutter-error',
        details.context?.toDescription() ?? 'Flutter framework error',
        error: details.exception,
        stackTrace: details.stack,
      ),
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    unawaited(
      appLogCritical(
        'app.platform-error',
        'Uncaught platform dispatcher error',
        error: error,
        stackTrace: stackTrace,
      ),
    );
    return true;
  };
}
