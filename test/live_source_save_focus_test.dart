import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/app/theme/app_colors.dart';
import 'package:starflow/app/theme/app_theme.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/live_tv/data/live_repository.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';
import 'package:starflow/features/live_tv/presentation/live_sources_page.dart';
import 'package:starflow/features/live_tv/presentation/live_widgets.dart';

void main() {
  for (final accent in AppAccent.values) {
    for (final television in [false, true]) {
      for (final editing in [false, true]) {
        testWidgets(
            'subscription save colors and focus: $accent TV=$television edit=$editing',
            (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1280, 720);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(ProviderScope(
            overrides: [
              isTelevisionProvider.overrideWith((_) => television),
              liveSnapshotProvider.overrideWith((_) => Stream.value(
                    const LiveSnapshot(
                      sources: [LiveSource(id: 'source', name: 'Source')],
                    ),
                  )),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(accent: accent)
                  .copyWith(splashFactory: NoSplash.splashFactory),
              home: const LiveSourcesPage(),
            ),
          ));
          await tester.pumpAndSettle();
          await tester.tap(find.byWidgetPredicate((widget) =>
              widget is LiveIconButton &&
              widget.label == (editing ? '编辑订阅' : '添加订阅')));
          await tester.pumpAndSettle();

          final save = find.byWidgetPredicate(
              (widget) => widget is StarflowButton && widget.label == '保存');
          await tester.ensureVisible(save);
          await tester.pumpAndSettle();
          final size = tester.getSize(save);
          final fill =
              find.descendant(of: save, matching: find.byType(DecoratedBox));
          BoxDecoration decoration() =>
              tester.widget<DecoratedBox>(fill).decoration as BoxDecoration;
          final expectedFill = television
              ? Colors.white.withValues(alpha: 0.06)
              : accent.primary;
          expect(decoration().color, expectedFill);
          expect(
              tester
                  .widget<Text>(
                      find.descendant(of: save, matching: find.text('保存')))
                  .style!
                  .color,
              television ? AppColors.foregroundBody : accent.onPrimary);

          if (television) {
            final action = tester.widget<TvFocusableAction>(find.descendant(
                of: save, matching: find.byType(TvFocusableAction)));
            action.focusNode!.requestFocus();
            await tester.pumpAndSettle();
            expect(action.focusNode!.hasPrimaryFocus, isTrue);
            expect(action.focusableWhenDisabled, isTrue);
            expect(decoration().color, expectedFill);
            expect(tester.getSize(save), size);
            final outline = find.descendant(
                of: save,
                matching: find.byWidgetPredicate((widget) =>
                    widget is CustomPaint && widget.foregroundPainter != null));
            void paintOutline(Canvas canvas) => tester
                .widget<CustomPaint>(outline)
                .foregroundPainter!
                .paint(canvas, size);
            expect(
                paintOutline,
                paints
                  ..rrect(
                      color: Colors.white,
                      style: PaintingStyle.stroke,
                      strokeWidth: 2));
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
            await tester.pumpAndSettle();
            expect(action.focusNode!.hasPrimaryFocus, isFalse);
            expect(paintOutline, paintsNothing);
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await tester.pumpAndSettle();
            expect(action.focusNode!.hasPrimaryFocus, isTrue);
            expect(tester.getSize(save), size);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
