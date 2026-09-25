import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starflow/app/theme/app_colors.dart';
import 'package:starflow/app/theme/app_typography.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/features/playback/presentation/widgets/player_menu_style.dart';
import 'package:starflow/features/playback/application/playback_episode_browser.dart';
import 'package:starflow/features/playback/domain/playback_episode_queue.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';

String formatPlaybackEpisodePickerLabel(
    PlaybackEpisodeQueueEntry entry, int index) {
  final target = entry.target;
  final season = target.seasonNumber ?? 0;
  final episode = target.episodeNumber ?? index + 1;
  final prefix = season > 0
      ? 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}'
      : '第 $episode 集';
  return target.title.trim().isEmpty
      ? prefix
      : '$prefix · ${target.title.trim()}';
}

String playbackEpisodeTitle(PlaybackEpisodeQueueEntry entry, int index) {
  final title = entry.target.title.trim();
  final number = entry.target.episodeNumber ?? index + 1;
  if (title.isEmpty ||
      RegExp(r'^(第\s*0*'
              '$number'
              r'\s*集|0*'
              '$number'
              r'|[Ee][Pp]?\s*0*'
              '$number'
              r')$')
          .hasMatch(title)) {
    return '第 $number 集';
  }
  return title;
}

Future<PlaybackEpisodeSelection?> showPlaybackEpisodePickerDialog({
  required BuildContext context,
  required PlaybackEpisodeQueue queue,
  required bool isTelevision,
  PlaybackEpisodeBrowser? browser,
  Future<PlaybackMemorySnapshot> Function()? loadHistory,
}) async {
  if (queue.entries.isEmpty || !queue.hasCurrent) return null;
  final origin = FocusManager.instance.primaryFocus;
  final preferences = SharedPreferencesStore.reloading();
  var grid = false;
  try {
    grid = await preferences.getString('episode_picker_layout') == 'grid';
  } catch (_) {}
  if (!context.mounted) return null;
  final result = await showPlaybackMenuDialog<PlaybackEpisodeSelection>(
    context: context,
    animationStyle: AnimationStyle.noAnimation,
    barrierColor: Colors.black.withValues(alpha: 0.18),
    builder: (_) => _PlaybackEpisodePickerDialog(
      queue: queue,
      isTelevision: isTelevision,
      browser: browser,
      loadHistory: loadHistory,
      grid: grid,
      preferences: preferences,
    ),
  );
  if (origin?.context != null && origin!.canRequestFocus) origin.requestFocus();
  return result;
}

class _PlaybackEpisodePickerDialog extends StatefulWidget {
  const _PlaybackEpisodePickerDialog(
      {required this.queue,
      required this.isTelevision,
      required this.grid,
      required this.preferences,
      this.browser,
      this.loadHistory});
  final PlaybackEpisodeQueue queue;
  final bool isTelevision;
  final bool grid;
  final PreferencesStore preferences;
  final PlaybackEpisodeBrowser? browser;
  final Future<PlaybackMemorySnapshot> Function()? loadHistory;
  @override
  State<_PlaybackEpisodePickerDialog> createState() =>
      _PlaybackEpisodePickerDialogState();
}

