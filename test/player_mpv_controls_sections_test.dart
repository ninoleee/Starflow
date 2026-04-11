import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Contract keys for the upcoming player_mpv_controls_sections.dart widget.
const Key _kLeanActionsSectionKey = Key('player-mpv-controls:actions:lean');
const Key _kFullActionsSectionKey = Key('player-mpv-controls:actions:full');

void main() {
  group('Player MPV controls sections contract', () {
    testWidgets('renders lean actions section in lightweight mode',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _buildUnderTest(leanMode: true),
          ),
        ),
      );

      expect(find.byKey(_kLeanActionsSectionKey), findsOneWidget);
      expect(find.byKey(_kFullActionsSectionKey), findsNothing);
    });

    testWidgets('renders full actions section in full mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _buildUnderTest(leanMode: false),
          ),
        ),
      );

      expect(find.byKey(_kLeanActionsSectionKey), findsNothing);
      expect(find.byKey(_kFullActionsSectionKey), findsOneWidget);
    });
  });
}

Widget _buildUnderTest({required bool leanMode}) {
  // TODO(soon): replace this fixture with:
  // `PlayerMpvControlsSections(leanMode: leanMode, ...)` from
  // `player_mpv_controls_sections.dart` once the widget lands.
  return _TestPlayerMpvControlsSections(leanMode: leanMode);
}

class _TestPlayerMpvControlsSections extends StatelessWidget {
  const _TestPlayerMpvControlsSections({required this.leanMode});

  final bool leanMode;

  @override
  Widget build(BuildContext context) {
    if (leanMode) {
      return const SizedBox(
        key: _kLeanActionsSectionKey,
        width: 1,
        height: 1,
      );
    }
    return const SizedBox(
      key: _kFullActionsSectionKey,
      width: 1,
      height: 1,
    );
  }
}
