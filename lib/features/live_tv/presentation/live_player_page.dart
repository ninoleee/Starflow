import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/playback/application/active_playback_cleanup.dart';
import 'package:starflow/features/playback/application/playback_session.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import '../application/live_playback_controller.dart';
import '../data/live_repository.dart';
import '../domain/live_models.dart';
import 'live_widgets.dart';

class LivePlayerPage extends ConsumerStatefulWidget {
  const LivePlayerPage(
      {super.key,
      required this.initialChannel,
      required this.snapshot,
      this.engineFactory});
  final LiveChannel initialChannel;
  final LiveSnapshot snapshot;
  @visibleForTesting
  final LiveEngine Function()? engineFactory;
  @override
  ConsumerState<LivePlayerPage> createState() => _LivePlayerPageState();
}

class _LivePlayerPageState extends ConsumerState<LivePlayerPage>
    with WidgetsBindingObserver {
  LivePlaybackController? _controller;
  late LiveSnapshot _snapshot = widget.snapshot;
  late LiveChannel _channel = widget.initialChannel;
  late bool _exo = !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      widget.snapshot.engine == 'exo';
  bool _list = false, _controls = true, _guide = false;
  bool _tools = false, _switching = false, _exiting = false;
  bool _foreground = true;
  bool _muted = false;
  String _group = '';
  int _viewKey = 0, _session = 0, _attachment = 0;
  Timer? _hide, _clock;
  final _focus = FocusNode(debugLabel: 'live-player', skipTraversal: true);
  final _toolsFocus = FocusNode(debugLabel: 'live-tools');
  final _overlayFocus = FocusNode(debugLabel: 'live-overlay-close');
  final _guideFirstFocus = FocusNode(debugLabel: 'live-guide-first');
  late final _performance = ref.read(playbackPerformanceModeProvider.notifier);
  bool _priorPerformance = false;
  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _priorPerformance = _performance.state;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _performance.state = true;
      if (!_exo || widget.engineFactory != null) {
        _attach(
            widget.engineFactory?.call() ??
                MpvLiveEngine(ref.read(appSettingsProvider).networkProxy),
            _session);
      }
      _focus.requestFocus();
      _autoHide();
    });
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _release(LiveEngine engine) async {
    try {
      await engine.dispose();
    } catch (_) {}
  }

  bool _isCurrent(int session) => mounted && !_exiting && session == _session;

  Future<void> _attach(LiveEngine engine, int session) async {
    if (!_isCurrent(session)) {
      await _release(engine);
      return;
    }
    final attachment = ++_attachment;
    await ActivePlaybackCleanupCoordinator.cleanupAll(reason: 'live-open');
    if (!_isCurrent(session) || attachment != _attachment) {
      await _release(engine);
      return;
    }
    final old = _controller;
    old?.removeListener(_changed);
    if (old != null) {
      try {
        await old.close();
      } finally {
        old.dispose();
      }
    }
    if (!_isCurrent(session) || attachment != _attachment) {
      await _release(engine);
      return;
    }
    final repository = ref.read(liveRepositoryProvider);
    _controller = LivePlaybackController(
        engine: engine, onReady: repository.remember, muted: _muted)
      ..addListener(_changed);
    if (_foreground) {
      _controller!
          .select(_channel, preferredLine: _snapshot.preference(_channel).line);
    } else {
      _controller!.suspend();
    }
    setState(() {});
  }

  void _changed() {
    _muted = _controller?.muted ?? _muted;
    if (mounted) setState(() {});
  }

  void _autoHide() {
    _hide?.cancel();
    if (_list || _guide || _tools) return;
    _hide = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent == false ||
          !_focus.hasPrimaryFocus) {
        _autoHide();
        return;
      }
      setState(() => _controls = false);
      _focus.requestFocus();
    });
  }

  void _select(LiveChannel channel) {
    setState(() {
      _channel = channel;
      _list = false;
      _guide = false;
      _tools = false;
      _controls = true;
    });
    if (_foreground) {
      _controller?.select(channel,
          preferredLine: _snapshot.preference(channel).line);
    }
    _focus.requestFocus();
    _autoHide();
  }

  void _step(int delta) {
    final channels = _snapshot.visible();
    if (channels.isEmpty) return;
    final index = channels.indexWhere((c) => c.id == _channel.id);
    _select(channels[(index + delta + channels.length) % channels.length]);
  }

  void _openOverlay({required bool guide}) {
    setState(() {
      _guide = guide;
      _list = !guide;
      _tools = false;
      _controls = true;
    });
    _hide?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (_list || _guide)) _overlayFocus.requestFocus();
    });
  }

  Future<void> _switchEngine() async {
    if (_switching || _exiting) return;
    final session = ++_session;
    ++_attachment;
    final old = _controller;
    setState(() {
      _switching = true;
      _controller = null;
    });
    old?.removeListener(_changed);
    try {
      await old?.close();
    } catch (_) {
      // Native views may already have been removed during route teardown.
    } finally {
      old?.dispose();
    }
    if (!_isCurrent(session)) return;
    final exo = !_exo;
    try {
      await ref.read(liveRepositoryProvider).setEngine(exo ? 'exo' : 'mpv');
    } catch (_) {
      if (mounted && _isCurrent(session)) liveMessage(context, '播放内核偏好保存失败');
    }
    if (!_isCurrent(session)) return;
    setState(() {
      _exo = exo;
      _switching = false;
      _viewKey++;
    });
    if (!_exo || widget.engineFactory != null) {
      unawaited(_attach(
          widget.engineFactory?.call() ??
              MpvLiveEngine(ref.read(appSettingsProvider).networkProxy),
          session));
    }
  }

  Future<void> _audio() async {
    try {
      final engine = _controller?.engine;
      final controller = _controller;
      final generation = controller?.generation;
      final tracks = await engine?.audioTracks() ?? [];
      if (!mounted ||
          _exiting ||
          !identical(controller, _controller) ||
          generation == null ||
          !controller!.acceptsAudioSelection(generation)) {
        return;
      }
      final id = await showDialog<String>(
          context: context,
          builder: (c) => SimpleDialog(title: const Text('音轨'), children: [
                if (tracks.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(24), child: Text('暂无可选音轨')),
                for (final t in tracks)
                  TvDialogOption(
                      isTelevision:
                          ref.read(isTelevisionProvider).value ?? false,
                      autofocus: t == tracks.first,
                      onPressed: () => Navigator.pop(c, t.$1),
                      child: Text(t.$2)),
              ]));
      if (id != null && identical(controller, _controller)) {
        await controller.selectAudio(generation, id);
      }
    } catch (_) {
      if (mounted) liveMessage(context, '音轨切换失败');
    }
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (ModalRoute.of(context)?.isCurrent == false) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (event is KeyDownEvent) Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (!_focus.hasPrimaryFocus) {
      final direction = switch (key) {
        LogicalKeyboardKey.arrowUp => TraversalDirection.up,
        LogicalKeyboardKey.arrowDown => TraversalDirection.down,
        LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
        LogicalKeyboardKey.arrowRight => TraversalDirection.right,
        _ => null,
      };
      if (direction != null) {
        final primary = FocusManager.instance.primaryFocus;
        if (_guide &&
            _overlayFocus.hasPrimaryFocus &&
            direction == TraversalDirection.down &&
            _guideFirstFocus.context != null) {
          _guideFirstFocus.requestFocus();
        } else if ((_list || _guide) && direction == TraversalDirection.down) {
          primary?.nextFocus();
        } else if ((_list || _guide) && direction == TraversalDirection.up) {
          primary?.previousFocus();
        } else {
          handleTvDirectionalFocusBoundary(context, direction);
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.contextMenu) {
      if (event is KeyDownEvent) {
        setState(() {
          _controls = true;
          _list = false;
          _guide = false;
          _tools = true;
        });
        _hide?.cancel();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _toolsFocus.requestFocus();
        });
      }
      return KeyEventResult.handled;
    }
    if (_list || _guide || _tools) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.channelUp) {
      _step(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.channelDown) {
      _step(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) {
        _openOverlay(guide: false);
      }
      _hide?.cancel();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.contextMenu) {
      if (event is KeyDownEvent) {
        _openOverlay(guide: key == LogicalKeyboardKey.arrowRight);
      }
      _hide?.cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_exiting) return;
    if (state == AppLifecycleState.resumed) {
      if (_controller?.status == 'suspended') {
        _controller?.select(_channel,
            preferredLine: _controller!.channel?.id == _channel.id
                ? _controller!.line
                : _snapshot.preference(_channel).line,
            resetBudget: false);
      }
    } else {
      _controller?.suspend();
    }
  }

  @override
  void dispose() {
    _exiting = true;
    ++_session;
    ++_attachment;
    WidgetsBinding.instance.removeObserver(this);
    _hide?.cancel();
    _clock?.cancel();
    _focus.dispose();
    _toolsFocus.dispose();
    _overlayFocus.dispose();
    _guideFirstFocus.dispose();
    _controller?.removeListener(_changed);
    _controller?.dispose();
    final previous = _priorPerformance;
    Future.microtask(() {
      if (_performance.mounted) _performance.state = previous;
    });
    super.dispose();
  }

  void _closeOverlay() {
    setState(() {
      _list = false;
      _guide = false;
      _tools = false;
    });
    _focus.requestFocus();
    _autoHide();
  }

  @override
  Widget build(BuildContext context) {
    final latest = ref.watch(liveSnapshotProvider).value;
    if (latest != null) _snapshot = latest;
    final controller = _controller;
    final session = _session;
    final guide = ref.watch(liveGuideProvider(_channel.id));
    final programmes = guide.value ?? [];
    final now = DateTime.now(),
        current =
            programmes.where((p) => p.contains(DateTime.now())).firstOrNull;
    final next = programmes.where((p) => p.start.isAfter(now)).firstOrNull;
    final groups = _snapshot
        .visible()
        .map(_snapshot.group)
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList();
    final group = groups.contains(_group) ? _group : '';
    final channels = _snapshot
        .visible()
        .where((c) => group.isEmpty || _snapshot.group(c) == group)
        .toList();
    return PopScope(
      canPop: !_list && !_guide && !_tools,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _closeOverlay();
        } else {
          _exiting = true;
          ++_session;
          ++_attachment;
          _controller?.suspend();
        }
      },
      child: Scaffold(
          backgroundColor: Colors.black,
          body: Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.arrowUp):
                    DirectionalFocusIntent(TraversalDirection.up),
                SingleActivator(LogicalKeyboardKey.arrowDown):
                    DirectionalFocusIntent(TraversalDirection.down),
                SingleActivator(LogicalKeyboardKey.arrowLeft):
                    DirectionalFocusIntent(TraversalDirection.left),
                SingleActivator(LogicalKeyboardKey.arrowRight):
                    DirectionalFocusIntent(TraversalDirection.right),
              },
              child: TvPageFocusScope(
                  isTelevision: ref.watch(isTelevisionProvider).value ?? false,
                  child: Focus(
                    focusNode: _focus,
                    onKeyEvent: _key,
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _controls = !_controls);
                        _autoHide();
                      },
                      child: Stack(fit: StackFit.expand, children: [
                        if (_exo && widget.engineFactory == null)
                          ExcludeFocus(
                              child: AndroidView(
                                  key: ValueKey(_viewKey),
                                  viewType: 'starflow/live_tv',
                                  onPlatformViewCreated: (id) =>
                                      _attach(ExoLiveEngine(id), session)))
                        else if (controller?.engine is MpvLiveEngine &&
                            (controller!.engine as MpvLiveEngine).video != null)
                          Video(
                              key: ObjectKey(
                                  (controller.engine as MpvLiveEngine).video),
                              controller:
                                  (controller.engine as MpvLiveEngine).video!,
                              controls: NoVideoControls),
                        if (controller == null || controller.busy)
                          const Center(child: CircularProgressIndicator()),
                        if (controller?.status == 'failed' ||
                            controller?.status == 'paused')
                          Center(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                Text(
                                    controller?.status == 'paused'
                                        ? '播放已暂停'
                                        : '当前频道播放失败',
                                    style:
                                        const TextStyle(color: Colors.white)),
                                const SizedBox(height: 12),
                                StarflowButton(
                                    label: controller?.status == 'paused'
                                        ? '继续播放'
                                        : '重试',
                                    autofocus: true,
                                    onPressed: () => controller!.select(
                                        _channel,
                                        preferredLine: controller.line)),
                              ])),
                        if (_controls && !_list && !_guide)
                          SafeArea(
                              child: Align(
                                  alignment: Alignment.topCenter,
                                  child: ColoredBox(
                                      color: const Color(0xD9000000),
                                      child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Row(children: [
                                            LiveIconButton(
                                                icon: Icons.arrow_back,
                                                label: '退出直播',
                                                onPressed: () =>
                                                    Navigator.pop(context)),
                                            Expanded(
                                                child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                  Text(_snapshot.name(_channel),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 20)),
                                                  Text(
                                                      current == null
                                                          ? '暂无节目单'
                                                          : '${liveTime(current.start)} ${current.title}',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                          color:
                                                              Colors.white70)),
                                                  if (next != null)
                                                    Text(
                                                        '接下来 ${liveTime(next.start)} ${next.title}',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                            color: Colors
                                                                .white70)),
                                                ])),
                                            Text(_exo ? 'Exo' : 'MPV',
                                                style: const TextStyle(
                                                    color: Colors.white70)),
                                          ]))))),
                        if (_controls && !_list && !_guide)
                          SafeArea(
                              child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: ColoredBox(
                                      color: const Color(0xD9000000),
                                      child: Wrap(
                                          alignment: WrapAlignment.center,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            LiveIconButton(
                                                icon: Icons.skip_previous,
                                                label: '上一频道',
                                                onPressed: () => _step(-1)),
                                            LiveIconButton(
                                                icon: Icons.list,
                                                focusNode: _toolsFocus,
                                                label: '频道列表',
                                                onPressed: () =>
                                                    _openOverlay(guide: false)),
                                            LiveIconButton(
                                                icon: Icons.skip_next,
                                                label: '下一频道',
                                                onPressed: () => _step(1)),
                                            LiveIconButton(
                                                icon: Icons.calendar_view_day,
                                                label: '节目单',
                                                onPressed: () =>
                                                    _openOverlay(guide: true)),
                                            LiveIconButton(
                                                icon: Icons.audiotrack,
                                                label: '音轨',
                                                onPressed: _audio),
                                            LiveIconButton(
                                                icon: controller?.muted == true
                                                    ? Icons.volume_off
                                                    : Icons.volume_up,
                                                label: '静音切换',
                                                onPressed: () async {
                                                  try {
                                                    await controller
                                                        ?.toggleMute();
                                                  } catch (_) {}
                                                }),
                                            if (!kIsWeb &&
                                                defaultTargetPlatform ==
                                                    TargetPlatform.android)
                                              LiveIconButton(
                                                  icon: Icons.swap_horiz,
                                                  label: '切换播放内核',
                                                  onPressed:
                                                      controller == null ||
                                                              _switching
                                                          ? null
                                                          : _switchEngine),
                                            DropdownButton<int>(
                                                value: controller?.line ?? 0,
                                                dropdownColor: Colors.black,
                                                items: [
                                                  for (var i = 0;
                                                      i < _channel.lines.length;
                                                      i++)
                                                    DropdownMenuItem(
                                                        value: i,
                                                        child: Text(
                                                            '线路 ${i + 1}',
                                                            style:
                                                                const TextStyle(
                                                                    color: Colors
                                                                        .white)))
                                                ],
                                                onChanged: controller == null ||
                                                        !_foreground
                                                    ? null
                                                    : (v) {
                                                        if (v != null) {
                                                          controller.select(
                                                              _channel,
                                                              preferredLine: v);
                                                        }
                                                      }),
                                          ])))),
                        if (_list || _guide)
                          SafeArea(
                              child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: SizedBox(
                                    width:
                                        MediaQuery.sizeOf(context).width < 480
                                            ? MediaQuery.sizeOf(context).width
                                            : 440,
                                    child: Material(
                                        color: const Color(0xF0202020),
                                        child: Column(children: [
                                          Row(children: [
                                            LiveIconButton(
                                                icon: Icons.close,
                                                label: '关闭',
                                                focusNode: _overlayFocus,
                                                autofocus: true,
                                                onPressed: _closeOverlay),
                                            Expanded(
                                                child:
                                                    Text(_guide ? '节目单' : '频道'))
                                          ]),
                                          if (_list)
                                            DropdownButton<String>(
                                                value: group,
                                                isExpanded: true,
                                                items: [
                                                  const DropdownMenuItem(
                                                      value: '',
                                                      child: Text('全部分组')),
                                                  for (final g in groups)
                                                    DropdownMenuItem(
                                                        value: g,
                                                        child: Text(g,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis))
                                                ],
                                                onChanged: (v) => setState(
                                                    () => _group = v ?? '')),
                                          Expanded(
                                              child: _guide
                                                  ? (programmes.isEmpty
                                                      ? Center(
                                                          child: guide.isLoading
                                                              ? const CircularProgressIndicator()
                                                              : guide.hasError
                                                                  ? StarflowButton(
                                                                      label:
                                                                          '重新读取节目单',
                                                                      onPressed: () =>
                                                                          ref.invalidate(liveGuideProvider(_channel
                                                                              .id)))
                                                                  : const Text(
                                                                      '暂无节目单'))
                                                      : ListView.builder(
                                                          cacheExtent: 0,
                                                          itemCount:
                                                              programmes.length,
                                                          itemBuilder:
                                                              (ctx, i) {
                                                            final p =
                                                                programmes[i];
                                                            return TvFocusableAction(
                                                                focusNode: i ==
                                                                        0
                                                                    ? _guideFirstFocus
                                                                    : null,
                                                                onPressed: () => showDialog<
                                                                        void>(
                                                                    context:
                                                                        context,
                                                                    builder: (c) =>
                                                                        AlertDialog(
                                                                          title:
                                                                              Text(p.title),
                                                                          content:
                                                                              SingleChildScrollView(child: Text(p.description.isEmpty ? '暂无节目简介' : p.description)),
                                                                          actions: [
                                                                            StarflowButton(
                                                                                label: '关闭',
                                                                                autofocus: true,
                                                                                onPressed: () => Navigator.pop(c))
                                                                          ],
                                                                        )),
                                                                child: ListTile(
                                                                    selected: p
                                                                        .contains(
                                                                            now),
                                                                    title: Text(
                                                                        '${liveTime(p.start)} - ${liveTime(p.end)}  ${p.title}'),
                                                                    subtitle: Text(
                                                                        '${p.start.toLocal().month}/${p.start.toLocal().day}${p.description.isEmpty ? "" : " · ${p.description}"}',
                                                                        maxLines:
                                                                            3,
                                                                        overflow:
                                                                            TextOverflow.ellipsis)));
                                                          }))
                                                  : ListView.builder(
                                                      cacheExtent: 0,
                                                      itemCount:
                                                          channels.length,
                                                      itemBuilder: (ctx, i) {
                                                        final c = channels[i];
                                                        return TvFocusableAction(
                                                            focusId:
                                                                'live-overlay:${c.id}',
                                                            onPressed: () =>
                                                                _select(c),
                                                            child: ListTile(
                                                                selected: c
                                                                        .id ==
                                                                    _channel.id,
                                                                leading: Icon(c.id ==
                                                                        _channel
                                                                            .id
                                                                    ? Icons
                                                                        .play_arrow
                                                                    : Icons
                                                                        .live_tv),
                                                                title: Text(
                                                                    _snapshot
                                                                        .name(
                                                                            c),
                                                                    maxLines: 1,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis)));
                                                      })),
                                        ])),
                                  ))),
                      ]),
                    ),
                  )))),
    );
  }
}
