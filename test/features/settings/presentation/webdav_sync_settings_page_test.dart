import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/data/webdav_sync_service.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/webdav_sync_settings_page.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';

class _Preferences extends WebDavSyncPreferences {
  _Preferences({bool favorites = true})
      : config = WebDavSyncConfig(
          url: 'https://example.com/dav/',
          password: 'hidden-password',
          favorites: favorites,
        );

  WebDavSyncConfig config;
  final saves = <WebDavSyncConfig>[];
  bool fail = false;
  Completer<void>? hold;

  @override
  Future<WebDavSyncConfig> load() async => config;

  @override
  Future<void> save(WebDavSyncConfig value) async {
    await hold?.future;
    if (fail) throw StateError('private-storage-error');
    config = value;
    saves.add(value);
    notifyChanged();
  }
}

class _SettingsController extends SettingsController {
  @override
  Future<AppSettings> build() async => SeedData.defaultSettings;
}

void main() {
  for (final tv in [false, true]) {
    testWidgets(
        'network sync form auto saves text and toggles without network: TV=$tv',
        (tester) async {
      final preferences = _Preferences();
      var requests = 0;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => tv),
          webDavSyncPreferencesProvider.overrideWithValue(preferences),
          webDavSyncServiceProvider
              .overrideWithValue(WebDavSyncService(MockClient((request) async {
            requests++;
            return http.Response('', 500);
          }))),
          settingsControllerProvider.overrideWith(_SettingsController.new),
        ],
        child: const MaterialApp(home: WebDavSyncSettingsPage()),
      ));
      await tester.pumpAndSettle();
      expect(preferences.saves, isEmpty);
      expect(find.text('保存同步设置'), findsNothing);
      expect(find.text('无 ETag 兼容'), findsNothing);
      expect(find.byType(SettingsToggleTile), findsNWidgets(3));
      final fields = tester.widgetList<SettingsTextInputField>(
          find.byType(SettingsTextInputField));
      fields.singleWhere((f) => f.focusId == 'sync:url').controller.text =
          'https://new.example/dav/';
      fields.singleWhere((f) => f.focusId == 'sync:directory').controller.text =
          'backup/Starflow';
      fields.singleWhere((f) => f.focusId == 'sync:username').controller.text =
          'new-user';
      fields.singleWhere((f) => f.focusId == 'sync:password').controller.text =
          'new-password';
      tester
          .widgetList<SettingsToggleTile>(find.byType(SettingsToggleTile))
          .singleWhere((t) => t.focusId == 'sync:settings')
          .onChanged!(false);
      tester
          .widgetList<SettingsToggleTile>(find.byType(SettingsToggleTile))
          .singleWhere((t) => t.focusId == 'sync:favorites')
          .onChanged!(false);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(preferences.saves.length, 1);
      expect(preferences.config.url, 'https://new.example/dav/');
      expect(preferences.config.directory, 'backup/Starflow');
      expect(preferences.config.username, 'new-user');
      expect(preferences.config.password, 'new-password');
      expect(preferences.config.settings, isFalse);
      expect(preferences.config.favorites, isFalse);
      expect(requests, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(preferences.saves.length, 1);
    });
  }

  testWidgets('back immediately flushes latest network sync draft',
      (tester) async {
    final preferences = _Preferences();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWith((ref) => false),
        webDavSyncPreferencesProvider.overrideWithValue(preferences),
        settingsControllerProvider.overrideWith(_SettingsController.new),
      ],
      child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                      body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const WebDavSyncSettingsPage())),
                    child: const Text('Open'),
                  )))),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    tester
        .widgetList<SettingsTextInputField>(find.byType(SettingsTextInputField))
        .singleWhere((f) => f.focusId == 'sync:directory')
        .controller
        .text = 'latest';
    unawaited(tester.binding.handlePopRoute());
    await tester.pumpAndSettle();
    expect(preferences.saves.length, 1);
    expect(preferences.config.directory, 'latest');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<SettingsTextInputField>(
                find.byType(SettingsTextInputField))
            .singleWhere((f) => f.focusId == 'sync:directory')
            .controller
            .text,
        'latest');
  });

  testWidgets(
      'test connection drains pending local save and never uses stale draft',
      (tester) async {
    final preferences = _Preferences()..hold = Completer<void>();
    final requests = <Uri>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWith((ref) => false),
        webDavSyncPreferencesProvider.overrideWithValue(preferences),
        webDavSyncServiceProvider
            .overrideWithValue(WebDavSyncService(MockClient((r) async {
          requests.add(r.url);
          return http.Response('', 207);
        }))),
        settingsControllerProvider.overrideWith(_SettingsController.new),
      ],
      child: const MaterialApp(home: WebDavSyncSettingsPage()),
    ));
    await tester.pumpAndSettle();
    tester
        .widgetList<SettingsTextInputField>(find.byType(SettingsTextInputField))
        .singleWhere((f) => f.focusId == 'sync:directory')
        .controller
        .text = 'latest';
    tester
        .widgetList<SettingsActionButton>(find.byType(SettingsActionButton))
        .singleWhere((b) => b.focusId == 'sync:test')
        .onPressed!();
    await tester.pump();
    expect(requests, isEmpty);
    preferences.hold!.complete();
    await tester.pumpAndSettle();
    expect(preferences.config.directory, 'latest');
    expect(requests.single.path, '/dav/latest/');
  });

  testWidgets('failed autosave stops network action and a later edit retries',
      (tester) async {
    final preferences = _Preferences()..fail = true;
    var requests = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWith((ref) => false),
        webDavSyncPreferencesProvider.overrideWithValue(preferences),
        webDavSyncServiceProvider
            .overrideWithValue(WebDavSyncService(MockClient((r) async {
          requests++;
          return http.Response('', 207);
        }))),
        settingsControllerProvider.overrideWith(_SettingsController.new),
      ],
      child: const MaterialApp(home: WebDavSyncSettingsPage()),
    ));
    await tester.pumpAndSettle();
    final field = tester
        .widgetList<SettingsTextInputField>(find.byType(SettingsTextInputField))
        .singleWhere((f) => f.focusId == 'sync:directory');
    field.controller.text = 'first';
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    tester
        .widgetList<SettingsActionButton>(find.byType(SettingsActionButton))
        .singleWhere((b) => b.focusId == 'sync:test')
        .onPressed!();
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(find.textContaining('private-storage-error'), findsNothing);
    preferences.fail = false;
    field.controller.text = 'second';
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(preferences.config.directory, 'second');
  });

  testWidgets(
      'connection test reports missing child directory without uploading',
      (tester) async {
    final requests = <String>[];
    final service = WebDavSyncService(MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      return http.Response('', request.url.path == '/dav/' ? 207 : 404);
    }));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWith((ref) => false),
        webDavSyncPreferencesProvider.overrideWithValue(_Preferences()),
        webDavSyncServiceProvider.overrideWithValue(service),
        settingsControllerProvider.overrideWith(_SettingsController.new),
      ],
      child: const MaterialApp(home: WebDavSyncSettingsPage()),
    ));
    await tester.pumpAndSettle();
    final button = tester
        .widgetList<SettingsActionButton>(find.byType(SettingsActionButton))
        .singleWhere((button) => button.focusId == 'sync:test');
    button.onPressed!();
    await tester.pumpAndSettle();
    expect(requests, ['PROPFIND /dav/Starflow/', 'PROPFIND /dav/']);
    final status =
        find.text(WebDavConnectionTestResult.directoryMissing.message);
    await tester.scrollUntilVisible(status, 300,
        scrollable: find.byWidgetPredicate((widget) =>
            widget is Scrollable &&
            widget.axisDirection == AxisDirection.down));
    await tester.pumpAndSettle();
    expect(status, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final tv in [false, true]) {
    testWidgets('upload reports directory failure on ${tv ? 'TV' : 'phone'}',
        (tester) async {
      await tester.binding
          .setSurfaceSize(tv ? const Size(1920, 1080) : const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final requests = <String>[];
      final service = WebDavSyncService(MockClient((request) async {
        requests.add(request.method);
        return http.Response(
            'private-server-error', request.method == 'MKCOL' ? 201 : 404);
      }));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => tv),
          webDavSyncPreferencesProvider
              .overrideWithValue(_Preferences(favorites: false)),
          webDavSyncServiceProvider.overrideWithValue(service),
          settingsControllerProvider.overrideWith(_SettingsController.new),
        ],
        child: const MaterialApp(home: WebDavSyncSettingsPage()),
      ));
      await tester.pumpAndSettle();
      final button = tester
          .widgetList<SettingsActionButton>(find.byType(SettingsActionButton))
          .singleWhere((button) => button.focusId == 'sync:upload');
      button.onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(requests, isEmpty);
      tester
          .widgetList<StarflowButton>(find.byType(StarflowButton))
          .singleWhere((button) => button.label == '确认')
          .onPressed!();
      await tester.pumpAndSettle();
      expect(requests, ['MKCOL', 'PROPFIND']);
      final status = find.textContaining('创建同步目录后仍无法访问');
      await tester.scrollUntilVisible(status, 300,
          scrollable: find.byWidgetPredicate((widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down));
      await tester.pumpAndSettle();
      expect(status, findsOneWidget);
      expect(find.textContaining('private-server-error'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sync form fits ${tv ? 'TV' : 'phone'} and hides password',
        (tester) async {
      await tester.binding.setSurfaceSize(
        tv ? const Size(1920, 1080) : const Size(390, 844),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => tv),
          webDavSyncPreferencesProvider.overrideWithValue(_Preferences()),
        ],
        child: const MaterialApp(home: WebDavSyncSettingsPage()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('网络同步'), findsOneWidget);
      expect(find.byType(SettingsTextInputField), findsNWidgets(4));
      expect(find.byType(SettingsActionButton), findsNWidgets(3));
      final autoToggle = tester
          .widgetList<SettingsToggleTile>(find.byType(SettingsToggleTile))
          .singleWhere((tile) => tile.title == '收藏自动同步');
      expect(autoToggle.value, isFalse);
      await tester.ensureVisible(find.text('收藏自动同步'));
      await tester.pumpAndSettle();
      autoToggle.onChanged!(true);
      await tester.pumpAndSettle();
      expect(find.text('开启收藏自动同步'), findsOneWidget);
      tester
          .widgetList<StarflowButton>(find.byType(StarflowButton))
          .singleWhere((button) => button.label == '取消')
          .onPressed!();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
          tester
              .widgetList<SettingsToggleTile>(find.byType(SettingsToggleTile))
              .singleWhere((tile) => tile.title == '收藏自动同步')
              .value,
          isFalse);
      autoToggle.onChanged!(true);
      await tester.pumpAndSettle();
      tester
          .widgetList<StarflowButton>(find.byType(StarflowButton))
          .singleWhere((button) => button.label == '开启')
          .onPressed!();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      final manualFavorites = tester
          .widgetList<SettingsToggleTile>(find.byType(SettingsToggleTile))
          .singleWhere((tile) => tile.title == '同步收藏');
      expect(manualFavorites.onChanged, isNull);
      expect(find.text('收藏等待同步'), findsOneWidget);
      if (tv) {
        expect(find.text('hidden-password'), findsNothing);
        expect(find.text('已填写'), findsOneWidget);
      } else {
        final password = tester
            .widgetList<TextField>(find.byType(TextField))
            .singleWhere((field) => field.obscureText);
        expect(password.controller!.text, 'hidden-password');
      }
      await tester.ensureVisible(find.text('从云端下载'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
