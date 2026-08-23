import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:starflow/app/app.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/state/riverpod_retry.dart';
import 'package:starflow/features/bootstrap/application/startup_crash_recovery.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

Future<void> main() async {
  final startup = runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      Object? settingsLoadError;
      StackTrace? settingsLoadStackTrace;
      try {
        final initialSettings = await LocalAppSettingsRepository().load();
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
      appLogInfo('app.lifecycle', 'Application startup');
      if (settingsLoadError != null) {
        appLogWarning(
          'app.startup',
          'Could not load logging preferences; defaults are active',
          error: settingsLoadError,
          stackTrace: settingsLoadStackTrace,
        );
      }

      await startupCrashRecovery.beginStartup().catchError((Object error) {
        appLogWarning(
          'app.startup',
          'Startup crash recovery could not begin',
          error: error,
        );
        return false;
      });
      MediaKit.ensureInitialized();
      runApp(
        const ProviderScope(
          retry: disableRiverpodRetry,
          child: StarflowApp(),
        ),
      );
    },
    (error, stackTrace) {
      appLogError(
        'app.uncaught-zone',
        'Uncaught asynchronous error',
        error: error,
        stackTrace: stackTrace,
      );
    },
  );
  if (startup != null) {
    await startup;
  }
}

void _installGlobalErrorLogging() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    appLogError(
      'app.flutter-error',
      details.context?.toDescription() ?? 'Flutter framework error',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    appLogError(
      'app.platform-error',
      'Uncaught platform dispatcher error',
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  };
}
