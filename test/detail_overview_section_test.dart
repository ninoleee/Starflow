import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/presentation/widgets/detail_overview_section.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const _raw = '原始视频：<a href="https://www.bilibili.com/video/BV1yhBjBSEzn/">'
    'BV1yhBjBSEzn</a><br/><br/>正文第一段。\n\n正文第二段。';
const _textKey = ValueKey('detail-overview-text');
const _captureKey = ValueKey('overview-capture');

Widget _app(
  String overview, {
  bool television = false,
  Future<bool> Function(Uri)? launcher,
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [
      isTelevisionProvider.overrideWith((ref) => television),
      appSettingsProvider.overrideWithValue(const AppSettings(
        mediaSources: [],
        searchProviders: [],
        homeModules: [],
        doubanAccount: DoubanAccountConfig(enabled: false),
      )),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: TvPageFocusScope(
        isTelevision: television,
        child: Scaffold(
          body: RepaintBoundary(
            key: _captureKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                DetailOverviewSection(
                  title: '重要的是那些微小的念头',
                  episodeTitle: '第 1 季 第 2 集',
                  overview: overview,
                  isTelevision: television,
                  focusId: 'test:overview',
                  sourceLauncher: launcher,
                ),
                const Text('剧照'),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    if (const bool.fromEnvironment('OVERVIEW_SCREENSHOTS')) {
      final loader = FontLoader('Roboto')
        ..addFont(
          File('/System/Library/Fonts/STHeiti Light.ttc')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });
  testWidgets('shows clean paragraphs and hides sources behind more',
      (tester) async {
    await tester.pumpWidget(_app(_raw));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(_textKey)).data, '正文第一段。\n\n正文第二段。');
    expect(find.textContaining('BV1yh'), findsNothing);
    expect(find.text('展开全文'), findsNothing);
    expect(find.byTooltip('更多'), findsOneWidget);
  });

  testWidgets(
      'link-only and empty overviews show fallback without empty controls',
      (tester) async {
    await tester.pumpWidget(_app('来源：<a href="https://example.com">编号</a>'));
    expect(find.text('暂无简介'), findsOneWidget);
    expect(find.byTooltip('更多'), findsOneWidget);
    await tester.pumpWidget(_app(''));
    expect(find.text('暂无简介'), findsOneWidget);
    expect(find.byTooltip('更多'), findsNothing);
    expect(find.text('展开全文'), findsNothing);
  });

  testWidgets('long overview expands, collapses and resets on changed metadata',
      (tester) async {
    final long = List.filled(30, '这一段正文需要完整阅读。').join('\n');
    await tester.pumpWidget(_app(long));
    await tester.tap(find.text('展开全文'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(_textKey)).maxLines, isNull);
    await tester.ensureVisible(find.text('收起'));
    await tester.tap(find.text('收起'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(_textKey)).maxLines, 6);
    await tester.tap(find.text('展开全文'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app('新简介'));
    await tester.pumpAndSettle();
    expect(find.text('收起'), findsNothing);
    expect(tester.widget<Text>(find.byKey(_textKey)).maxLines, 6);
  });

  testWidgets('more opens source picker and launches only the selected source',
      (tester) async {
    final launched = <Uri>[];
    await tester.pumpWidget(
        _app('$_raw<a href="https://example.com/second">另一个</a>',
            launcher: (uri) async {
      launched.add(uri);
      return true;
    }));
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(launched, isEmpty);
    await tester.tap(find.text('视频来源'));
    await tester.pumpAndSettle();
    expect(launched, isEmpty);
    await tester.tap(find.text('example.com'));
    await tester.pumpAndSettle();
    expect(launched.single.toString(), 'https://example.com/second');
  });

  testWidgets('failed source launch shows a recoverable error', (tester) async {
    await tester.pumpWidget(
        _app(_raw, launcher: (_) async => throw StateError('no browser')));
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('视频来源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('www.bilibili.com'));
    await tester.pumpAndSettle();
    expect(find.text('无法打开链接'), findsOneWidget);
  });

  testWidgets('cancelling either menu never launches a source', (tester) async {
    final launched = <Uri>[];
    await tester.pumpWidget(_app(_raw, launcher: (uri) async {
      launched.add(uri);
      return true;
    }));
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('视频来源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(launched, isEmpty);
  });

  testWidgets('TV enter opens sources and back restores more focus',
      (tester) async {
    await tester.pumpWidget(_app(_raw, television: true));
    final more =
        tester.widget<StarflowIconButton>(find.byType(StarflowIconButton));
    more.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('视频来源'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('www.bilibili.com'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('www.bilibili.com'), findsNothing);
    expect(more.focusNode!.hasFocus, isTrue);
  });

  testWidgets('TV long overview can scroll and collapse with remote keys',
      (tester) async {
    await tester.pumpWidget(
        _app(List.filled(50, '长正文的每一行都需要能读到。').join('\n'), television: true));
    final expand = tester.widget<StarflowButton>(find.byType(StarflowButton));
    expand.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final body = tester.widget<TvFocusableAction>(find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction &&
            widget.focusId == 'test:overview:body'));
    expect(body.focusNode!.hasFocus, isTrue);
    final scroll = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    expect(scroll.controller!.offset, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(scroll.controller!.offset, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('展开全文'), findsOneWidget);
    expect(expand.focusNode!.hasFocus, isTrue);
  });

  for (final width in [320.0, 1280.0]) {
    testWidgets('overview fits $width with large text', (tester) async {
      tester.view.reset();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.reset);
      final long = '$_raw\n\n${List.filled(20, '正文保留段落，来源单独收纳。').join()}';
      await tester
          .pumpWidget(_app(long, textScale: 1.5, television: width > 1000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('展开全文'), findsOneWidget);
      if (const bool.fromEnvironment('OVERVIEW_SCREENSHOTS')) {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/starflow-overview-${width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      if (width > 1000) {
        tester
            .widget<StarflowIconButton>(find.byType(StarflowIconButton))
            .focusNode!
            .requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      } else {
        await tester.tap(find.byTooltip('更多'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('视频来源'));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
