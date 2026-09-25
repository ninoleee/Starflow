import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/playback/presentation/widgets/player_variant_picker_dialog.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'playback_variant_resolver_test.dart' show target;

void main() {
  for (final tv in [false, true]) {
    testWidgets('version picker loading, current, selection and layout TV=$tv',
        (tester) async {
      await tester.binding
          .setSurfaceSize(tv ? const Size(1280, 720) : const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pending = Completer<List<PlaybackTarget>>();
      PlaybackTarget? selected;
      await tester.pumpWidget(ProviderScope(
          overrides: [isTelevisionProvider.overrideWithValue(AsyncData(tv))],
          child: MaterialApp(
              home: Builder(
                  builder: (context) => TextButton(
                      child: const Text('Open'),
                      onPressed: () async {
                        selected = await showDialog<PlaybackTarget>(
                            context: context,
                            builder: (_) => PlayerVariantPickerDialog(
                                target: target,
                                isTelevision: tv,
                                load: () => pending.future));
                      })))));
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final next = target.copyWith(
          preferredMediaSourceId: 'b',
          actualAddress: '/Movie/another-long-version-name-2160p.mkv');
      pending.complete([target, next]);
      await tester.pumpAndSettle();
      expect(find.text('a.mkv  当前'), findsOneWidget);
      if (tv) {
        final option = find.widgetWithText(
            TvDialogOption, 'another-long-version-name-2160p.mkv');
        tester
            .widget<FocusableActionDetector>(find.descendant(
                of: option, matching: find.byType(FocusableActionDetector)))
            .focusNode!
            .requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
      } else {
        await tester.tap(find.text('another-long-version-name-2160p.mkv'));
      }
      await tester.pumpAndSettle();
      expect(selected, same(next));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed loading can retry and single version is explicit',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
        home: PlayerVariantPickerDialog(
      target: target,
      isTelevision: false,
      load: () async {
        if (++attempts == 1) throw StateError('offline');
        return [target];
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('版本加载失败，重试'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('当前仅有一个播放版本'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final cancel in [false, true]) {
    testWidgets(
        'current version or cancel closes picker without another target ($cancel)',
        (tester) async {
      PlaybackTarget? selected;
      var completed = false;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => TextButton(
                  child: const Text('Open'),
                  onPressed: () async {
                    selected = await showDialog<PlaybackTarget>(
                        context: context,
                        builder: (_) => PlayerVariantPickerDialog(
                            target: target,
                            isTelevision: false,
                            load: () async => [target]));
                    completed = true;
                  }))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(cancel ? '取消' : 'a.mkv  当前'));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(selected, cancel ? isNull : same(target));
      expect(tester.takeException(), isNull);
    });
  }
}
