import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/app/shell_layout.dart';

void main() {
  testWidgets('registers an explicit page controller as primary',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AppPrimaryScrollController(
          controller: controller,
          child: Scaffold(
            body: Builder(
              builder: (context) {
                expect(PrimaryScrollController.maybeOf(context), controller);
                return ListView(
                  controller: controller,
                  children: const [SizedBox(height: 1200)],
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
