import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

void main() {
  test('repeat blockers preserve shortcut triggers and key descriptions', () {
    const activator = SingleActivator(
      LogicalKeyboardKey.enter,
      control: true,
      shift: true,
    );
    const intent = ActivateIntent();
    final shortcuts = tvPressOnlyShortcuts(const {activator: intent});
    final repeatBlocker = shortcuts.keys.first;

    expect(shortcuts, hasLength(2));
    expect(shortcuts[repeatBlocker], isA<DoNothingIntent>());
    expect(shortcuts.keys.last, same(activator));
    expect(shortcuts[activator], same(intent));
    expect(repeatBlocker.triggers, orderedEquals(activator.triggers));
    expect(
      repeatBlocker.debugDescribeKeys(),
      contains(activator.debugDescribeKeys()),
    );
    expect(repeatBlocker.debugDescribeKeys(), contains('(repeat)'));
  });
}
