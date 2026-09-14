import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/search/domain/cloud_save_feedback.dart';
import 'package:starflow/features/search/presentation/cloud_save_feedback_controller.dart';

Future<CloudSaveFeedbackController> _pump(WidgetTester tester,
    {bool Function()? isActive, Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  BuildContext? context;
  await tester
      .pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (value) {
    context = value;
    return const SizedBox();
  }))));
  final controller = CloudSaveFeedbackController(() => context,
      isActive: isActive ?? () => true);
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(1280, 900),
    const Size(1920, 1080)
  ]) {
    for (final drive in CloudSaveDrive.values) {
      testWidgets('$drive progress is replaced by the summary at $size',
          (tester) async {
        final controller = await _pump(tester, size: size);
        final session = controller.start();
        session.showProgress(CloudSaveProgress.saving(drive));
        await tester.pumpAndSettle();
        expect(find.text(drive.savingMessage), findsOneWidget);
        final message = CloudSaveSummary(
          drive: drive,
          savedCount: 3,
          skippedCount: 21,
          smartStrmTriggered: true,
          smartStrmDelaySeconds: 5,
          refreshDelaySeconds: 10,
        ).buildSuccessMessage();
        session.complete(message);
        session.closeProgress();
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        expect(find.text(drive.savingMessage), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('failure closes progress and discards a pending refresh notice',
      (tester) async {
    final session = (await _pump(tester)).start();
    session.showProgress(const CloudSaveProgress.saving(CloudSaveDrive.quark));
    session.showRefreshFailure('refresh failure');
    session.fail('save failed');
    session.closeProgress();
    await tester.pumpAndSettle();
    expect(find.text('save failed'), findsOneWidget);
    expect(find.text('夸克保存中...'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('refresh failure'), findsNothing);
  });

  testWidgets(
      'a fast refresh failure follows, rather than replaces, the summary',
      (tester) async {
    final session = (await _pump(tester)).start();
    session
        .showProgress(const CloudSaveProgress.saving(CloudSaveDrive.cloud115));
    session.showRefreshFailure('refresh failure');
    session.complete('save summary');
    await tester.pumpAndSettle();
    expect(find.text('save summary'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('refresh failure'), findsOneWidget);
  });

  testWidgets('concurrent sessions cannot close each other from finally',
      (tester) async {
    final controller = await _pump(tester);
    final first = controller.start();
    first.showProgress(const CloudSaveProgress.saving(CloudSaveDrive.quark));
    await tester.pumpAndSettle();
    final second = controller.start();
    second
        .showProgress(const CloudSaveProgress.saving(CloudSaveDrive.cloud115));
    await tester.pumpAndSettle();
    first.closeProgress();
    await tester.pumpAndSettle();
    expect(find.text('115 保存中...'), findsOneWidget);
    second.complete('save summary');
    await tester.pumpAndSettle();
    expect(find.text('save summary'), findsOneWidget);
  });

  testWidgets('synchronous replacement forgets the previous progress owner',
      (tester) async {
    final controller = await _pump(tester);
    final first = controller.start();
    first.showProgress(const CloudSaveProgress.saving(CloudSaveDrive.quark));
    await tester.pumpAndSettle();
    final second = controller.start();
    second
        .showProgress(const CloudSaveProgress.saving(CloudSaveDrive.cloud115));
    first.closeProgress();
    await tester.pumpAndSettle();
    expect(find.text('115 保存中...'), findsOneWidget);
    second.complete('save summary');
    await tester.pumpAndSettle();
    expect(find.text('save summary'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new save replaces queued notices before showing progress',
      (tester) async {
    final controller = await _pump(tester);
    final first = controller.start();
    first.complete('first summary');
    first.showRefreshFailure('first refresh failure');
    await tester.pumpAndSettle();
    final second = controller.start();
    second
        .showProgress(const CloudSaveProgress.saving(CloudSaveDrive.cloud115));
    await tester.pumpAndSettle();
    expect(find.text('115 保存中...'), findsOneWidget);
    second.complete('second summary');
    await tester.pumpAndSettle();
    expect(find.text('second summary'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'progress expires after two minutes and later completion still works',
      (tester) async {
    final session = (await _pump(tester)).start();
    session.showProgress(const CloudSaveProgress.saving(CloudSaveDrive.quark));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 2));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    session.complete('save summary');
    await tester.pumpAndSettle();
    expect(find.text('save summary'), findsOneWidget);
  });

  testWidgets('disposing closes progress and rejects all late callbacks',
      (tester) async {
    final controller = await _pump(tester);
    final session = controller.start();
    session.showProgress(const CloudSaveProgress.saving(CloudSaveDrive.quark));
    await tester.pumpAndSettle();
    controller.dispose();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    session.showProgress(
        const CloudSaveProgress.sanitizingNames(CloudSaveDrive.quark, 1));
    session.complete('save summary');
    session.showRefreshFailure('refresh failure');
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive pages suppress background refresh notices',
      (tester) async {
    final session = (await _pump(tester, isActive: () => false)).start();
    session.complete('save summary');
    session.showRefreshFailure('refresh failure');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}
