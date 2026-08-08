import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/presentation/widgets/detail_television_picker_dialog.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  testWidgets('detail TV picker actively focuses the first option',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(
            const AppSettings(
              mediaSources: <MediaSourceConfig>[],
              searchProviders: <SearchProviderConfig>[],
              doubanAccount: DoubanAccountConfig(enabled: false),
              homeModules: <HomeModuleConfig>[],
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    unawaited(
                      showDetailTelevisionPickerDialog<int>(
                        context: context,
                        title: '选择播放来源',
                        selectedValue: 1,
                        options: const [
                          DetailTelevisionPickerOption<int>(
                            value: 0,
                            title: '第一项',
                            focusId: 'test:option:0',
                          ),
                          DetailTelevisionPickerOption<int>(
                            value: 1,
                            title: '第二项',
                            focusId: 'test:option:1',
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('打开'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byType(SimpleDialog), findsOneWidget);
    expect(find.byType(StarflowSelectionTile), findsNothing);
    expect(find.text('第二项  当前'), findsOneWidget);

    final firstFinder = find.byWidgetPredicate(
      (widget) =>
          widget is TvFocusableAction && widget.focusId == 'test:option:0',
    );
    final secondFinder = find.byWidgetPredicate(
      (widget) =>
          widget is TvFocusableAction && widget.focusId == 'test:option:1',
    );
    final first = tester.widget<TvFocusableAction>(firstFinder);
    final second = tester.widget<TvFocusableAction>(secondFinder);
    final firstDetector = tester.widget<FocusableActionDetector>(
      find.descendant(
        of: firstFinder,
        matching: find.byType(FocusableActionDetector),
      ),
    );
    final secondDetector = tester.widget<FocusableActionDetector>(
      find.descendant(
        of: secondFinder,
        matching: find.byType(FocusableActionDetector),
      ),
    );

    expect(firstDetector.focusNode?.hasFocus, isTrue);
    expect(secondDetector.focusNode?.hasFocus, isFalse);
    expect(first.visualStyle, TvFocusVisualStyle.subtle);
    expect(second.visualStyle, TvFocusVisualStyle.subtle);
  });
}
