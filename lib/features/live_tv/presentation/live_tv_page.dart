import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/app/theme/app_colors.dart';
import 'package:starflow/core/navigation/page_activity_mixin.dart';
import 'package:starflow/core/network/network_proxy_runtime.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';
import '../application/live_channel_probe_controller.dart';
import '../data/live_channel_probe.dart';
import '../data/live_probe_network.dart';
import '../data/live_repository.dart';
import '../domain/live_models.dart';
import 'live_logo.dart';
import 'live_player_page.dart';
import 'live_probe_label.dart';
import 'live_probe_viewport.dart';
import 'live_sources_page.dart';
import 'live_widgets.dart';

class LiveTvPage extends ConsumerStatefulWidget {
  const LiveTvPage({super.key, this.showBackButton = false});
  final bool showBackButton;
  @override
  ConsumerState<LiveTvPage> createState() => _LiveTvPageState();
}

class _LiveTvPageState extends ConsumerState<LiveTvPage>
    with PageActivityMixin<LiveTvPage> {
  final _search = TextEditingController();
  late final LiveChannelProbeController _probes;
  Timer? _minute;
  String _group = '';
  bool _favorites = false, _organize = false;
  bool _openingPlayer = false;
  bool _probesPaused = false;
  Future<void>? _sourceRefresh;
  bool _groupMenuOpen = false;
  List<LiveChannel> _visibleChannels = [];
  StreamSubscription<bool>? _networkWatch;
  bool _networkAvailable = true;
  bool _networkUncertain = false;
  late final AppLifecycleListener _probeLifecycle;
  @override
  void initState() {
    super.initState();
    _probes = LiveChannelProbeController(ref.read(liveChannelProbeProvider));
    _probeLifecycle = AppLifecycleListener(onStateChange: (state) {
      if (state != AppLifecycleState.resumed) _networkUncertain = true;
    });
    networkProxyRuntime.addListener(_proxyChanged);
    _search.addListener(_changed);
    _minute = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && isPageActive) ref.invalidate(liveNowNextProvider);
    });
  }

  void _proxyChanged() {
    _probes.invalidateNetwork(available: _networkAvailable);
  }

  void _watchNetwork() {
    if (kIsWeb || _networkWatch != null) return;
    _networkWatch = ref.read(liveProbeNetworkProvider).listen((available) {
      if (!mounted) return;
      _networkAvailable = available;
      _probes.invalidateNetwork(available: available);
    }, onError: (Object _) {
      // Interface notifications are optional; they never gate HTTP detection.
      _networkUncertain = true;
    });
  }

  void _changed() {
    _clearProbeViewport();
    if (mounted) setState(() {});
  }

  void _clearProbeViewport() {
    _visibleChannels = [];
    _probes.updateVisible(const [], const LiveSnapshot());
  }

  void _selectGroup(String group) {
    if (_group == group) return;
    _clearProbeViewport();
    setState(() => _group = group);
  }

  @override
  void onPageBecameInactive() {
    _clearProbeViewport();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      _networkUncertain = true;
    }
    // The group chooser covers this route without leaving the channel list.
    if (_groupMenuOpen &&
        TickerMode.of(context) &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed)) {
      return;
    }
    _groupMenuOpen = false;
    _probesPaused = false;
    unawaited(_probes.stop());
  }

  @override
  void onPageBecameActive() {
    _groupMenuOpen = false;
    // Passive interface events invalidate cached results even while away.
    if (_networkUncertain) {
      _networkUncertain = false;
      _probes.invalidateNetwork(available: _networkAvailable);
    }
    _watchNetwork();
    ref.invalidate(liveNowNextProvider);
    final refresh = ref
        .read(liveRepositoryProvider)
        .refreshDue(canContinue: () => mounted && isPageActive)
        .catchError((Object _) {});
    _sourceRefresh = refresh;
    unawaited(refresh.whenComplete(() {
      if (mounted && identical(_sourceRefresh, refresh)) {
        setState(() => _sourceRefresh = null);
      }
    }));
  }

  void _startProbes(List<LiveChannel> channels, LiveSnapshot snapshot) {
    if (!isPageVisible || _openingPlayer) return;
    _probesPaused = false;
    _probes.start(channels, snapshot);
  }

  void _scheduleAutomaticProbes(
      List<LiveChannel> channels, LiveSnapshot snapshot) {
    if (kIsWeb ||
        _probesPaused ||
        _probes.running ||
        _sourceRefresh != null ||
        !isPageVisible ||
        !channels.any((c) =>
            !snapshot.preference(c).hidden &&
            !snapshot.groupHidden(snapshot.group(c)))) {
      return;
    }
    // Viewport callbacks run after layout, with the current visible rows.
    if (identical(ref.read(liveSnapshotProvider).asData?.value, snapshot)) {
      _startProbes(channels, snapshot);
    }
  }

  @override
  void dispose() {
    _minute?.cancel();
    _probeLifecycle.dispose();
    networkProxyRuntime.removeListener(_proxyChanged);
    unawaited(_networkWatch?.cancel());
    _probes.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _play(LiveChannel channel, LiveSnapshot snapshot) async {
    if (_openingPlayer) return;
    _openingPlayer = true;
    try {
      await _probes.stop();
      if (!mounted || !isPageVisible) return;
      appLogInfo('live.playback', 'Live player page requested', fields: {
        'channelId': channel.id,
        'lineCount': channel.lines.length,
        'preferredEngine': snapshot.engine,
        'platform': defaultTargetPlatform.name,
      });
      await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) =>
                  LivePlayerPage(initialChannel: channel, snapshot: snapshot)));
    } finally {
      _openingPlayer = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _save(Future<void> action) async {
    try {
      await action;
    } catch (_) {
      if (mounted) liveMessage(context, '保存失败');
    }
  }

  void _setGroupHidden(String group, LiveSnapshot snapshot) {
    final hidden = snapshot.groupPreference(group).hidden;
    _save(ref.read(liveRepositoryProvider).setGroupHidden(group, !hidden));
  }

  void _moveGroup(String group, int delta) {
    _save(ref.read(liveRepositoryProvider).moveGroup(group, delta));
  }

  Widget _groupLabel(String group, LiveSnapshot snapshot,
      {bool selected = false}) {
    final hidden = snapshot.groupPreference(group).hidden;
    return Tooltip(
        message: group,
        child: LiveSelectionLabel(
            label: hidden ? '$group · 已隐藏' : group, selected: selected));
  }

  Widget _groupActions(String group, LiveSnapshot snapshot) {
    final hidden = snapshot.groupPreference(group).hidden;
    return Wrap(children: [
      LiveIconButton(
          icon: hidden ? Icons.visibility : Icons.visibility_off_outlined,
          label: hidden ? '显示分组' : '隐藏分组',
          onPressed: () => _setGroupHidden(group, snapshot)),
      LiveIconButton(
          icon: Icons.arrow_upward,
          label: '分组上移',
          onPressed: () => _moveGroup(group, -1)),
      LiveIconButton(
          icon: Icons.arrow_downward,
          label: '分组下移',
          onPressed: () => _moveGroup(group, 1)),
    ]);
  }

  Widget _organizeGroupTile(String group, LiveSnapshot snapshot) {
    return SizedBox(
        width: 184,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: 40, child: _groupLabel(group, snapshot)),
          _groupActions(group, snapshot),
        ]));
  }

  Future<void> _edit(LiveChannel c, LiveSnapshot s) async {
    final p = s.preference(c);
    final name = TextEditingController(text: s.name(c)),
        group = TextEditingController(text: s.group(c));
    final logo = TextEditingController(text: s.logo(c)),
        epg = TextEditingController(text: s.epgId(c));
    try {
      final result = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('频道映射'),
                  content: SizedBox(
                      width: 440,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        SettingsTextInputField(
                            controller: name,
                            labelText: '频道名称',
                            autofocus: true),
                        SettingsTextInputField(
                            controller: group, labelText: '分组'),
                        SettingsTextInputField(
                            controller: logo, labelText: '台标 URL'),
                        SettingsTextInputField(
                            controller: epg, labelText: 'XMLTV 频道 ID'),
                      ]))),
                  actions: [
                    StarflowButton(
                        label: '取消',
                        onPressed: () => Navigator.pop(ctx, false)),
                    StarflowButton(
                        label: '保存', onPressed: () => Navigator.pop(ctx, true)),
                  ]));
      if (result == true && mounted) {
        await _save(ref.read(liveRepositoryProvider).preference(c.id, {
          ...p.toJson(),
          'name': name.text.trim(),
          'group': group.text.trim(),
          'logo': logo.text.trim(),
          'epgId': epg.text.trim()
        }));
      }
    } finally {
      name.dispose();
      group.dispose();
      logo.dispose();
      epg.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(liveSnapshotProvider, (previous, next) {
      if (!identical(previous?.value, next.value)) {
        _probes.updateSnapshot(next.value ?? const LiveSnapshot());
      }
    });
    final tv = ref.watch(isTelevisionProvider).value ?? false;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final nowNext = ref.watch(liveNowNextProvider).value ?? {};
    return TvPageFocusScope(
        isTelevision: tv,
        child: Scaffold(
          body: SafeArea(
              child: Padding(
            padding: appPageContentPadding(context, includeTopSafeArea: false),
            child: ref.watch(liveSnapshotProvider).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(
                    child: StarflowButton(
                        label: '重新读取直播数据',
                        onPressed: () => ref.invalidate(liveSnapshotProvider))),
                data: (s) {
                  final now = DateTime.now();
                  final channels = s.visible(includeHidden: _organize);
                  final groups = s.groups(includeHidden: _organize);
                  final activeGroup = groups.contains(_group) ? _group : '';
                  final query = _search.text.trim().toLowerCase();
                  final filtered = channels
                      .where((c) =>
                          (activeGroup.isEmpty || s.group(c) == activeGroup) &&
                          (!_favorites || s.preference(c).favorite) &&
                          s.name(c).toLowerCase().contains(query))
                      .toList();
                  final last = channels
                      .where((c) =>
                          c.id == s.lastChannel &&
                          !s.preference(c).hidden &&
                          !s.groupHidden(s.group(c)))
                      .firstOrNull;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                            height: 56,
                            child: Row(children: [
                              if (widget.showBackButton)
                                LiveIconButton(
                                    icon: Icons.arrow_back,
                                    label: '返回',
                                    onPressed: () =>
                                        Navigator.of(context).maybePop()),
                              Text('直播',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: SettingsTextInputField(
                                      controller: _search, labelText: '搜索频道')),
                            ])),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                            builder: (context, constraints) => Wrap(
                                    spacing: 12,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      if (!landscape)
                                        SizedBox(
                                            width: constraints.maxWidth < 260
                                                ? constraints.maxWidth
                                                : 240,
                                            child: DropdownButton<String>(
                                                key: const ValueKey(
                                                    'live-home-group-dropdown'),
                                                isExpanded: true,
                                                value: activeGroup,
                                                onTap: () =>
                                                    _groupMenuOpen = true,
                                                items: [
                                                  DropdownMenuItem(
                                                      value: '',
                                                      child: LiveSelectionLabel(
                                                          label: '全部分组',
                                                          selected: activeGroup
                                                              .isEmpty)),
                                                  for (final g in groups)
                                                    DropdownMenuItem(
                                                        value: g,
                                                        child: ConstrainedBox(
                                                            constraints:
                                                                const BoxConstraints(
                                                                    maxWidth:
                                                                        200),
                                                            child: LiveSelectionLabel(
                                                                label: g,
                                                                selected:
                                                                    activeGroup ==
                                                                        g)))
                                                ],
                                                onChanged: (v) =>
                                                    _selectGroup(v ?? ''))),
                                      if (!landscape &&
                                          _organize &&
                                          groups.isNotEmpty)
                                        SizedBox(
                                            height: 88,
                                            width: constraints.maxWidth,
                                            child: ListView.separated(
                                                key: const ValueKey(
                                                    'live-home-organize-groups'),
                                                scrollDirection:
                                                    Axis.horizontal,
                                                itemCount: groups.length,
                                                separatorBuilder: (_, __) =>
                                                    const SizedBox(width: 8),
                                                itemBuilder: (_, i) =>
                                                    _organizeGroupTile(
                                                        groups[i], s))),
                                      Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            FilterChip(
                                                label: const Text('收藏'),
                                                selected: _favorites,
                                                onSelected: (v) {
                                                  _clearProbeViewport();
                                                  setState(
                                                      () => _favorites = v);
                                                }),
                                            const SizedBox(width: 12),
                                            if (!kIsWeb)
                                              ListenableBuilder(
                                                  listenable: _probes,
                                                  builder: (_, __) =>
                                                      LiveIconButton(
                                                          icon: _probes.running
                                                              ? Icons.stop
                                                              : Icons.speed,
                                                          label: _probes.running
                                                              ? '停止检测 ${_probes.completed}/${_probes.total}'
                                                              : '检测可见频道',
                                                          onPressed: _probes
                                                                  .running
                                                              ? () {
                                                                  _probesPaused =
                                                                      true;
                                                                  unawaited(_probes
                                                                      .stop());
                                                                }
                                                              : filtered.isEmpty
                                                                  ? null
                                                                  : () => _startProbes(
                                                                      _visibleChannels,
                                                                      s))),
                                            LiveIconButton(
                                                icon: Icons.tune,
                                                label: '直播订阅',
                                                autofocus: true,
                                                onPressed: () => Navigator.of(
                                                        context)
                                                    .push(MaterialPageRoute<
                                                            void>(
                                                        builder: (_) =>
                                                            const LiveSourcesPage()))),
                                            LiveIconButton(
                                                icon: _organize
                                                    ? Icons.done
                                                    : Icons.edit_outlined,
                                                label:
                                                    _organize ? '完成整理' : '整理频道',
                                                onPressed: () {
                                                  _clearProbeViewport();
                                                  setState(() =>
                                                      _organize = !_organize);
                                                }),
                                          ]),
                                      if (last != null)
                                        TextButton.icon(
                                            icon: const Icon(Icons.history),
                                            label: Text(s.name(last),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                            onPressed: () => _play(last, s)),
                                      if (!kIsWeb &&
                                          defaultTargetPlatform ==
                                              TargetPlatform.android)
                                        DropdownButton<String>(
                                            value: s.engine,
                                            items: [
                                              DropdownMenuItem(
                                                  value: 'mpv',
                                                  child: LiveSelectionLabel(
                                                      label: 'MPV',
                                                      selected:
                                                          s.engine == 'mpv')),
                                              DropdownMenuItem(
                                                  value: 'exo',
                                                  child: LiveSelectionLabel(
                                                      label: 'ExoPlayer',
                                                      selected:
                                                          s.engine == 'exo'))
                                            ],
                                            onChanged: (v) {
                                              if (v != null) {
                                                _save(ref
                                                    .read(
                                                        liveRepositoryProvider)
                                                    .setEngine(v));
                                              }
                                            }),
                                    ])),
                        const Divider(),
                        Expanded(
                            child: LayoutBuilder(
                                builder:
                                    (context, constraints) => Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              if (landscape) ...[
                                                SizedBox(
                                                    width: (constraints
                                                                .maxWidth *
                                                            .24)
                                                        .clamp(152.0, 240.0),
                                                    child: ListView(
                                                        key: const PageStorageKey(
                                                            'live-home-groups'),
                                                        primary: false,
                                                        padding:
                                                            EdgeInsets.zero,
                                                        children: [
                                                          for (final group in [
                                                            '',
                                                            ...groups
                                                          ])
                                                            Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .stretch,
                                                                children: [
                                                                  TvFocusableAction(
                                                                      key: ValueKey(
                                                                          'live-home-group:$group'),
                                                                      focusId:
                                                                          'live-home-group:$group',
                                                                      onPressed: () =>
                                                                          _selectGroup(
                                                                              group),
                                                                      child: ColoredBox(
                                                                          color: group == activeGroup
                                                                              ? AppActionColors.of(Theme.of(context)).primary.withValues(alpha: .09)
                                                                              : Colors.transparent,
                                                                          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16), child: _groupLabel(group.isEmpty ? '全部分组' : group, s, selected: group == activeGroup)))),
                                                                  if (_organize &&
                                                                      group
                                                                          .isNotEmpty)
                                                                    _groupActions(
                                                                        group,
                                                                        s),
                                                                ]),
                                                        ])),
                                                const VerticalDivider(
                                                    width: 17),
                                              ],
                                              Expanded(
                                                  child: LiveProbeViewport(
                                                      onChanged: (visible) {
                                                        if (!isPageVisible ||
                                                            _openingPlayer) {
                                                          return;
                                                        }
                                                        _visibleChannels =
                                                            visible;
                                                        _probes.updateVisible(
                                                            visible, s);
                                                        _scheduleAutomaticProbes(
                                                            visible, s);
                                                      },
                                                      child: filtered.isEmpty
                                                          ? Center(
                                                              child: Text(s
                                                                      .sources
                                                                      .isEmpty
                                                                  ? '尚未添加直播订阅'
                                                                  : '没有符合条件的频道'))
                                                          : ListView.builder(
                                                              key: const PageStorageKey(
                                                                  'live-home-channels'),
                                                              itemCount:
                                                                  filtered
                                                                      .length,
                                                              itemBuilder:
                                                                  (ctx, i) {
                                                                final c =
                                                                        filtered[
                                                                            i],
                                                                    p = s
                                                                        .preference(
                                                                            c);
                                                                final schedule =
                                                                    nowNext['${c.sourceId}|${s.epgId(c)}'] ??
                                                                        [];
                                                                final current = schedule
                                                                    .where((p) =>
                                                                        p.contains(
                                                                            now))
                                                                    .firstOrNull;
                                                                final next = schedule
                                                                    .where((p) => p
                                                                        .start
                                                                        .isAfter(
                                                                            now))
                                                                    .firstOrNull;
                                                                return LiveProbeViewportItem(
                                                                    key: ValueKey(
                                                                        c.id),
                                                                    channel: c,
                                                                    child: Column(
                                                                        children: [
                                                                          Row(children: [
                                                                            Expanded(
                                                                                child: TvFocusableAction(
                                                                                    focusId: 'live:${c.id}',
                                                                                    onFocused: tv ? () => _probes.prioritize(c.id) : null,
                                                                                    onPressed: () => _play(c, s),
                                                                                    child: Padding(
                                                                                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                                                                        child: Row(children: [
                                                                                          LiveLogo(url: s.logo(c)),
                                                                                          const SizedBox(width: 12),
                                                                                          Expanded(
                                                                                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                                                            Row(children: [
                                                                                              Flexible(child: Text(s.name(c), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium)),
                                                                                              if (!kIsWeb) ...[
                                                                                                const SizedBox(width: 6),
                                                                                                ListenableBuilder(listenable: _probes, builder: (_, __) => LiveProbeLabel(key: ValueKey('live-probe:${c.id}'), entry: _probes.entry(c, p.line))),
                                                                                              ],
                                                                                            ]),
                                                                                            Text('${s.group(c)}${p.hidden ? " · 已隐藏" : ""} · ${c.lines.length} 条线路', maxLines: 1, overflow: TextOverflow.ellipsis),
                                                                                            LiveCurrentProgramme(programme: current),
                                                                                            if (next != null) Text('接下来 ${liveTime(next.start)} ${next.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
                                                                                          ])),
                                                                                        ])))),
                                                                            LiveIconButton(
                                                                                selected: p.favorite,
                                                                                icon: p.favorite ? Icons.star : Icons.star_border,
                                                                                label: p.favorite ? '取消收藏' : '收藏频道',
                                                                                onPressed: () => _save(ref.read(liveRepositoryProvider).preference(c.id, {'favorite': !p.favorite}))),
                                                                          ]),
                                                                          if (_organize)
                                                                            Wrap(children: [
                                                                              LiveIconButton(icon: Icons.edit_outlined, label: '名称、台标与节目单映射', onPressed: () => _edit(c, s)),
                                                                              LiveIconButton(icon: p.hidden ? Icons.visibility : Icons.visibility_off_outlined, label: p.hidden ? '显示频道' : '隐藏频道', onPressed: () => _save(ref.read(liveRepositoryProvider).preference(c.id, {'hidden': !p.hidden}))),
                                                                              LiveIconButton(icon: Icons.arrow_upward, label: '上移', onPressed: () => _save(ref.read(liveRepositoryProvider).move(c.id, -1))),
                                                                              LiveIconButton(icon: Icons.arrow_downward, label: '下移', onPressed: () => _save(ref.read(liveRepositoryProvider).move(c.id, 1))),
                                                                            ]),
                                                                        ]));
                                                              }))),
                                            ]))),
                      ]);
                }),
          )),
        ));
  }
}
