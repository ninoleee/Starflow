import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/presentation/widgets/player_menu_style.dart';

void main() {
  testWidgets(
      'playback menus share 80 percent surfaces without changing app theme',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
          dialogTheme: const DialogThemeData(backgroundColor: Colors.red)),
      home: Builder(
          builder: (context) => TextButton(
                onPressed: () => showPlaybackMenuDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(title: Text('Menu')),
                ),
                child: const Text('Open'),
              )),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final menuContext = tester.element(find.byType(AlertDialog));
    expect(Theme.of(menuContext).dialogTheme.backgroundColor,
        const Color(0xCC18181B));
    final material = tester.widget<Material>(find
        .descendant(of: find.byType(Dialog), matching: find.byType(Material))
        .first);
    expect(material.color, playbackMenuBackground);
    expect(material.elevation, 0);
    expect(
        Theme.of(tester.element(find.text('Open', skipOffstage: false)))
            .dialogTheme
            .backgroundColor,
        Colors.red);
    Navigator.of(menuContext).pop();
    await tester.pumpAndSettle();
  });
}
