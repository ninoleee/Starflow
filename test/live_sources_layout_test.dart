import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/live_tv/data/live_repository.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';
import 'package:starflow/features/live_tv/presentation/live_sources_page.dart';
import 'package:starflow/features/live_tv/presentation/live_widgets.dart';

void main() {
  for (final television in [false, true]) {
    for (final bottomInset in [0.0, 34.0]) {
      testWidgets(
          'subscription list and editors reserve bottom space '
          '(TV: $television, inset: $bottomInset)', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 480);
        tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
        tester.view.padding = FakeViewPadding(bottom: bottomInset);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(ProviderScope(
          overrides: [
            isTelevisionProvider.overrideWith((_) => television),
            liveSnapshotProvider.overrideWith((_) => Stream.value(LiveSnapshot(
                  sources: List.generate(
                    8,
                    (i) => LiveSource(id: '$i', name: 'Source $i'),
                  ),
                ))),
          ],
          child: MaterialApp(
            theme: ThemeData(splashFactory: NoSplash.splashFactory),
            home: const LiveSourcesPage(),
          ),
        ));
        await tester.pumpAndSettle();

        Future<void> checkBottomSpace(Finder lastControl) async {
          final list = find.byType(ListView);
          final scrollable = find.descendant(
            of: list,
            matching: find.byType(Scrollable),
          );
          final position =
              tester.state<ScrollableState>(scrollable.first).position;
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle();
          final padding = tester.widget<ListView>(list).padding! as EdgeInsets;
          expect(padding.bottom, kBottomReservedSpacing + bottomInset);
          final viewport = tester.getRect(list);
          final control = tester.getRect(lastControl);
          expect(control.top, greaterThanOrEqualTo(viewport.top));
          expect(control.bottom,
              lessThanOrEqualTo(viewport.bottom - padding.bottom + 0.01));
          expect(lastControl.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }

        Finder icon(String label) => find.byWidgetPredicate(
            (widget) => widget is LiveIconButton && widget.label == label);
        await checkBottomSpace(icon('删除订阅').last);

        for (final action in ['编辑订阅', '添加订阅']) {
          await tester.tap(icon(action).last);
          await tester.pumpAndSettle();
          final save = find.byWidgetPredicate(
              (widget) => widget is StarflowButton && widget.label == '保存');
          await checkBottomSpace(save);
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
      });
    }
  }
}
