import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:starflow/app/app.dart';
import 'package:starflow/core/state/riverpod_retry.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(
    const ProviderScope(
      retry: disableRiverpodRetry,
      child: StarflowApp(),
    ),
  );
}
