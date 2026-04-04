// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:starflow/app/app.dart';

void main() {
  testWidgets('renders Starflow shell', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: StarflowApp()));

    expect(find.text('正在唤醒你的片库'), findsOneWidget);
    expect(find.text('把想看的、能播的、还缺资源的，放在同一个首页。'), findsNothing);

    expect(find.text('Starflow'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });
}
