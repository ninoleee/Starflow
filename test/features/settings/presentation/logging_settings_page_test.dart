import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/logging/app_log_api.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/logging_settings_page.dart';

void main() {
  testWidgets('TV log preview entries accept focus and move down',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          appLogSummaryProvider.overrideWith(
            (ref) async => const AppLogSummary(
              supported: true,
              fileCount: 1,
              totalBytes: 128,
              directoryPath: '/tmp/logs',
            ),
          ),
          appLogEntriesProvider.overrideWith(
            (ref) async => List<AppLogEntry>.generate(
              12,
              (index) => AppLogEntry(
                timestamp: DateTime.utc(2026, 8, 23, 10, index),
                level: index.isEven ? AppLogLevel.info : AppLogLevel.error,
                category: 'test',
                message: 'entry-$index',
                error: 'diagnostic details for entry $index',
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: LoggingSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    final entries = tester
        .widgetList<TvFocusableAction>(find.byType(TvFocusableAction))
        .where(
          (widget) =>
              widget.focusId?.startsWith('settings:logging:entry:') ?? false,
        )
        .toList(growable: false);
    expect(entries, hasLength(12));

    final previewViewport = tester.widget<SizedBox>(
      find
          .descendant(
            of: find.byKey(
              const ValueKey<String>('logging-preview-viewport'),
            ),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(previewViewport.height, 560);
    final previewScroll = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey<String>('logging-preview-scroll')),
    );
    expect(previewScroll.primary, isFalse);
    expect(previewScroll.controller, isNotNull);
    final outerLists = tester
        .widgetList<ListView>(find.byType(ListView))
        .where((list) => list.primary == true)
        .toList(growable: false);
    expect(outerLists, hasLength(1));

    entries.first.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    expect(entries.first.focusNode!.hasFocus, isTrue);

    for (var index = 0; index < 8; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(entries[8].focusNode!.hasFocus, isTrue);
    expect(previewScroll.controller!.offset, greaterThan(0));
  });
}
