import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/settings/presentation/quark_folder_picker_page.dart';

void main() {
  for (final fail in [false, true]) {
    testWidgets('TV directory focus survives loading and empty/error: $fail',
        (tester) async {
      final client = _DirectoryClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isTelevisionProvider.overrideWith((ref) => true),
            quarkSaveClientProvider.overrideWithValue(client),
          ],
          child: const MaterialApp(
            home: QuarkFolderPickerPage(cookie: 'test'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel,
          'quark-folder-select');
      client.pending.complete([
        const QuarkDirectoryEntry(fid: 'child', name: 'Child', path: '/Child'),
      ]);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel,
          'quark-folder-select');
      final childAction = tester
          .widgetList<TvFocusableAction>(find.byType(TvFocusableAction))
          .firstWhere((widget) => widget.focusId == 'quark-folder:child');
      childAction.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel,
          'quark-folder-select');
      if (fail) {
        client.pending.completeError(Exception('directory unavailable'));
      } else {
        client.pending.complete([]);
      }
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel,
          'quark-folder-select');
      expect(tester.takeException(), isNull);
    });
  }
}

class _DirectoryClient extends QuarkSaveClient {
  _DirectoryClient() : super(MockClient((_) async => http.Response('{}', 200)));

  late Completer<List<QuarkDirectoryEntry>> pending;

  @override
  Future<List<QuarkDirectoryEntry>> listDirectories({
    required String cookie,
    String parentFid = '0',
  }) {
    pending = Completer<List<QuarkDirectoryEntry>>();
    return pending.future;
  }
}
