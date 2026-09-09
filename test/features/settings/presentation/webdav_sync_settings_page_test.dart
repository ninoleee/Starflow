import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/settings/data/webdav_sync_service.dart';
import 'package:starflow/features/settings/presentation/webdav_sync_settings_page.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';

class _Preferences extends WebDavSyncPreferences {
  @override
  Future<WebDavSyncConfig> load() async => const WebDavSyncConfig(
        url: 'https://example.com/dav/',
        password: 'hidden-password',
      );
}

void main() {
  for (final tv in [false, true]) {
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
      expect(find.byType(SettingsActionButton), findsNWidgets(4));
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
