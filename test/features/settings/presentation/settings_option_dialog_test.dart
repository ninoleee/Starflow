import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

void main() {
  testWidgets('TV settings option dialog focuses the first option',
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
                      showSettingsOptionDialog<String>(
                        context: context,
                        title: '选择选项',
                        options: const ['第一项', '第二项'],
                        currentValue: '第二项',
                        labelBuilder: (option) => option,
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

    final options = tester
        .widgetList<TvFocusableAction>(find.byType(TvFocusableAction))
        .where(
          (widget) =>
              widget.focusId?.startsWith('settings-option-dialog:') ?? false,
        )
        .toList(growable: false);

    expect(options, hasLength(2));
    expect(options.first.focusNode?.hasFocus, isTrue);
    expect(options.last.focusNode?.hasFocus, isFalse);
  });
}
