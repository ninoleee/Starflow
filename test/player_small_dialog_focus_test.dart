import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_dialogs.dart';

void main() {
  for (final mode in ['delay', 'empty-delay', 'skip', 'options']) {
    testWidgets('TV $mode dialog starts focused and accepts remote input',
        (tester) async {
      var applied = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [isTelevisionProvider.overrideWith((ref) => true)],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(builder: (context) {
                return TextButton(
                  onPressed: () {
                    switch (mode) {
                      case 'delay':
                      case 'empty-delay':
                        showPlaybackSubtitleDelayDialog(
                          context: context,
                          initialDelay: 0,
                          steps: mode == 'delay' ? [-1, 0, 1] : [],
                          onApplyDelay: (value) async {
                            applied = true;
                            return value;
                          },
                        );
                      case 'skip':
                        showPlaybackSeriesSkipDialog(
                          context: context,
                          target: const PlaybackTarget(
                            title: 'Episode',
                            sourceId: 'test',
                            streamUrl: '',
                            sourceName: 'Test',
                            sourceKind: MediaSourceKind.nas,
                          ),
                          playerDuration: const Duration(minutes: 40),
                          currentPosition: const Duration(minutes: 1),
                          seedPreference: SeriesSkipPreference(
                            seriesKey: 'test',
                            updatedAt: DateTime(2026),
                          ),
                        );
                      case 'options':
                        showDialog<void>(
                          context: context,
                          builder: (context) => SimpleDialog(
                            children: [
                              TvDialogOption(
                                isTelevision: true,
                                autofocus: true,
                                onPressed: () {},
                                child: const Text('First'),
                              ),
                              TvDialogOption(
                                isTelevision: true,
                                onPressed: () {
                                  applied = true;
                                  Navigator.of(context).pop();
                                },
                                child: const Text('Second'),
                              ),
                            ],
                          ),
                        );
                    }
                  },
                  child: const Text('Open'),
                );
              }),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final initialFocus = FocusManager.instance.primaryFocus;
      expect(initialFocus, isNot(isA<FocusScopeNode>()));
      expect(initialFocus?.context, isNotNull);
      if (mode == 'options') {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus, isNot(same(initialFocus)));
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      switch (mode) {
        case 'delay':
          expect(applied, isTrue);
          expect(initialFocus?.hasPrimaryFocus, isTrue);
        case 'skip':
          expect(
              tester
                  .widget<StarflowToggleTile>(
                    find.byType(StarflowToggleTile),
                  )
                  .value,
              isTrue);
          expect(initialFocus?.hasPrimaryFocus, isTrue);
        case 'empty-delay':
          expect(find.byType(AlertDialog), findsNothing);
        case 'options':
          expect(applied, isTrue);
          expect(find.byType(SimpleDialog), findsNothing);
      }
      if (mode == 'delay' || mode == 'skip') {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }
}
