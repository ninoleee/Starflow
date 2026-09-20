import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/playback/application/playback_control_intents.dart';

class _MenuIntent extends Intent {
  const _MenuIntent();
}

void main() {
  for (final tool in ['Subtitle', 'Audio', 'Next episode', 'Options']) {
    testWidgets('media commands and menu bypass focused $tool activation',
        (tester) async {
      var playing = true;
      var activated = 0;
      var menus = 0;
      var commands = 0;
      await tester.pumpWidget(_host(Shortcuts(
        shortcuts: tvPressOnlyShortcuts(const {
          ...playbackMediaShortcuts,
          SingleActivator(LogicalKeyboardKey.contextMenu): _MenuIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonY): _MenuIntent(),
        }),
        child: Actions(
            actions: {
              PlaybackPlayIntent:
                  CallbackAction<PlaybackPlayIntent>(onInvoke: (_) {
                playing = true;
                commands++;
                return null;
              }),
              PlaybackPauseIntent:
                  CallbackAction<PlaybackPauseIntent>(onInvoke: (_) {
                playing = false;
                commands++;
                return null;
              }),
              PlaybackToggleIntent:
                  CallbackAction<PlaybackToggleIntent>(onInvoke: (_) {
                playing = !playing;
                commands++;
                return null;
              }),
              _MenuIntent: CallbackAction<_MenuIntent>(onInvoke: (_) {
                menus++;
                return null;
              }),
            },
            child: TvFocusableAction(
              autofocus: true,
              onPressed: () => activated++,
              child: Text(tool),
            )),
      )));
      await tester.pumpAndSettle();
      for (final key in [
        LogicalKeyboardKey.mediaPause,
        LogicalKeyboardKey.mediaPause,
        LogicalKeyboardKey.mediaPlay,
        LogicalKeyboardKey.mediaPlay,
        LogicalKeyboardKey.mediaPlayPause
      ]) {
        await tester.sendKeyDownEvent(key);
        await tester.sendKeyRepeatEvent(key);
        await tester.sendKeyUpEvent(key);
        expect(playing, key == LogicalKeyboardKey.mediaPlay);
      }
      expect(commands, 5);
      expect(activated, 0);
      for (final key in [
        LogicalKeyboardKey.contextMenu,
        LogicalKeyboardKey.gameButtonY
      ]) {
        await tester.sendKeyDownEvent(key);
        await tester.sendKeyRepeatEvent(key);
        await tester.sendKeyUpEvent(key);
      }
      expect(menus, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(activated, 1);
    });
  }

  for (final enabled in [true, false]) {
    testWidgets('TV primary/secondary/long pointer, disabled=$enabled',
        (tester) async {
      var activated = 0;
      var contexts = 0;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(_host(TvFocusableAction(
        focusNode: focus,
        focusableWhenDisabled: true,
        onPressed: enabled ? () => activated++ : null,
        onContextAction: enabled ? () => contexts++ : null,
        child: const SizedBox(width: 150, height: 70, child: Text('Tool')),
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tool'));
      await tester.pumpAndSettle();
      expect(activated, enabled ? 1 : 0);
      if (enabled) expect(focus.hasPrimaryFocus, isTrue);
      await tester.tap(find.text('Tool'), buttons: kSecondaryMouseButton);
      await tester.longPress(find.text('Tool'));
      expect(contexts, enabled ? 2 : 0);
      expect(activated, enabled ? 1 : 0);
    });
  }

  testWidgets('local menu and page scope each handle once; nested tap wins',
      (tester) async {
    var outer = 0;
    var inner = 0;
    var scope = 0;
    var local = 0;
    await tester.pumpWidget(_host(TvMenuButtonScope(
      onMenuButtonPressed: () => scope++,
      child: Column(children: [
        TvFocusableAction(
            autofocus: true,
            onPressed: () => outer++,
            onContextAction: () => local++,
            child: GestureDetector(
                onTap: () => inner++,
                child: const SizedBox(
                    width: 120, height: 60, child: Text('Nested')))),
        TvFocusableAction(onPressed: () {}, child: const Text('Fallback')),
      ]),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nested'));
    expect(inner, 1);
    expect(outer, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    expect(local, 1);
    expect(scope, 0);
    await tester.tap(find.text('Fallback'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    expect(scope, 1);
  });
}

Widget _host(Widget child) => ProviderScope(
      overrides: [isTelevisionProvider.overrideWith((ref) => true)],
      child: MaterialApp(home: Scaffold(body: child)),
    );