class _PlaybackEpisodePickerDialogState
    extends State<_PlaybackEpisodePickerDialog> {
  late PlaybackEpisodeQueue _queue;
  final _nodes = <String, FocusNode>{};
  ScrollController? _scroll;
  List<PlaybackEpisodeSeason> _seasons = const [];
  PlaybackMemorySnapshot _history = const PlaybackMemorySnapshot();
  PlaybackEpisodeSeason? _season;
  PlaybackEpisodeSeason? _pendingSeason;
  final _headerFocus = FocusNode();
  final _gridFocus = FocusNode();
  final _seasonFocus = FocusNode(debugLabel: 'player-episode-picker-season');
  final _rangeFocus = FocusNode(debugLabel: 'player-episode-picker-range');
  final _focusSummary = ValueNotifier<int>(0);
  Color get _accent => AppActionColors.of(Theme.of(context)).primary;
  double get _rowExtent => 72;
  String? _error;
  bool _loading = false;
  bool _grid = false;
  int _page = 0;
  int _request = 0;
  int _focused = 0;
  bool _initialFocus = true;
  int _layoutVersion = 0;
  static const _pageSize = 30;

  String _key(int index) => '${_queue.entries[index].playbackItemKey}:$index';
  FocusNode _node(int index) => _nodes.putIfAbsent(
      _key(index), () => FocusNode(debugLabel: 'player-episode-picker-$index'));
  int get _start => _page * _pageSize;
  int get _end => math.min(_start + _pageSize, _queue.entries.length);
  bool _playing(int index) =>
      _queue.entries[index].playbackItemKey ==
      widget.queue.currentEntry!.playbackItemKey;

  @override
  void initState() {
    super.initState();
    _queue = widget.queue;
    _grid = widget.grid;
    _focused = _queue.currentIndex;
    _focusSummary.value = _focused;
    _page = _focused ~/ _pageSize;
    unawaited(_loadMetadata());
  }

  Future<void> _loadMetadata() async {
    if (widget.loadHistory != null) {
      unawaited(widget.loadHistory!().then((value) {
        if (mounted) setState(() => _history = value);
      }).catchError((Object _) {}));
    }
    try {
      final seasons = await widget.browser?.loadSeasons() ??
          const <PlaybackEpisodeSeason>[];
      if (mounted) setState(() => _seasons = seasons);
    } catch (_) {
      if (mounted) setState(() => _error = '季列表加载失败');
    }
  }

  Future<void> _loadSeason(PlaybackEpisodeSeason season) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _pendingSeason = season;
    });
    try {
      final queue =
          season.number == widget.queue.currentEntry!.target.seasonNumber
              ? widget.queue
              : await widget.browser!
                  .loadSeason(season)
                  .timeout(const Duration(seconds: 30));
      if (!mounted || request != _request) return;
      if (queue.entries.isEmpty) throw StateError('Empty season');
      setState(() {
        _queue = queue;
        _season = season;
        _pendingSeason = null;
        _focused = queue.hasCurrent ? queue.currentIndex : 0;
        _page = _focused ~/ _pageSize;
        _loading = false;
        _resetLayout();
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _error = '本季加载失败，请重试';
        });
      }
    }
  }

  void _resetLayout() {
    _focusSummary.value = _focused;
    final old = _scroll;
    _scroll = null;
    _layoutVersion++;
    _initialFocus = true;
    final version = _layoutVersion;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old?.dispose();
      if (mounted && version == _layoutVersion && widget.isTelevision) {
        _node(_focused).requestFocus();
      }
    });
  }

  void _setGrid(bool grid) {
    if (_loading) return;
    setState(() {
      _grid = grid;
      _resetLayout();
    });
    unawaited(widget.preferences
        .setString('episode_picker_layout', grid ? 'grid' : 'list')
        .catchError((Object _) {}));
  }

  double _rowAlignedOffset(int row, double viewportHeight, double maxOffset) {
    final centered = row * _rowExtent - viewportHeight / 2 + _rowExtent / 2;
    return ((centered / _rowExtent).round() * _rowExtent).clamp(0.0, maxOffset);
  }

  void _focus(int index) {
    if (!mounted || index < 0 || index >= _queue.entries.length) return;
    final row = (index - _start) ~/ (_grid ? 4 : 1);
    final scroll = _scroll;
    if (scroll != null && scroll.hasClients) {
      scroll.jumpTo(_rowAlignedOffset(row, scroll.position.viewportDimension,
          scroll.position.maxScrollExtent));
    }
    if (widget.isTelevision && _node(index).context != null) {
      _node(index).requestFocus();
    }
  }

  void _move(int index, {bool direct = false}) {
    if (index < 0 || index >= _queue.entries.length) return;
    final page = index ~/ _pageSize;
    _focused = index;
    if (direct || page != _page) {
      setState(() {
        _page = page;
        _resetLayout();
      });
    } else {
      _initialFocus = false;
      _focus(index);
    }
  }

  bool get _canChooseSeason => !_loading && _seasons.length > 1;

  void _focusAboveEpisodes() {
    (_canChooseSeason ? _seasonFocus : _headerFocus).requestFocus();
  }

  void _focusBelowHeader() {
    if (_canChooseSeason) {
      _seasonFocus.requestFocus();
    } else {
      _focus(_focused);
    }
  }

  Future<void> _chooseSeason() async {
    final season = await showPlaybackMenuDialog<PlaybackEpisodeSeason>(
        context: context,
        animationStyle: AnimationStyle.noAnimation,
        builder: (context) => SimpleDialog(
              title: const Text('选择季'),
              children: _seasons
                  .map((season) => TvDialogOption(
                        isTelevision: widget.isTelevision,
                        autofocus: season.number ==
                            (_season?.number ??
                                _queue.entries.first.target.seasonNumber),
                        onPressed: () => Navigator.pop(context, season),
                        child: Text(season.title),
                      ))
                  .toList(),
            ));
    if (mounted && season != null) await _loadSeason(season);
  }

  Future<void> _chooseRange() async {
    final page = await showPlaybackMenuDialog<int>(
        context: context,
        animationStyle: AnimationStyle.noAnimation,
        builder: (context) => SimpleDialog(
              title: const Text('选择集数范围'),
              children: List.generate(
                  (_queue.entries.length / _pageSize).ceil(), (page) {
                final start = page * _pageSize;
                final end =
                    math.min(start + _pageSize, _queue.entries.length) - 1;
                return TvDialogOption(
                    isTelevision: widget.isTelevision,
                    autofocus: page == _page,
                    onPressed: () => Navigator.pop(context, page),
                    child: Text(
                        '${_queue.entries[start].target.episodeNumber ?? start + 1}–${_queue.entries[end].target.episodeNumber ?? end + 1} 集'));
              }),
            ));
    if (mounted && page != null) _move(page * _pageSize, direct: true);
  }

  Widget _tool(IconData icon, String label, VoidCallback? action,
      {bool selected = false, FocusNode? focusNode}) {
    return Tooltip(
        message: label,
        child: Semantics(
          label: label,
          button: true,
          selected: selected,
          child: Focus(
              onKeyEvent: (_, event) {
                if (event is KeyUpEvent || _loading) {
                  return KeyEventResult.ignored;
                }
                if ((focusNode == _headerFocus || focusNode == _gridFocus) &&
                    event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  if (focusNode == _gridFocus &&
                      _queue.entries.length > _pageSize) {
                    _rangeFocus.requestFocus();
                  } else {
                    _focusBelowHeader();
                  }
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: GestureDetector(
                  onTap: widget.isTelevision ? action : null,
                  child: TvFocusableAction(
                    focusNode: focusNode,
                    onPressed: action,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                            color: selected ? AppColors.layerActive : null,
                            borderRadius: BorderRadius.circular(6)),
                        alignment: Alignment.center,
                        child: Icon(icon,
                            size: 22,
                            color: action == null
                                ? AppColors.fgDisabled
                                : AppColors.foreground)),
                  ))),
        ));
  }

  Widget _tile(int index) {
    final entry = _queue.entries[index];
    final playing = _playing(index);
    final history = _history.items[entry.playbackItemKey];
    final number = entry.target.episodeNumber ?? index + 1;
    final title = playbackEpisodeTitle(entry, index);
    final status = playing
        ? '正在播放'
        : history?.completed == true
            ? '已看完'
            : history?.hasProgress == true
                ? '已看 ${history!.position.inMinutes} 分钟'
                : '';
    final content = Container(
      decoration: BoxDecoration(
          color: playing ? _accent.withValues(alpha: .09) : Colors.transparent,
          borderRadius: BorderRadius.circular(6)),
      padding: EdgeInsets.symmetric(horizontal: _grid ? 8 : 12, vertical: 4),
      child: Stack(children: [
        if (_grid)
          Center(
              child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('$number',
                maxLines: 1,
                style: const TextStyle(fontSize: AppTextSizes.display)),
          ))
        else
          Row(children: [
            SizedBox(
                width: 42,
                child: Text(number.toString().padLeft(2, '0'),
                    style: const TextStyle(
                        fontSize: AppTextSizes.section,
                        color: AppColors.foregroundBody))),
            const SizedBox(width: 8),
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: AppTextSizes.title,
                          height: 1.2)),
                  if (status.isNotEmpty)
                    Text(status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: AppTextSizes.caption,
                            height: 1.2,
                            color:
                                playing ? _accent : AppColors.foregroundMuted)),
                ])),
            if (playing || history?.completed == true)
              Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                      playing ? Icons.play_arrow_rounded : Icons.check_rounded,
                      color: playing ? _accent : AppColors.foregroundMuted,
                      size: 18)),
          ]),
        if (_grid && (playing || history?.completed == true))
          Positioned(
              top: 0,
              right: 0,
              child: Icon(
                  playing ? Icons.play_arrow_rounded : Icons.check_rounded,
                  size: 14,
                  color: playing ? _accent : AppColors.foregroundMuted)),
        if (history != null && history.hasProgress && !history.completed)
          Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                  value: history.progress.clamp(0, 1),
                  minHeight: 2,
                  color: _accent,
                  backgroundColor: Colors.transparent)),
      ]),
    );
    return Padding(
        padding: const EdgeInsets.all(4),
        child: Focus(
          onKeyEvent: (_, event) {
            if (!widget.isTelevision || event is KeyUpEvent) {
              return KeyEventResult.ignored;
            }
            final key = event.logicalKey;
            if (_loading) return KeyEventResult.handled;
            if (_grid &&
                (key == LogicalKeyboardKey.arrowLeft ||
                    key == LogicalKeyboardKey.arrowRight)) {
              final column = (index - _start) % 4;
              if ((key == LogicalKeyboardKey.arrowLeft && column == 0) ||
                  (key == LogicalKeyboardKey.arrowRight &&
                      (column == 3 || index == _end - 1))) {
                return KeyEventResult.handled;
              }
            }
            final step = _grid ? 4 : 1;
            final delta = key == LogicalKeyboardKey.arrowDown
                ? step
                : key == LogicalKeyboardKey.arrowUp
                    ? -step
                    : _grid && key == LogicalKeyboardKey.arrowLeft
                        ? -1
                        : _grid && key == LogicalKeyboardKey.arrowRight
                            ? 1
                            : 0;
            if (delta == 0) {
              return KeyEventResult.ignored;
            }
            var next = index + delta;
            if (_grid && delta.abs() == 4) {
              final column = (index - _start) % 4;
              if (delta > 0 && next >= _end) {
                next = _end < _queue.entries.length
                    ? math.min(_end + column, _queue.entries.length - 1)
                    : ((index - _start) ~/ 4 < (_end - _start - 1) ~/ 4
                        ? _end - 1
                        : _queue.entries.length);
              } else if (delta < 0 && next < _start && _start > 0) {
                next = _start - 2 + math.min(column, 1);
              }
            }
            if (next < 0) {
              _focusAboveEpisodes();
            } else if (next < _queue.entries.length) {
              _move(next);
            }
            return KeyEventResult.handled;
          },
          child: GestureDetector(
              onTap: widget.isTelevision && !_loading
                  ? () => Navigator.pop(
                      context, PlaybackEpisodeSelection(_queue, index))
                  : null,
              child: TvFocusableAction(
                focusNode: _node(index),
                focusId: 'player:episode-picker:$index',
                autofocus: _initialFocus && index == _focused,
                borderRadius: BorderRadius.circular(6),
                onFocused: () {
                  _focused = index;
                  _focusSummary.value = index;
                },
                onPressed: _loading
                    ? null
                    : () => Navigator.pop(
                        context, PlaybackEpisodeSelection(_queue, index)),
                child: Semantics(
                    label: _grid
                        ? '$title${status.isEmpty ? '' : '，$status'}'
                        : null,
                    child: content),
              )),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final target = widget.queue.currentEntry!.target;
    final number =
        _season?.number ?? _queue.entries.first.target.seasonNumber ?? 0;
    return Dialog(
      alignment: Alignment.centerRight,
      insetPadding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(),
      child: SizedBox(
        key: const ValueKey<String>('player:episode-picker:panel'),
        width: size.width < 600
            ? size.width
            : (size.width * .30).clamp(320.0, 600.0),
        height: size.height,
        child: DecoratedBox(
            decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: Color(0x1FFFFFFF)))),
            child: SafeArea(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Column(children: [
                      Row(children: [
                        if (!widget.isTelevision)
                          _tool(Icons.arrow_back_rounded, '返回',
                              () => Navigator.pop(context)),
                        Expanded(
                            child: Text(
                                target.resolvedSeriesTitle.isEmpty
                                    ? '选择剧集'
                                    : target.resolvedSeriesTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: AppTextSizes.display,
                                    fontWeight: FontWeight.w600))),
                        _tool(Icons.view_list_rounded, '列表',
                            _loading ? null : () => _setGrid(false),
                            selected: !_grid, focusNode: _headerFocus),
                        _tool(Icons.grid_view_rounded, '网格',
                            _loading ? null : () => _setGrid(true),
                            selected: _grid, focusNode: _gridFocus),
                      ]),
                      SizedBox(
                          height: 36,
                          child: Row(children: [
                            Expanded(
                                child: TvDirectionalActionPanel(
                                    enabled: widget.isTelevision,
                                    onMoveUp: _headerFocus.requestFocus,
                                    onMoveDown: () => _focus(_focused),
                                    child: Tooltip(
                                      message: '选择季',
                                      child: TvFocusableAction(
                                        focusNode: _seasonFocus,
                                        onPressed: _canChooseSeason
                                            ? _chooseSeason
                                            : null,
                                        borderRadius: BorderRadius.circular(6),
                                        child: SizedBox(
                                            height: 36,
                                            child: Row(children: [
                                              Flexible(
                                                  child: Text(
                                                      !_grid && _loading
                                                          ? '正在加载剧集'
                                                          : !_grid &&
                                                                  _error != null
                                                              ? _error!
                                                              : '${number == 0 ? '特别篇' : '第 $number 季'} · 共 ${_queue.entries.length} 集',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                          fontSize:
                                                              AppTextSizes
                                                                  .title))),
                                              if (_seasons.length > 1)
                                                const Icon(
                                                    Icons.expand_more_rounded,
                                                    size: 20),
                                            ])),
                                      ),
                                    ))),
                            if (_queue.entries.length > _pageSize)
                              Flexible(
                                  child: TvDirectionalActionPanel(
                                      enabled: widget.isTelevision,
                                      onMoveUp: _gridFocus.requestFocus,
                                      onMoveDown: () => _focus(_focused),
                                      child: Tooltip(
                                          message: '选择集数范围',
                                          child: TvFocusableAction(
                                              focusNode: _rangeFocus,
                                              onPressed: _loading
                                                  ? null
                                                  : _chooseRange,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              child: SizedBox(
                                                  height: 36,
                                                  child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Flexible(
                                                            child: Text(
                                                                '${_queue.entries[_start].target.episodeNumber ?? _start + 1}–${_queue.entries[_end - 1].target.episodeNumber ?? _end} 集',
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: const TextStyle(
                                                                    fontSize:
                                                                        AppTextSizes
                                                                            .caption,
                                                                    color: AppColors
                                                                        .foregroundMuted))),
                                                        const Icon(
                                                            Icons
                                                                .expand_more_rounded,
                                                            size: 20),
                                                      ])))))),
                            if (!_grid && _error != null)
                              _tool(Icons.refresh_rounded, '重试', () {
                                if (_pendingSeason != null) {
                                  unawaited(_loadSeason(_pendingSeason!));
                                } else {
                                  setState(() => _error = null);
                                  unawaited(_loadMetadata());
                                }
                              }),
                          ])),
                      if (_grid)
                        SizedBox(
                            key: const ValueKey(
                                'player:episode-picker:information'),
                            height: 28,
                            child: _loading
                                ? const Center(child: Text('正在加载剧集'))
                                : _error != null
                                    ? Row(children: [
                                        Expanded(
                                            child: Text(_error!,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    color: AppColors
                                                        .foregroundMuted))),
                                        _tool(Icons.refresh_rounded, '重试', () {
                                          if (_pendingSeason != null) {
                                            unawaited(
                                                _loadSeason(_pendingSeason!));
                                          } else {
                                            setState(() => _error = null);
                                            unawaited(_loadMetadata());
                                          }
                                        }),
                                      ])
                                    : ValueListenableBuilder<int>(
                                        valueListenable: _focusSummary,
                                        builder: (context, index, _) {
                                          final current = index.clamp(
                                              0, _queue.entries.length - 1);
                                          final entry = _queue.entries[current];
                                          final history = _history
                                              .items[entry.playbackItemKey];
                                          final status = _playing(current)
                                              ? '正在播放'
                                              : history?.completed == true
                                                  ? '已看完'
                                                  : history?.hasProgress == true
                                                      ? '已看 ${history!.position.inMinutes} 分钟'
                                                      : '';
                                          return Align(
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                _grid
                                                    ? '${playbackEpisodeTitle(entry, current)}${status.isEmpty ? '' : ' · $status'}'
                                                    : '共 ${_queue.entries.length} 集',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize:
                                                        AppTextSizes.caption,
                                                    color: AppColors
                                                        .foregroundMuted),
                                              ));
                                        },
                                      )),
                      const SizedBox(height: 4),
                      Expanded(
                          child: LayoutBuilder(builder: (context, constraints) {
                        // Seed the offset before the first layout, not after painting.
                        final extent = _rowExtent;
                        final columns = _grid ? 4 : 1;
                        final row = (_focused - _start) ~/ columns;
                        final rawMaxOffset = math.max(
                            0.0,
                            ((_end - _start) / columns).ceil() * extent -
                                constraints.maxHeight);
                        // Keep the last row visible without leaving a partial row at the top.
                        final maxOffset =
                            (rawMaxOffset / extent).ceil() * extent;
                        _scroll ??= ScrollController(
                            initialScrollOffset: _rowAlignedOffset(
                                row, constraints.maxHeight, maxOffset));
                        // At most 30 lightweight cells are mounted, so D-pad neighbors exist.
                        return SingleChildScrollView(
                            key: ValueKey(_layoutVersion),
                            controller: _scroll,
                            padding: EdgeInsets.only(
                                bottom: maxOffset - rawMaxOffset),
                            child: _grid
                                ? Wrap(
                                    children: List.generate(
                                        _end - _start,
                                        (i) => SizedBox(
                                            width: constraints.maxWidth / 4,
                                            height: _rowExtent,
                                            child: _tile(_start + i))))
                                : Column(
                                    children: List.generate(
                                        _end - _start,
                                        (i) => SizedBox(
                                            height: _rowExtent,
                                            child: _tile(_start + i)))));
                      })),
                    ])))),
      ),
    );
  }

  @override
  void dispose() {
    _scroll?.dispose();
    _headerFocus.dispose();
    _gridFocus.dispose();
    _seasonFocus.dispose();
    _rangeFocus.dispose();
    _focusSummary.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }
}
