import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:starflow/app/theme/app_colors.dart';
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
import 'live_network_speed_label.dart';
import 'live_channel_picker.dart';

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
  bool _settings = false;
  bool _switching = false, _exiting = false;
  PhysicalKeyboardKey? _exitBackKey;
  LocalHistoryEntry? _overlayEntry;
  bool get _hasOverlay => _list || _guide || _settings;
  bool _foreground = true;
  bool _muted = false;
  final _channelPicker = GlobalKey<LiveChannelPickerState>();
  int _viewKey = 0, _session = 0, _attachment = 0;
  Timer? _hide, _clock;
  final _focus = FocusNode(debugLabel: 'live-player', skipTraversal: true);
  final _settingsFocus = FocusNode(debugLabel: 'live-settings-close');
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
      if (!mounted || !_foreground) return;
      if (_list) ref.invalidate(liveNowNextProvider);
      setState(() {});
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
    if (_hasOverlay) return;
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
    _closeOverlay();
    setState(() {
      _channel = channel;
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
    if (!guide) ref.invalidate(liveNowNextProvider);
    _retainPlayerRoute();
    setState(() {
      _settings = false;
      _guide = guide;
      _list = !guide;
      _controls = true;
    });
    _hide?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_list) {
        _channelPicker.currentState?.focusChannels();
      } else if (_guide) {
        _overlayFocus.requestFocus();
      }
    });
  }

  void _openSettings() {
    _retainPlayerRoute();
    setState(() {
      _list = false;
      _guide = false;
      _settings = true;
      _controls = true;
    });
    _hide?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _settings) _settingsFocus.requestFocus();
    });
  }

  void _retainPlayerRoute() {
    if (_overlayEntry != null) return;
    // Local history also intercepts Navigator.pop, which bypasses PopScope.
    final entry = LocalHistoryEntry(
      impliesAppBarDismissal: false,
      onRemove: () {
        _overlayEntry = null;
        if (mounted && !_exiting) _closeOverlay();
      },
    );
    _overlayEntry = entry;
    ModalRoute.of(context)!.addLocalHistoryEntry(entry);
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
    if (ModalRoute.of(context)?.isCurrent == false) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (event is KeyDownEvent) {
        _exitBackKey = null;
        if (_hasOverlay) {
          _closeOverlay();
        } else {
          // Keep this route focused until it has consumed the release.
          _exitBackKey = event.physicalKey;
        }
      } else if (event is KeyUpEvent && _exitBackKey == event.physicalKey) {
        _exitBackKey = null;
        Navigator.of(context).maybePop();
      }
      // Android must not redispatch the release as a second system back.
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;
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
        if (_list &&
            _overlayFocus.hasPrimaryFocus &&
            direction == TraversalDirection.down) {
          _channelPicker.currentState?.focusChannels();
        } else if (_guide &&
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
      if (event is KeyDownEvent) _openSettings();
      return KeyEventResult.handled;
    }
    if (_hasOverlay) return KeyEventResult.ignored;
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
        key == LogicalKeyboardKey.arrowRight) {
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
    if (!_foreground) _exitBackKey = null;
    if (_exiting) return;
    if (state == AppLifecycleState.resumed) {
      if (_list) ref.invalidate(liveNowNextProvider);
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
    _settingsFocus.dispose();
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
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      return;
    }
    if (!_hasOverlay) return;
    setState(() {
      _list = false;
      _guide = false;
      _settings = false;
      _controls = true;
    });
    _focus.requestFocus();
    _autoHide();
  }

  @override
  Widget build(BuildContext context) {
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final accent = AppActionColors.of(Theme.of(context)).primary;
    final latest = ref.watch(liveSnapshotProvider).value;
    if (latest != null) _snapshot = latest;
    final controller = _controller;
    final session = _session;
    final loading = controller == null || controller.busy;
    final showTopBar = _controls && !_hasOverlay;
    final fullWidthOverlay =
        MediaQuery.sizeOf(context).width < (_list ? 720 : 480);
    final speedSource = controller != null &&
            (controller.busy || controller.status == 'playing') &&
            controller.engine is LiveNetworkSpeedSource
        ? controller.engine as LiveNetworkSpeedSource
        : null;
    Widget speedLabel() => LiveNetworkSpeedLabel(
        source: _foreground ? speedSource : null,
        generation: controller?.generation ?? 0);
    final guide = ref.watch(liveGuideProvider(_channel.id));
    final nowNext = _list ? ref.watch(liveNowNextProvider).value : null;
    final programmes = guide.value ?? [];
    final now = DateTime.now(),
        current =
            programmes.where((p) => p.contains(DateTime.now())).firstOrNull;
    final next = programmes.where((p) => p.start.isAfter(now)).firstOrNull;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
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
                  isTelevision: isTelevision,
                  child: Focus(
                    focusNode: _focus,
                    onKeyEvent: _key,
                    child: GestureDetector(
                      onTap: () {
                        if (_hasOverlay) return;
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
                        if (loading)
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
                                if (controller?.status == 'failed' &&
                                    controller?.failureLabel != null)
                                  Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(controller!.failureLabel!,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              color: Colors.white70))),
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
                        if (showTopBar)
                          SafeArea(
                              child: Align(
                                  alignment: Alignment.topCenter,
                                  child: ColoredBox(
                                      key: const ValueKey(
                                          'live-player-top-bar-background'),
                                      color: Colors.black.withValues(alpha: .2),
                                      child: SizedBox(
                                          key: const ValueKey(
                                              'live-player-top-bar'),
                                          height: 112,
                                          child:
                                              MediaQuery.withClampedTextScaling(
                                                  maxScaleFactor: 1.2,
                                                  child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              12),
                                                      child: Row(children: [
                                                        if (!isTelevision)
                                                          LiveIconButton(
                                                              icon: Icons
                                                                  .arrow_back,
                                                              label: '退出直播',
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                      context)),
                                                        Expanded(
                                                            child: Column(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .min,
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .center,
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                              Text(
                                                                  _snapshot.name(
                                                                      _channel),
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style: const TextStyle(
                                                                      color: Colors
                                                                          .white,
                                                                      fontSize:
                                                                          20)),
                                                              Text(
                                                                  current ==
                                                                          null
                                                                      ? '暂无节目单'
                                                                      : '${liveTime(current.start)} ${current.title}',
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style: const TextStyle(
                                                                      color: Colors
                                                                          .white70)),
                                                              if (next != null)
                                                                Text(
                                                                    '接下来 ${liveTime(next.start)} ${next.title}',
                                                                    maxLines: 1,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                    style: const TextStyle(
                                                                        color: Colors
                                                                            .white70)),
                                                            ])),
                                                        Column(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .end,
                                                          children: [
                                                            Text(
                                                                _exo
                                                                    ? 'Exo'
                                                                    : 'MPV',
                                                                style: const TextStyle(
                                                                    color: Colors
                                                                        .white70)),
                                                            const SizedBox(
                                                                height: 4),
                                                            speedLabel(),
                                                          ],
                                                        ),
                                                        if (!isTelevision) ...[
                                                          const SizedBox(
                                                              width: 12),
                                                          LiveIconButton(
                                                            icon:
                                                                Icons.settings,
                                                            label: '播放设置',
                                                            onPressed:
                                                                _openSettings,
                                                          ),
                                                        ],
                                                      ]))))))),
                        if (_settings)
                          Material(
                            key: const ValueKey('live-settings-background'),
                            color:
                                const Color(0xFF202020).withValues(alpha: .7),
                            child: SafeArea(
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 360),
                                  child: Material(
                                    type: MaterialType.transparency,
                                    child: SingleChildScrollView(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(children: [
                                            const Expanded(child: Text('播放设置')),
                                            LiveIconButton(
                                              icon: Icons.close,
                                              label: '关闭设置',
                                              focusNode: _settingsFocus,
                                              onPressed: _closeOverlay,
                                            ),
                                          ]),
                                          Row(children: [
                                            const Expanded(child: Text('频道列表')),
                                            LiveIconButton(
                                                icon: Icons.list,
                                                label: '频道列表',
                                                onPressed: () =>
                                                    _openOverlay(guide: false)),
                                          ]),
                                          Row(children: [
                                            const Expanded(child: Text('节目单')),
                                            LiveIconButton(
                                                icon: Icons.calendar_view_day,
                                                label: '节目单',
                                                onPressed: () =>
                                                    _openOverlay(guide: true)),
                                          ]),
                                          Row(children: [
                                            const Expanded(child: Text('音轨')),
                                            LiveIconButton(
                                                icon: Icons.audiotrack,
                                                label: '音轨',
                                                onPressed: _audio),
                                          ]),
                                          if (!kIsWeb &&
                                              defaultTargetPlatform ==
                                                  TargetPlatform.android)
                                            Row(children: [
                                              Expanded(
                                                  child: Text(
                                                      '播放内核 · ${_exo ? 'Exo' : 'MPV'}')),
                                              LiveIconButton(
                                                  icon: Icons.swap_horiz,
                                                  label: '切换播放内核',
                                                  onPressed:
                                                      controller == null ||
                                                              _switching
                                                          ? null
                                                          : _switchEngine),
                                            ]),
                                          if (_channel.lines.length > 1)
                                            Row(children: [
                                              const Expanded(
                                                  child: Text('播放线路')),
                                              DropdownButton<int>(
                                                  value: controller?.line ?? 0,
                                                  dropdownColor: Colors.black,
                                                  items: [
                                                    for (var i = 0;
                                                        i <
                                                            _channel
                                                                .lines.length;
                                                        i++)
                                                      DropdownMenuItem(
                                                          value: i,
                                                          child: LiveSelectionLabel(
                                                              label:
                                                                  '线路 ${i + 1}',
                                                              selected: i ==
                                                                  (controller
                                                                          ?.line ??
                                                                      0),
                                                              enabled: controller !=
                                                                      null &&
                                                                  _foreground))
                                                  ],
                                                  onChanged:
                                                      controller == null ||
                                                              !_foreground
                                                          ? null
                                                          : (v) {
                                                              if (v != null) {
                                                                controller.select(
                                                                    _channel,
                                                                    preferredLine:
                                                                        v);
                                                              }
                                                            }),
                                            ]),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (_list || _guide)
                          SafeArea(
                              child: Align(
                                  alignment: _guide
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: SizedBox(
                                    width: fullWidthOverlay
                                        ? MediaQuery.sizeOf(context).width
                                        : (_list ? 560 : 440),
                                    child: Material(
                                        key: ValueKey(_list
                                            ? 'live-channels-background'
                                            : 'live-guide-background'),
                                        color: const Color(0xFF202020)
                                            .withValues(alpha: .7),
                                        child: Column(children: [
                                          if (!_list || !isTelevision)
                                            Row(children: [
                                              LiveIconButton(
                                                  icon: Icons.close,
                                                  label: '关闭',
                                                  focusNode: _overlayFocus,
                                                  autofocus: _guide,
                                                  onPressed: _closeOverlay),
                                              Expanded(
                                                  child: Text(
                                                      _guide ? '节目单' : '频道')),
                                              if (_guide || fullWidthOverlay)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.all(12),
                                                  child: speedLabel(),
                                                ),
                                            ]),
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
                                                                focusNode: i == 0
                                                                    ? _guideFirstFocus
                                                                    : null,
                                                                onPressed: () => showDialog<
                                                                        void>(
                                                                    context:
                                                                        context,
                                                                    builder:
                                                                        (c) =>
                                                                            AlertDialog(
                                                                              title: Text(p.title),
                                                                              content: SingleChildScrollView(child: Text(p.description.isEmpty ? '暂无节目简介' : p.description)),
                                                                              actions: [
                                                                                StarflowButton(label: '关闭', autofocus: true, onPressed: () => Navigator.pop(c))
                                                                              ],
                                                                            )),
                                                                child: ListTile(
                                                                    selectedColor:
                                                                        accent,
                                                                    selectedTileColor:
                                                                        accent.withValues(
                                                                            alpha:
                                                                                .09),
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
                                                  : LiveChannelPicker(
                                                      key: _channelPicker,
                                                      snapshot: _snapshot,
                                                      currentChannel: _channel,
                                                      nowNext:
                                                          nowNext ?? const {},
                                                      closeFocus: isTelevision
                                                          ? null
                                                          : _overlayFocus,
                                                      onSelected: _select)),
                                        ])),
                                  ))),
                        if (!_settings &&
                            !_guide &&
                            !showTopBar &&
                            (loading || _controls) &&
                            (!(_list || _guide) || !fullWidthOverlay))
                          SafeArea(
                            child: Align(
                              alignment: Alignment.topRight,
                              child: IgnorePointer(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: const Color(0xD9000000),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: speedLabel(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  )))),
    );
  }
}
