import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/active_playback_cleanup.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/player_page.dart';

void main() {
  testWidgets('exit while waiting for old playback cleanup cancels startup',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cleanupStarted = Completer<void>();
    final releaseCleanup = Completer<void>();
    final token = ActivePlaybackCleanupCoordinator.register((_) async {
      if (!cleanupStarted.isCompleted) {
        cleanupStarted.complete();
      }
      await releaseCleanup.future;
    });
    addTearDown(() {
      ActivePlaybackCleanupCoordinator.unregister(token);
      if (!releaseCleanup.isCompleted) {
        releaseCleanup.complete();
      }
    });

    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: PlayerPage(
          target: PlaybackTarget(
            title: 'Cancelled startup',
            sourceId: 'test',
            streamUrl: '',
            sourceName: 'Test',
            sourceKind: MediaSourceKind.nas,
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(cleanupStarted.isCompleted, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    releaseCleanup.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
