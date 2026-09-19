import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/data/search_repository.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/search/presentation/search_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('detail search page requests TV focus on query input',
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
          home: SearchPage(
            initialQuery: '测试电影',
            showBackButton: true,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'search-query');
    expect(find.byType(OverlayToolbar), findsOneWidget);
  });

  testWidgets('standalone favorites page focuses its sync action on TV',
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
          home: SearchPage(favoritesOnly: true),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'favorites-sync',
    );
  });

  testWidgets('detail search route push requests TV focus on query input',
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
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const SearchPage(
                            initialQuery: '测试电影',
                            showBackButton: true,
                          ),
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'search-query');
  });

  testWidgets('TV query dialog moves down out of its text field',
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
          home: SearchPage(
            initialQuery: '测试电影',
            showBackButton: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'search-query-dialog-field',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      isNot('search-query-dialog-field'),
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      anyOf('search-query-dialog-cancel', 'search-query-dialog-submit'),
    );
  });

  testWidgets('detail search restores TV focus after online result update',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final repository = _PendingSearchRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          searchRepositoryProvider.overrideWithValue(repository),
          appSettingsProvider.overrideWithValue(
            const AppSettings(
              mediaSources: <MediaSourceConfig>[],
              searchProviders: <SearchProviderConfig>[
                SearchProviderConfig(
                  id: 'online',
                  name: 'Online',
                  kind: SearchProviderKind.panSou,
                  endpoint: 'https://example.com',
                  enabled: true,
                ),
              ],
              doubanAccount: DoubanAccountConfig(enabled: false),
              homeModules: <HomeModuleConfig>[],
            ),
          ),
        ],
        child: const MaterialApp(
          home: SearchPage(
            initialQuery: '测试电影',
            showBackButton: true,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'search-query');

    for (var i = 0; i < 10 && !repository.onlineStarted.isCompleted; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(repository.onlineStarted.isCompleted, isTrue);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    repository.onlineResult.complete(
      SearchFetchResult(
        filteredCount: 0,
        items: const [
          SearchResult(
            id: 'online-1',
            title: '测试电影 4K',
            posterUrl: '',
            providerId: 'online',
            providerName: 'Online',
            quality: '4K',
            sizeLabel: '10GB',
            seeders: 0,
            summary: 'online result',
            resourceUrl: 'https://example.com/share/1',
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('测试电影 4K'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'search-query');
  });

  testWidgets('search result update does not steal an actionable page focus',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final repository = _PendingSearchRepository();
    final externalFocusNode = FocusNode(debugLabel: 'test-menu-entry');
    addTearDown(externalFocusNode.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          searchRepositoryProvider.overrideWithValue(repository),
          appSettingsProvider.overrideWithValue(
            const AppSettings(
              mediaSources: <MediaSourceConfig>[],
              searchProviders: <SearchProviderConfig>[
                SearchProviderConfig(
                  id: 'online',
                  name: 'Online',
                  kind: SearchProviderKind.panSou,
                  endpoint: 'https://example.com',
                  enabled: true,
                ),
              ],
              doubanAccount: DoubanAccountConfig(enabled: false),
              homeModules: <HomeModuleConfig>[],
            ),
          ),
        ],
        child: MaterialApp(
          home: Column(
            children: [
              TvFocusableAction(
                focusNode: externalFocusNode,
                focusId: 'test-menu-entry',
                onPressed: () {},
                child: const SizedBox(width: 120, height: 44),
              ),
              const Expanded(
                child: SearchPage(initialQuery: '测试电影'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    for (var i = 0; i < 10 && !repository.onlineStarted.isCompleted; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(repository.onlineStarted.isCompleted, isTrue);

    externalFocusNode.requestFocus();
    await tester.pump();
    expect(externalFocusNode.hasPrimaryFocus, isTrue);

    repository.onlineResult.complete(
      SearchFetchResult(
        filteredCount: 0,
        items: const [
          SearchResult(
            id: 'online-1',
            title: '测试电影 4K',
            posterUrl: '',
            providerId: 'online',
            providerName: 'Online',
            quality: '4K',
            sizeLabel: '10GB',
            seeders: 0,
            summary: 'online result',
            resourceUrl: 'https://example.com/share/1',
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(externalFocusNode.hasPrimaryFocus, isTrue);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'test-menu-entry');
  });

  for (final television in [false, true]) {
    for (final validating115 in [false, true]) {
      for (final validation in ['valid', 'cancelled', 'rate-limited']) {
        testWidgets(
            'cloud options follow validation: $validation 115=$validating115 TV=$television',
            (tester) async {
          SharedPreferences.setMockInitialValues(const {});
          tester.view.physicalSize = const Size(1280, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repository = _PendingSearchRepository();
          final validationStarted = Completer<void>();
          final validationResponse = Completer<http.Response>();
          final pendingType = validating115 ? '115 网盘' : '夸克网盘';
          final readyType = validating115 ? '夸克网盘' : '115 网盘';
          final readyCode = validating115 ? 'quark' : '115';
          final quarkClient = QuarkSaveClient(
            MockClient((request) {
              if (request.url.path == '/1/clouddrive/share/sharepage/token') {
                return Future.value(
                  http.Response.bytes(
                    utf8.encode(
                      jsonEncode({
                        'code': 0,
                        'data': {'stoken': 'st-valid'},
                      }),
                    ),
                    200,
                    headers: const {
                      'content-type': 'application/json; charset=utf-8',
                    },
                  ),
                );
              }
              if (validating115) {
                return Future.value(http.Response(
                    jsonEncode({
                      'code': 0,
                      'data': {
                        'list': [
                          {'fid': '1'}
                        ]
                      }
                    }),
                    200));
              }
              if (!validationStarted.isCompleted) {
                validationStarted.complete();
              }
              return validationResponse.future;
            }),
          );
          final cloud115Client = Cloud115SaveClient(MockClient((request) {
            expect(request.method, 'GET');
            expect(request.url.path, '/share/snap');
            expect(request.url.queryParameters['receive_code'], 'abcd');
            if (!validating115) {
              return Future.value(http.Response(
                  jsonEncode({
                    'state': true,
                    'data': {
                      'count': 1,
                      'list': [
                        {'fid': '1'}
                      ]
                    },
                  }),
                  200));
            }
            if (!validationStarted.isCompleted) validationStarted.complete();
            return validationResponse.future;
          }));

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                isTelevisionProvider.overrideWith((ref) => television),
                searchRepositoryProvider.overrideWithValue(repository),
                quarkSaveClientProvider.overrideWithValue(quarkClient),
                cloud115SaveClientProvider.overrideWithValue(cloud115Client),
                appSettingsProvider.overrideWithValue(
                  const AppSettings(
                    mediaSources: <MediaSourceConfig>[],
                    searchProviders: <SearchProviderConfig>[
                      SearchProviderConfig(
                        id: 'online',
                        name: 'Online',
                        kind: SearchProviderKind.panSou,
                        endpoint: 'https://example.com',
                        enabled: true,
                        allowedCloudTypes: ['quark', '115'],
                      ),
                    ],
                    doubanAccount: DoubanAccountConfig(enabled: false),
                    homeModules: <HomeModuleConfig>[],
                    networkStorage: NetworkStorageConfig(
                      quarkCookie: 'kps=test;',
                      cloud115Cookie: 'UID=test;',
                    ),
                  ),
                ),
              ],
              child: const MaterialApp(
                home: SearchPage(initialQuery: '测试电影'),
              ),
            ),
          );

          for (var i = 0;
              i < 10 && !repository.onlineStarted.isCompleted;
              i++) {
            await tester.pump(const Duration(milliseconds: 20));
          }
          repository.onlineResult.complete(
            SearchFetchResult(
              filteredCount: 0,
              items: [
                SearchResult(
                  id: '115-1',
                  title: validating115 ? '待验证电影' : '立即显示的电影',
                  posterUrl: '',
                  providerId: 'online',
                  providerName: 'Online',
                  quality: '4K',
                  sizeLabel: '10GB',
                  seeders: 0,
                  summary: 'online result',
                  resourceUrl: 'https://115cdn.com/s/abc123',
                  password: 'abcd',
                ),
                SearchResult(
                  id: 'quark-1',
                  title: validating115 ? '立即显示的电影' : '待验证电影',
                  posterUrl: '',
                  providerId: 'online',
                  providerName: 'Online',
                  quality: '4K',
                  sizeLabel: '10GB',
                  seeders: 0,
                  summary: 'online result',
                  resourceUrl: 'https://pan.quark.cn/s/abc123',
                ),
              ],
            ),
          );

          for (var i = 0; i < 10 && !validationStarted.isCompleted; i++) {
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(validationStarted.isCompleted, isTrue);
          await tester.pump(const Duration(milliseconds: 150));
          expect(find.text('立即显示的电影'), findsOneWidget);
          if (!television && !validating115) {
            expect(find.byTooltip('保存到 115'), findsOneWidget);
          }
          expect(find.text('待验证电影'), findsNothing);
          expect(find.textContaining('正在验证链接'), findsOneWidget);
          expect(find.text(readyType), findsOneWidget);
          expect(find.text(pendingType), findsNothing);
          expect(find.text('全部类型'), findsNothing);

          Future<void> selectType(String label) async {
            if (television) {
              final action = tester.widget<TvFocusableAction>(find.ancestor(
                of: find.text(label),
                matching: find.byType(TvFocusableAction),
              ));
              action.focusNode!.requestFocus();
              await tester.pump();
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            } else {
              await tester.tap(find.text(label));
            }
          }

          await selectType(readyType);
          await tester.pump(const Duration(milliseconds: 150));
          final selectedFocus = FocusManager.instance.primaryFocus;

          validationResponse.complete(
            http.Response.bytes(
              utf8.encode(
                jsonEncode(validation == 'valid'
                    ? {
                        'state': true,
                        'code': 0,
                        'data': {
                          'count': 1,
                          'list': [
                            {
                              'fid': 'file-1',
                              'dir': false,
                              'file_name': 'movie.mkv'
                            },
                          ],
                        },
                      }
                    : {
                        'state': false,
                        'code': validation == 'cancelled' ? 41001 : 429,
                        'message': validation == 'cancelled'
                            ? '好友已取消了分享'
                            : '请求过于频繁，请稍后再试',
                      }),
              ),
              200,
              headers: const {
                'content-type': 'application/json; charset=utf-8'
              },
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('待验证电影'), findsNothing);
          expect(find.text('立即显示的电影'), findsOneWidget);
          expect(find.textContaining('结果 1 条'), findsOneWidget);
          expect(find.text('全部类型'), findsNothing);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          if (television) {
            expect(FocusManager.instance.primaryFocus, same(selectedFocus));
            expect(selectedFocus?.debugLabel,
                contains('search:cloud-type:$readyCode'));
          }
          if (validation == 'cancelled') {
            expect(find.text(pendingType), findsNothing);
            expect(find.textContaining('过滤 1 条'), findsOneWidget);
          } else {
            expect(find.text(pendingType), findsOneWidget);
            await selectType(pendingType);
            await tester.pumpAndSettle();
            expect(find.text('待验证电影'), findsOneWidget);
            expect(find.text('立即显示的电影'), findsNothing);
            expect(find.text('链接暂未验证'),
                validation == 'rate-limited' ? findsOneWidget : findsNothing);
          }
        });
      }
    }
  }

  for (final isTelevision in [false, true]) {
    testWidgets('search page hides favorites entry (TV: $isTelevision)',
        (tester) async {
      SharedPreferences.setMockInitialValues(const {});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isTelevisionProvider.overrideWith((ref) => isTelevision),
            appSettingsProvider.overrideWithValue(
              const AppSettings(
                mediaSources: <MediaSourceConfig>[],
                searchProviders: <SearchProviderConfig>[],
                doubanAccount: DoubanAccountConfig(enabled: false),
                homeModules: <HomeModuleConfig>[],
              ),
            ),
          ],
          child: const MaterialApp(home: SearchPage()),
        ),
      );

      await tester.pump();

      expect(find.byTooltip('查看收藏'), findsNothing);
      expect(find.byType(OverlayToolbar), findsNothing);
      expect(find.text('收藏'), findsNothing);
      expect(find.byIcon(Icons.favorite_rounded), findsNothing);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    });
  }

  testWidgets('standalone favorites page hides search controls and tabs',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => false),
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
          home: SearchPage(favoritesOnly: true),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('收藏'), findsOneWidget);
    expect(find.byType(OverlayToolbar), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('搜索'), findsNothing);
    expect(find.text('全部'), findsNothing);
  });
}

class _PendingSearchRepository implements SearchRepository {
  final Completer<void> onlineStarted = Completer<void>();
  final Completer<SearchFetchResult> onlineResult =
      Completer<SearchFetchResult>();

  @override
  Future<SearchFetchResult> searchLocal(
    String query, {
    String? sourceId,
    String? sectionId,
    int limit = 60,
  }) async {
    return SearchFetchResult(items: const [], filteredCount: 0);
  }

  @override
  Future<SearchFetchResult> searchOnline(
    String query, {
    required SearchProviderConfig provider,
  }) {
    if (!onlineStarted.isCompleted) {
      onlineStarted.complete();
    }
    return onlineResult.future;
  }
}
