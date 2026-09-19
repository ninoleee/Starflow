import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/metadata_index_management_page.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/metadata_match_resolver.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final fail in [false, true]) {
    for (final moveAway in [false, true]) {
      testWidgets('TV refresh focus: failure=$fail moveAway=$moveAway',
          (tester) async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final resolver = _PendingMetadataResolver();
        await tester.pumpWidget(ProviderScope(
          overrides: [
            isTelevisionProvider.overrideWith((ref) => true),
            appSettingsProvider.overrideWithValue(const AppSettings(
              mediaSources: [], searchProviders: [], homeModules: [],
              doubanAccount: DoubanAccountConfig(enabled: false),
            )),
            metadataMatchResolverProvider.overrideWithValue(resolver),
            localStorageCacheRepositoryProvider.overrideWithValue(
              LocalStorageCacheRepository(sharedPreferences: preferences),
            ),
          ],
          child: const MaterialApp(home: MetadataIndexManagementPage(
            target: MediaDetailTarget(title: 'Test', posterUrl: '', overview: '',
                sourceKind: MediaSourceKind.emby),
          )),
        ));
        await tester.pumpAndSettle();
        final refresh = FocusManager.instance.primaryFocus!;
        expect(refresh.debugLabel, 'metadata-index-auto-refresh');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.text('更新中...'), findsOneWidget);
        expect(refresh.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        expect(resolver.calls, 1);

        if (moveAway) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          expect(hasActionableTvFocus(), isTrue);
          expect(refresh.hasPrimaryFocus, isFalse);
        }
        final beforeCompletion = FocusManager.instance.primaryFocus;
        if (fail) {
          resolver.result.completeError(StateError('test refresh failure'));
        } else {
          resolver.result.complete(null);
        }
        await tester.pumpAndSettle();
        expect(find.text('更新中...'), findsNothing);
        expect(find.text('自动更新'), findsOneWidget);
        expect(FocusManager.instance.primaryFocus, same(beforeCompletion));
        expect(resolver.calls, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

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

class _PendingMetadataResolver implements MetadataMatchResolver {
  final result = Completer<MetadataMatchResult?>();
  int calls = 0;

  @override
  Future<MetadataMatchResult?> match({
    required AppSettings settings,
    required MetadataMatchRequest request,
  }) {
    calls++;
    return result.future;
  }
}
