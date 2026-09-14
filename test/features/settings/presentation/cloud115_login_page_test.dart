import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:starflow/features/settings/data/cloud115_login_client.dart';
import 'package:starflow/features/settings/presentation/cloud115_login_page.dart';

class FakeLoginClient extends Cloud115LoginClient {
  FakeLoginClient()
      : super(MockClient((_) async => throw StateError('Unexpected request')));
  final statusResult = Completer<Cloud115QrStatus>();
  int exchanges = 0;
  @override
  Future<Cloud115QrToken> createToken() async => const Cloud115QrToken(
      uid: 'u', time: '1', sign: 's', qrcode: 'https://115.com/scan');
  @override
  Future<Cloud115QrStatus> status(Cloud115QrToken token) => statusResult.future;
  @override
  Future<String> exchange(Cloud115QrToken token) async {
    exchanges++;
    return 'UID=u; CID=c; SEID=s';
  }
}

void main() {
  for (final cancel in [false, true]) {
    testWidgets(
        'QR confirmation returns cookie only while page active: cancel=$cancel',
        (tester) async {
      final client = FakeLoginClient();
      String? cookie;
      await tester.pumpWidget(ProviderScope(
          overrides: [
            cloud115LoginClientProvider.overrideWithValue(client),
          ],
          child: MaterialApp(
              home: Builder(
                  builder: (context) => Scaffold(
                          body: TextButton(
                        onPressed: () async {
                          cookie = await Navigator.of(context).push<String>(
                              MaterialPageRoute(
                                  builder: (_) => const Cloud115LoginPage()));
                        },
                        child: const Text('Login'),
                      ))))));
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();
      expect(find.text('等待 115 App 扫码'), findsOneWidget);
      if (cancel) {
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
      }
      client.statusResult.complete(Cloud115QrStatus.confirmed);
      await tester.pumpAndSettle();
      expect(cookie, cancel ? isNull : 'UID=u; CID=c; SEID=s');
      expect(client.exchanges, cancel ? 0 : 1);
      expect(tester.takeException(), isNull);
    });
  }
}
