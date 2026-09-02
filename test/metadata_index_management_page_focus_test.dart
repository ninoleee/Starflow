import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/metadata_index_management_page.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('metadata management route focuses its first visible TV action',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});

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
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    autofocus: true,
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const MetadataIndexManagementPage(
                            target: MediaDetailTarget(
                              title: '测试影片',
                              posterUrl: '',
                              overview: '',
                              sourceKind: MediaSourceKind.emby,
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Text('打开信息管理'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    final focusHistory = <String?>[];
    void recordFocus() {
      focusHistory.add(FocusManager.instance.primaryFocus?.debugLabel);
    }

    FocusManager.instance.addListener(recordFocus);
    addTearDown(() => FocusManager.instance.removeListener(recordFocus));
    await tester.tap(find.text('打开信息管理'));
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'metadata-index-auto-refresh',
    );
    expect(focusHistory, isNot(contains('metadata-index-search')));
  });

  testWidgets('TV metadata title field keeps focus when backspace deletes text',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});

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
        child: const MaterialApp(
          home: MetadataIndexManagementPage(
            target: MediaDetailTarget(
              title: '测试影片',
              posterUrl: '',
              overview: '',
              sourceKind: MediaSourceKind.emby,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final titleField = find.widgetWithText(TextField, '片名 / 搜索词');
    await tester.tap(titleField);
    await tester.pump();
    await tester.enterText(titleField, '测试');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(
      tester.widget<TextField>(titleField).controller?.text,
      '测',
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'metadata-index-query',
    );
  });
}
