import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:starflow/app/app.dart';
import 'package:starflow/core/state/riverpod_retry.dart';
import 'package:starflow/features/bootstrap/application/startup_crash_recovery.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await startupCrashRecovery.beginStartup().catchError((_) => false);
  MediaKit.ensureInitialized();
  runApp(
    const ProviderScope(
      retry: disableRiverpodRetry,
      child: StarflowApp(),
    ),
  );
}
