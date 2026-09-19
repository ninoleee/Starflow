import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starflow/app/theme/app_colors.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
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
  final result = await showDialog<PlaybackEpisodeSelection>(
    context: context,
    animationStyle: AnimationStyle.noAnimation,
    barrierColor: Colors.black.withValues(alpha: 0.18),
    builder: (_) => _PlaybackEpisodePickerDialog(
      queue: queue,
      isTelevision: isTelevision,
      browser: browser,
      loadHistory: loadHistory,
    ),
  );
  if (origin?.context != null && origin!.canRequestFocus) origin.requestFocus();
  return result;
}

class _PlaybackEpisodePickerDialog extends StatefulWidget {
  const _PlaybackEpisodePickerDialog(
      {required this.queue,
      required this.isTelevision,
      this.browser,
      this.loadHistory});
  final PlaybackEpisodeQueue queue;
  final bool isTelevision;
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
  final _scroll = ScrollController();
  List<PlaybackEpisodeSeason> _seasons = const [];
  PlaybackMemorySnapshot _history = const PlaybackMemorySnapshot();
  PlaybackEpisodeSeason? _season;
  String? _error;
  bool _loading = false;
  bool _grid = false;
  int _page = 0;
  int _request = 0;
  int _focused = 0;
  bool _initialFocus = true;
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
    _focused = _queue.currentIndex;
    _page = _focused ~/ _pageSize;
    unawaited(_loadMetadata());
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus(_focused));
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
      _season = season;
    });
    try {
      final queue =
          season.number == widget.queue.currentEntry!.target.seasonNumber
              ? widget.queue
              : await widget.browser!
                  .loadSeason(season)
                  .timeout(const Duration(seconds: 30));
      if (!mounted || request != _request) return;
      setState(() {
        _queue = queue;
        _focused = queue.hasCurrent ? queue.currentIndex : 0;
        _page = _focused ~/ _pageSize;
        _loading = false;
        _initialFocus = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus(_focused));
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _error = '本季加载失败，请重试';
        });
      }
    }
  }

  void _focus(int index) {
    if (!mounted || index < 0 || index >= _queue.entries.length) return;
    final row = (index - _start) ~/ (_grid ? 4 : 1);
    if (_scroll.hasClients) {
      final extent = _grid ? 86.0 : 80.0;
      _scroll.jumpTo(
          (row * extent - _scroll.position.viewportDimension / 2 + extent / 2)
              .clamp(0.0, _scroll.position.maxScrollExtent));
    }
    if (widget.isTelevision && _node(index).context != null) {
      _node(index).requestFocus();
    }
  }

  void _move(int index) {
    if (index < 0 || index >= _queue.entries.length) return;
    setState(() {
      _focused = index;
      _page = index ~/ _pageSize;
      _initialFocus = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus(index));
  }

  Future<void> _chooseSeason() async {
    final season = await showDialog<PlaybackEpisodeSeason>(
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
    final page = await showDialog<int>(
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
    if (mounted && page != null) _move(page * _pageSize);
  }

  Widget _tool(IconData icon, String label, VoidCallback? action,
      {bool selected = false}) {
    return Tooltip(
        message: label,
        child: Semantics(
          label: label,
          button: true,
          selected: selected,
          child: GestureDetector(
              onTap: widget.isTelevision ? action : null,
              child: TvFocusableAction(
                onPressed: action,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                    width: 44,
                    height: 44,
                    color: selected ? AppColors.layerActive : null,
                    alignment: Alignment.center,
                    child: Icon(icon,
                        size: 22,
                        color: action == null
                            ? AppColors.fgDisabled
                            : AppColors.foreground)),
              )),
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
          color: playing ? AppColors.layerActive : Colors.transparent,
          borderRadius: BorderRadius.circular(6)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Stack(children: [
        if (_grid)
          Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$number', style: const TextStyle(fontSize: 22)),
            if (status.isNotEmpty)
              Text(status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.foregroundBody)),
          ]))
        else
          Row(children: [
            SizedBox(
                width: 42,
                child: Text(number.toString().padLeft(2, '0'),
                    style: const TextStyle(
                        fontSize: 20, color: AppColors.foregroundBody))),
            const SizedBox(width: 8),
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15)),
                  if (status.isNotEmpty)
                    Text(status,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.foregroundBody)),
                ])),
            if (playing || history?.completed == true)
              Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                      playing ? Icons.play_arrow_rounded : Icons.check_rounded,
                      size: 18)),
          ]),
        if (history != null && history.hasProgress && !history.completed)
          Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                  value: history.progress.clamp(0, 1),
                  minHeight: 2,
                  color: AppActionColors.of(Theme.of(context)).primary,
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
            if (delta == 0 ||
                index + delta < 0 ||
                index + delta >= _queue.entries.length) {
              return KeyEventResult.ignored;
            }
            _move(index + delta);
            return KeyEventResult.handled;
          },
          child: GestureDetector(
              onTap: widget.isTelevision
                  ? () => Navigator.pop(
                      context, PlaybackEpisodeSelection(_queue, index))
                  : null,
              child: TvFocusableAction(
                focusNode: _node(index),
                focusId: 'player:episode-picker:$index',
                autofocus: _initialFocus && index == widget.queue.currentIndex,
                borderRadius: BorderRadius.circular(6),
                onFocused: () {
                  _focused = index;
                },
                onPressed: () => Navigator.pop(
                    context, PlaybackEpisodeSelection(_queue, index)),
                child: content,
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
      backgroundColor: AppColors.neutral3,
      child: SizedBox(
        key: const ValueKey<String>('player:episode-picker:panel'),
        width: size.width < 600
            ? size.width
            : (size.width * .30).clamp(320.0, 600.0),
        height: size.height,
        child: SafeArea(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                        child: Text(
                            target.resolvedSeriesTitle.isEmpty
                                ? '选择剧集'
                                : target.resolvedSeriesTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w600))),
                    _tool(Icons.close_rounded, '关闭',
                        () => Navigator.pop(context)),
                  ]),
                  Row(children: [
                    Expanded(
                        child: Text(
                            '${number == 0 ? '特别篇' : '第 $number 季'} · 共 ${_queue.entries.length} 集',
                            style: const TextStyle(
                                color: AppColors.foregroundMuted))),
                    if (_seasons.length > 1)
                      _tool(Icons.expand_more_rounded, '选择季',
                          _loading ? null : _chooseSeason),
                    _tool(Icons.view_list_rounded, '列表', () {
                      setState(() {
                        _grid = false;
                      });
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => _focus(_focused));
                    }, selected: !_grid),
                    _tool(Icons.grid_view_rounded, '网格', () {
                      setState(() {
                        _grid = true;
                      });
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => _focus(_focused));
                    }, selected: _grid),
                  ]),
                  if (_error != null)
                    Row(children: [
                      Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: AppColors.foregroundMuted))),
                      _tool(Icons.refresh_rounded, '重试', () {
                        if (_season != null) {
                          unawaited(_loadSeason(_season!));
                        } else {
                          setState(() => _error = null);
                          unawaited(_loadMetadata());
                        }
                      }),
                    ]),
                  const SizedBox(height: 8),
                  Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _season != null && _error != null
                              ? const SizedBox.shrink()
                              : LayoutBuilder(builder: (context, constraints) {
                                  // At most 30 lightweight cells are mounted, so D-pad neighbors exist.
                                  return SingleChildScrollView(
                                      controller: _scroll,
                                      child: _grid
                                          ? Wrap(
                                              children: List.generate(
                                                  _end - _start,
                                                  (i) => SizedBox(
                                                      width:
                                                          constraints.maxWidth /
                                                              4,
                                                      height: 86,
                                                      child:
                                                          _tile(_start + i))))
                                          : Column(
                                              children: List.generate(
                                                  _end - _start,
                                                  (i) => SizedBox(
                                                      height: 80,
                                                      child:
                                                          _tile(_start + i)))));
                                })),
                  Row(children: [
                    _tool(
                        Icons.chevron_left_rounded,
                        '上一段',
                        !_loading && _page > 0
                            ? () => _move(_start - _pageSize)
                            : null),
                    Expanded(
                        child: Center(
                            child: _queue.entries.length > _pageSize
                                ? TextButton(
                                    onPressed: _loading ? null : _chooseRange,
                                    child: Text(
                                        '${_queue.entries[_start].target.episodeNumber ?? _start + 1}–${_queue.entries[_end - 1].target.episodeNumber ?? _end} 集'))
                                : Text('${_queue.entries.length} 集',
                                    style: const TextStyle(
                                        color: AppColors.foregroundMuted)))),
                    _tool(
                        Icons.chevron_right_rounded,
                        '下一段',
                        !_loading && _end < _queue.entries.length
                            ? () => _move(_end)
                            : null),
                    _tool(Icons.my_location_rounded, '定位当前集', () {
                      ++_request;
                      setState(() {
                        _queue = widget.queue;
                        _season = null;
                        _loading = false;
                        _error = null;
                      });
                      _move(widget.queue.currentIndex);
                    }),
                  ]),
                ]))),
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }
}
