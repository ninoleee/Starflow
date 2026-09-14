import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/app/theme/app_theme.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/library/application/library_cached_items.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/presentation/library_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

void main() {
  for (final television in [false, true]) {
    testWidgets(
        'library keeps only incremental and rebuild actions: $television',
        (tester) async {
      await tester.binding.setSurfaceSize(
        television ? const Size(1280, 720) : const Size(390, 844),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWithValue(AsyncData(television)),
          appSettingsProvider.overrideWithValue(
            SeedData.defaultSettings.copyWith(
              mediaSources: const [
                MediaSourceConfig(
                  id: 'nas',
                  name: 'NAS',
                  kind: MediaSourceKind.nas,
                  endpoint: 'https://nas.example/dav/',
                  enabled: true,
                ),
              ],
              homeModules: const [],
            ),
          ),
          libraryVisiblePageItemsProvider.overrideWith(
            (ref, request) async => const LibraryVisiblePageItemsResult(
              totalItems: 0,
              items: [],
            ),
          ),
          libraryCollectionsProvider.overrideWith((ref, filter) async => []),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const LibraryPage(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('增量更新'), findsOneWidget);
      expect(find.text('重建索引'), findsOneWidget);
      expect(find.text('完整查新'), findsNothing);
      expect(find.text('快速更新'), findsNothing);
      expect(find.textContaining('完整核对'), findsNothing);
      FocusNode node(Finder button) => tester
          .widget<FocusableActionDetector>(
            find.descendant(
                of: button, matching: find.byType(FocusableActionDetector)),
          )
          .focusNode!;
      if (television) {
        node(find.widgetWithText(TvAdaptiveButton, '重建索引')).requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
      } else {
        await tester.tap(find.text('重建索引'));
      }
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(StarflowButton, '开始重扫');
      final cancel = find.widgetWithText(StarflowButton, '取消');
      expect(tester.widget<StarflowButton>(confirm).variant,
          StarflowButtonVariant.primary);
      if (television) {
        final backgrounds = tester
            .widgetList<DecoratedBox>(find.descendant(
              of: confirm,
              matching: find.byType(DecoratedBox),
            ))
            .map((box) => box.decoration)
            .whereType<BoxDecoration>()
            .map((decoration) => decoration.color)
            .whereType<Color>();
        expect(backgrounds, contains(Colors.white.withValues(alpha: 0.06)));
        expect(backgrounds, isNot(contains(Colors.white)));
        expect(node(cancel).hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(node(confirm).hasFocus, isTrue);
        expect(node(cancel).hasFocus, isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(node(cancel).hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
      } else {
        await tester.tap(cancel);
      }
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
