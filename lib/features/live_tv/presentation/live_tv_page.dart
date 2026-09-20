import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/navigation/page_activity_mixin.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';
import '../data/live_repository.dart';
import '../data/live_logo_provider.dart';
import '../domain/live_models.dart';
import 'live_player_page.dart';
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
  Timer? _minute;
  String _group = '';
  bool _favorites = false, _organize = false;
  @override
  void initState() {
    super.initState();
    _search.addListener(_changed);
    _minute = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && isPageActive) ref.invalidate(liveNowNextProvider);
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void onPageBecameActive() {
    unawaited(ref
        .read(liveRepositoryProvider)
        .refreshDue(canContinue: () => mounted && isPageActive)
        .catchError((Object _) {}));
  }

  @override
  void dispose() {
    _minute?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _play(LiveChannel channel, LiveSnapshot snapshot) async {
    await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) =>
                LivePlayerPage(initialChannel: channel, snapshot: snapshot)));
  }

  Future<void> _save(Future<void> action) async {
    try {
      await action;
    } catch (_) {
      if (mounted) liveMessage(context, '保存失败');
    }
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
    final tv = ref.watch(isTelevisionProvider).value ?? false;
    final nowNext = ref.watch(liveNowNextProvider).value ?? {};
    return TvPageFocusScope(
        isTelevision: tv,
        child: Scaffold(
          body: SafeArea(
              child: Padding(
            padding: appPageContentPadding(context),
            child: ref.watch(liveSnapshotProvider).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(
                    child: StarflowButton(
                        label: '重新读取直播数据',
                        onPressed: () => ref.invalidate(liveSnapshotProvider))),
                data: (s) {
                  final channels = s.visible(includeHidden: _organize);
                  final groups = channels
                      .map(s.group)
                      .where((g) => g.isNotEmpty)
                      .toSet()
                      .toList()
                    ..sort();
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
                          c.id == s.lastChannel && !s.preference(c).hidden)
                      .firstOrNull;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          if (widget.showBackButton)
                            LiveIconButton(
                                icon: Icons.arrow_back,
                                label: '返回',
                                onPressed: () =>
                                    Navigator.of(context).maybePop()),
                          Expanded(
                              child: Text('直播',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall)),
                          LiveIconButton(
                              icon: Icons.tune,
                              label: '直播订阅',
                              autofocus: true,
                              onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                      builder: (_) =>
                                          const LiveSourcesPage()))),
                          LiveIconButton(
                              icon:
                                  _organize ? Icons.done : Icons.edit_outlined,
                              label: _organize ? '完成整理' : '整理频道',
                              onPressed: () =>
                                  setState(() => _organize = !_organize)),
                        ]),
                        SettingsTextInputField(
                            controller: _search, labelText: '搜索频道'),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                            builder: (context, constraints) => Wrap(
                                    spacing: 12,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      SizedBox(
                                          width: constraints.maxWidth < 260
                                              ? constraints.maxWidth
                                              : 240,
                                          child: DropdownButton<String>(
                                              isExpanded: true,
                                              value: activeGroup,
                                              items: [
                                                const DropdownMenuItem(
                                                    value: '',
                                                    child: Text('全部分组')),
                                                for (final g in groups)
                                                  DropdownMenuItem(
                                                      value: g,
                                                      child: ConstrainedBox(
                                                          constraints:
                                                              const BoxConstraints(
                                                                  maxWidth:
                                                                      200),
                                                          child: Text(g,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis)))
                                              ],
                                              onChanged: (v) => setState(
                                                  () => _group = v ?? ''))),
                                      FilterChip(
                                          label: const Text('收藏'),
                                          selected: _favorites,
                                          onSelected: (v) =>
                                              setState(() => _favorites = v)),
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
                                            items: const [
                                              DropdownMenuItem(
                                                  value: 'mpv',
                                                  child: Text('MPV')),
                                              DropdownMenuItem(
                                                  value: 'exo',
                                                  child: Text('ExoPlayer'))
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
                            child: filtered.isEmpty
                                ? Center(
                                    child: Text(s.sources.isEmpty
                                        ? '尚未添加直播订阅'
                                        : '没有符合条件的频道'))
                                : ListView.builder(
                                    itemCount: filtered.length,
                                    itemBuilder: (ctx, i) {
                                      final c = filtered[i],
                                          p = s.preference(c);
                                      final schedule = nowNext[
                                              '${c.sourceId}|${s.epgId(c)}'] ??
                                          [];
                                      final current = schedule
                                          .where(
                                              (p) => p.contains(DateTime.now()))
                                          .firstOrNull;
                                      final next = schedule
                                          .where((p) =>
                                              p.start.isAfter(DateTime.now()))
                                          .firstOrNull;
                                      return Column(children: [
                                        Row(children: [
                                          Expanded(
                                              child: TvFocusableAction(
                                                  focusId: 'live:${c.id}',
                                                  onPressed: () => _play(c, s),
                                                  child: Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          vertical: 12,
                                                          horizontal: 8),
                                                      child: Row(children: [
                                                        LiveLogo(
                                                            url: s.logo(c)),
                                                        const SizedBox(
                                                            width: 12),
                                                        Expanded(
                                                            child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                              Text(s.name(c),
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style: Theme.of(
                                                                          context)
                                                                      .textTheme
                                                                      .titleMedium),
                                                              Text(
                                                                  '${s.group(c)}${p.hidden ? " · 已隐藏" : ""} · ${c.lines.length} 条线路',
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis),
                                                              if (current !=
                                                                  null)
                                                                Text(
                                                                    current
                                                                        .title,
                                                                    maxLines: 1,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis),
                                                              if (next != null)
                                                                Text(
                                                                    '接下来 ${liveTime(next.start)} ${next.title}',
                                                                    maxLines: 1,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis),
                                                            ])),
                                                      ])))),
                                          LiveIconButton(
                                              icon: p.favorite
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              label:
                                                  p.favorite ? '取消收藏' : '收藏频道',
                                              onPressed: () => _save(ref
                                                  .read(liveRepositoryProvider)
                                                  .preference(c.id,
                                                      {'favorite': !p.favorite}))),
                                        ]),
                                        if (_organize)
                                          Wrap(children: [
                                            LiveIconButton(
                                                icon: Icons.edit_outlined,
                                                label: '名称、台标与节目单映射',
                                                onPressed: () => _edit(c, s)),
                                            LiveIconButton(
                                                icon: p.hidden
                                                    ? Icons.visibility
                                                    : Icons
                                                        .visibility_off_outlined,
                                                label:
                                                    p.hidden ? '显示频道' : '隐藏频道',
                                                onPressed: () => _save(ref
                                                    .read(
                                                        liveRepositoryProvider)
                                                    .preference(c.id,
                                                        {'hidden': !p.hidden}))),
                                            LiveIconButton(
                                                icon: Icons.arrow_upward,
                                                label: '上移',
                                                onPressed: () => _save(ref
                                                    .read(
                                                        liveRepositoryProvider)
                                                    .move(c.id, -1))),
                                            LiveIconButton(
                                                icon: Icons.arrow_downward,
                                                label: '下移',
                                                onPressed: () => _save(ref
                                                    .read(
                                                        liveRepositoryProvider)
                                                    .move(c.id, 1))),
                                          ]),
                                      ]);
                                    })),
                      ]);
                }),
          )),
        ));
  }
}

class LiveLogo extends ConsumerWidget {
  const LiveLogo({super.key, required this.url});
  final String url;
  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
      width: 48,
      height: 40,
      child: url.startsWith('https://') || url.startsWith('http://')
          ? ref.watch(liveLogoProvider(url)).when(
              data: (bytes) => Image.memory(bytes,
                  fit: BoxFit.contain,
                  cacheWidth: 144,
                  cacheHeight: 120,
                  errorBuilder: (_, __, ___) => const Icon(Icons.live_tv)),
              loading: () => const Icon(Icons.live_tv),
              error: (_, __) => const Icon(Icons.live_tv))
          : const Icon(Icons.live_tv));
}
