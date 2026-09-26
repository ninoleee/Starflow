import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/settings/data/aliyun_login_client.dart';
import 'package:starflow/features/settings/presentation/aliyun_login_page.dart';

class _Client extends Fake implements AliyunLoginClient {
  final results = <Completer<AliyunQrResult>>[];
  int created = 0;
  bool failCreate = false;
  Completer<AliyunQrToken>? pendingCreate;
  @override
  Future<AliyunQrToken> createToken() async {
    created++;
    if (failCreate) throw StateError('secret');
    if (pendingCreate != null) return pendingCreate!.future;
    return AliyunQrToken(
        t: '$created',
        ck: 'session',
        qrcode:
            'https://passport.aliyundrive.com/qrcodeCheck.htm?code=$created');
  }

  @override
  Future<AliyunQrResult> status(AliyunQrToken token) {
    final result = Completer<AliyunQrResult>();
    results.add(result);
    return result.future;
  }
}

Future<void> _open(WidgetTester tester, _Client client,
    {bool tv = false, ValueChanged<String?>? onResult}) async {
  tester.view.physicalSize = tv ? const Size(1920, 1080) : const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        aliyunLoginClientProvider.overrideWithValue(client),
        isTelevisionProvider.overrideWith((ref) => tv)
      ],
      child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        final token = await Navigator.of(context).push<String>(
                            MaterialPageRoute(
                                builder: (_) => const AliyunLoginPage()));
                        onResult?.call(token);
                      },
                      child: const Text('Login')))))));
  await tester.tap(find.text('Login'));
  await tester.pumpAndSettle();
}

void main() {
  for (final networkError in [false, true]) {
    testWidgets('poll resumes after overlay networkError=$networkError',
        (tester) async {
      final client = _Client();
      String? token;
      await _open(tester, client, onResult: (value) => token = value);
      unawaited(showDialog<void>(
          context: tester.element(find.byType(AliyunLoginPage)),
          builder: (_) => const AlertDialog(title: Text('Overlay'))));
      await tester.pumpAndSettle();
      if (networkError) {
        client.results.single.completeError(
            const AliyunLoginException('network', retryable: true));
      } else {
        client.results.single
            .complete(const AliyunQrResult(AliyunQrStatus.waiting));
      }
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(client.results.length, 1);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(client.results.length, 2);
      client.results.last.complete(const AliyunQrResult(
          AliyunQrStatus.confirmed,
          refreshToken: 'fresh'));
      await tester.pumpAndSettle();
      expect(token, 'fresh');
    });
  }

  testWidgets('background invalidates in-flight results and resumes same QR',
      (tester) async {
    final client = _Client();
    String? token;
    await _open(tester, client, onResult: (value) => token = value);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    client.results.first.complete(
        const AliyunQrResult(AliyunQrStatus.confirmed, refreshToken: 'stale'));
    await tester.pump(const Duration(seconds: 4));
    expect(token, isNull);
    expect(client.results.length, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(client.created, 1);
    expect(client.results.length, 2);
    client.results.last.complete(
        const AliyunQrResult(AliyunQrStatus.confirmed, refreshToken: 'fresh'));
    await tester.pumpAndSettle();
    expect(token, 'fresh');
  });

  testWidgets('transient error retries with bounded backoff', (tester) async {
    final client = _Client();
    await _open(tester, client);
    client.results.single
        .completeError(const AliyunLoginException('network', retryable: true));
    await tester.pumpAndSettle();
    expect(find.text('连接中断，正在重试（1/3）'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(client.results.length, 2);
    client.results.last.complete(const AliyunQrResult(AliyunQrStatus.scanned));
    await tester.pumpAndSettle();
    expect(find.text('已扫码，请在手机上确认'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('failed generation can be retried without leaking errors',
      (tester) async {
    final client = _Client()..failCreate = true;
    await _open(tester, client);
    expect(find.text('登录未完成，请重试'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    expect(client.results, isEmpty);
    client.failCreate = false;
    await tester.tap(find.text('刷新二维码'));
    await tester.pumpAndSettle();
    expect(find.text('等待阿里云盘 App 扫码'), findsOneWidget);
    expect(client.created, 2);
  });

  testWidgets('leaving during QR creation never starts polling',
      (tester) async {
    final pending = Completer<AliyunQrToken>();
    final client = _Client()..pendingCreate = pending;
    await tester.pumpWidget(ProviderScope(overrides: [
      aliyunLoginClientProvider.overrideWithValue(client),
    ], child: const MaterialApp(home: AliyunLoginPage())));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(const AliyunQrToken(
        t: '1',
        ck: 'session',
        qrcode: 'https://passport.aliyundrive.com/qrcodeCheck.htm?code=1'));
    await tester.pumpAndSettle();
    expect(client.results, isEmpty);
    expect(tester.takeException(), isNull);
  });
  for (final tv in [false, true]) {
    for (final cancel in [false, true]) {
      testWidgets(
          'confirmation only returns on active page tv=$tv cancel=$cancel',
          (tester) async {
        final client = _Client();
        String? token;
        await _open(tester, client, tv: tv, onResult: (value) => token = value);
        expect(find.text('等待阿里云盘 App 扫码'), findsOneWidget);
        if (cancel) {
          tester.state<NavigatorState>(find.byType(Navigator)).pop();
          await tester.pumpAndSettle();
        }
        client.results.single.complete(const AliyunQrResult(
            AliyunQrStatus.confirmed,
            refreshToken: 'secret'));
        await tester.pumpAndSettle();
        expect(token, cancel ? isNull : 'secret');
        await tester.pump(const Duration(seconds: 5));
        expect(client.results.length, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('refresh isolates late confirmation from the previous QR',
      (tester) async {
    final client = _Client();
    String? token;
    await _open(tester, client, onResult: (value) => token = value);
    await tester.tap(find.text('刷新二维码'));
    await tester.pumpAndSettle();
    expect(client.created, 2);
    client.results.first.complete(const AliyunQrResult(AliyunQrStatus.confirmed,
        refreshToken: 'old-secret'));
    await tester.pumpAndSettle();
    expect(token, isNull);
    expect(find.byType(AliyunLoginPage), findsOneWidget);
    client.results.last.complete(const AliyunQrResult(AliyunQrStatus.confirmed,
        refreshToken: 'new-secret'));
    await tester.pumpAndSettle();
    expect(token, 'new-secret');
  });

  for (final terminal in [AliyunQrStatus.expired, AliyunQrStatus.cancelled]) {
    testWidgets('scanned then $terminal stops polling and can retry',
        (tester) async {
      final client = _Client();
      await _open(tester, client);
      client.results.single
          .complete(const AliyunQrResult(AliyunQrStatus.scanned));
      await tester.pumpAndSettle();
      expect(find.text('已扫码，请在手机上确认'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      client.results.last.complete(AliyunQrResult(terminal));
      await tester.pumpAndSettle();
      expect(find.text(terminal == AliyunQrStatus.expired ? '二维码已过期' : '登录已取消'),
          findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(client.results.length, 2);
      await tester.tap(find.text('刷新二维码'));
      await tester.pumpAndSettle();
      expect(client.created, 2);
    });
  }

  testWidgets('network error hides secrets and allows retry', (tester) async {
    final client = _Client();
    await _open(tester, client);
    client.results.single.completeError(StateError('secret'));
    await tester.pumpAndSettle();
    expect(find.text('登录未完成，请重试'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    await tester.tap(find.text('刷新二维码'));
    await tester.pumpAndSettle();
    expect(client.created, 2);
  });
}
