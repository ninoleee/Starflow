import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/presentation/webdav_directory_picker_page.dart';

const _source = MediaSourceConfig(
  id: 'nas',
  name: 'NAS',
  kind: MediaSourceKind.nas,
  endpoint: 'https://example.com/dav/',
  enabled: true,
);

void main() {
  for (final fail in [false, true]) {
    testWidgets('TV root retains select focus while loading/empty/error: $fail',
        (tester) async {
      final client = _DirectoryClient();
      await tester.pumpWidget(_host(client));
      await tester.pump();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel,
          'webdav-directory-select');
      if (fail) {
        client.pending.completeError(StateError('unavailable'));
      } else {
        client.pending.complete([]);
      }
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel,
          'webdav-directory-select');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('TV folder replacement recovers only missing focus',
      (tester) async {
    final client = _DirectoryClient();
    await tester.pumpWidget(_host(client));
    client.pending.complete(const [
      MediaCollection(
        id: 'https://example.com/dav/child/',
        title: 'Child',
        sourceId: 'nas',
        sourceName: 'NAS',
        sourceKind: MediaSourceKind.nas,
      ),
    ]);
    await tester.pumpAndSettle();
    final folder = tester
        .widgetList<TvFocusableAction>(find.byType(TvFocusableAction))
        .firstWhere((widget) =>
            widget.focusId ==
            'webdav-directory:https://example.com/dav/child/');
    folder.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        'webdav-directory-select');
    final parent = tester
        .widgetList<TvFocusableAction>(find.byType(TvFocusableAction))
        .firstWhere((widget) => widget.focusId == 'webdav-directory:parent');
    parent.focusNode!.requestFocus();
    await tester.pump();
    client.pending.complete([]);
    await tester.pumpAndSettle();
    expect(parent.focusNode!.hasPrimaryFocus, isTrue);
  });
}

Widget _host(_DirectoryClient client) => ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWith((ref) => true),
        webDavNasClientProvider.overrideWithValue(client),
      ],
      child:
          const MaterialApp(home: WebDavDirectoryPickerPage(source: _source)),
    );

class _DirectoryClient extends WebDavNasClient {
  _DirectoryClient() : super(MockClient((_) async => http.Response('', 200)));

  late Completer<List<MediaCollection>> pending;

  @override
  Future<List<MediaCollection>> fetchCollections(MediaSourceConfig source,
      {String? directoryId}) {
    pending = Completer<List<MediaCollection>>();
    return pending.future;
  }
}
