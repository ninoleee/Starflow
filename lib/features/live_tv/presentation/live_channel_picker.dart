import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starflow/app/theme/app_colors.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

import '../domain/live_models.dart';
import 'live_widgets.dart';

class LiveChannelPicker extends StatefulWidget {
  const LiveChannelPicker({
    super.key,
    required this.snapshot,
    required this.currentChannel,
    this.nowNext = const {},
    this.closeFocus,
    required this.onSelected,
  });

  final LiveSnapshot snapshot;
  final LiveChannel currentChannel;
  final Map<String, List<LiveProgramme>> nowNext;
  final FocusNode? closeFocus;
  final ValueChanged<LiveChannel> onSelected;

  @override
  State<LiveChannelPicker> createState() => LiveChannelPickerState();
}

class LiveChannelPickerState extends State<LiveChannelPicker> {
  final _groupsKey = GlobalKey<_PickerColumnState>();
  final _channelsKey = GlobalKey<_PickerColumnState>();
  late String _group = widget.snapshot.group(widget.currentChannel);

  void focusChannels() {
    final column = _channelsKey.currentState;
    if (column != null && column.widget.ids.isNotEmpty) {
      column.focusItem(column.focusedIndex);
    } else {
      _groupsKey.currentState?.focusItem(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final visible = widget.snapshot.visible();
    final groups = [
      '',
      ...visible.map(widget.snapshot.group).where((g) => g.isNotEmpty).toSet()
    ];
    if (!groups.contains(_group)) _group = '';
    final channels = visible
        .where((c) => _group.isEmpty || widget.snapshot.group(c) == _group)
        .toList();
    final current =
        channels.indexWhere((c) => c.id == widget.currentChannel.id);
    final accent = AppActionColors.of(Theme.of(context)).primary;

    void selectGroup(int index) {
      if (_group != groups[index]) setState(() => _group = groups[index]);
    }

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: LayoutBuilder(
          builder: (context, constraints) => Row(children: [
                SizedBox(
                  width: (constraints.maxWidth * .32).clamp(100.0, 180.0),
                  child: _PickerColumn(
                    key: _groupsKey,
                    ids: groups,
                    initialIndex: groups.indexOf(_group),
                    focusPrefix: 'live-group',
                    onAbove: widget.closeFocus?.requestFocus,
                    onRight: focusChannels,
                    onFocused: selectGroup,
                    onPressed: selectGroup,
                    itemBuilder: (index) {
                      final selected = groups[index] == _group;
                      return ColoredBox(
                        color: selected
                            ? accent.withValues(alpha: .09)
                            : Colors.transparent,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                                groups[index].isEmpty ? '全部分组' : groups[index],
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    TextStyle(color: selected ? accent : null)),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                    child: channels.isEmpty
                        ? const Center(child: Text('暂无频道'))
                        : _PickerColumn(
                            key: _channelsKey,
                            ids: channels.map((c) => c.id).toList(),
                            initialIndex: math.max(0, current),
                            focusPrefix: 'live-overlay',
                            autofocus: true,
                            onAbove: widget.closeFocus?.requestFocus,
                            onLeft: () => _groupsKey.currentState
                                ?.focusItem(groups.indexOf(_group)),
                            onPressed: (index) =>
                                widget.onSelected(channels[index]),
                            itemBuilder: (index) {
                              final channel = channels[index];
                              final selected =
                                  channel.id == widget.currentChannel.id;
                              final schedule = widget.nowNext[
                                      '${channel.sourceId}|${widget.snapshot.epgId(channel)}'] ??
                                  const <LiveProgramme>[];
                              final current = schedule
                                  .where((p) => p.contains(now))
                                  .firstOrNull;
                              return ListTile(
                                minTileHeight: 64,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                minLeadingWidth: 20,
                                horizontalTitleGap: 8,
                                selected: selected,
                                selectedColor: accent,
                                selectedTileColor:
                                    accent.withValues(alpha: .09),
                                leading: const Icon(Icons.live_tv, size: 20),
                                trailing: SizedBox(
                                    width: 20,
                                    child: selected
                                        ? const Icon(Icons.play_arrow, size: 20)
                                        : null),
                                title: Text(widget.snapshot.name(channel),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: LiveCurrentProgramme(
                                    programme: current, compact: true),
                              );
                            },
                          )),
              ])),
    );
  }
}

class _PickerColumn extends StatefulWidget {
  const _PickerColumn(
      {super.key,
      required this.ids,
      required this.initialIndex,
      required this.focusPrefix,
      required this.itemBuilder,
      required this.onPressed,
      this.onAbove,
      this.autofocus = false,
      this.onLeft,
      this.onRight,
      this.onFocused});

  final List<String> ids;
  final int initialIndex;
  final String focusPrefix;
  final Widget Function(int index) itemBuilder;
  final ValueChanged<int> onPressed;
  final ValueChanged<int>? onFocused;
  final VoidCallback? onAbove;
  final VoidCallback? onLeft, onRight;
  final bool autofocus;

  @override
  State<_PickerColumn> createState() => _PickerColumnState();
}

class _PickerColumnState extends State<_PickerColumn> {
  static const _extent = 64.0;
  final _nodes = <String, FocusNode>{};
  ScrollController? _scroll;
  late int focusedIndex = widget.initialIndex;
  bool _resetOffset = false;
  int _request = 0;

  FocusNode _node(int index) => _nodes.putIfAbsent(
      widget.ids[index],
      () =>
          FocusNode(debugLabel: '${widget.focusPrefix}:${widget.ids[index]}'));

  @override
  void didUpdateWidget(covariant _PickerColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.ids, widget.ids)) {
      final focusedId = oldWidget.ids.elementAtOrNull(focusedIndex);
      final index = focusedId == null ? -1 : widget.ids.indexOf(focusedId);
      focusedIndex = index < 0 ? widget.initialIndex : index;
      _resetOffset = true;
      ++_request;
    }
  }

  double _offset(int index, double height) =>
      (index * _extent - (height - _extent) / 2)
          .clamp(0.0, math.max(0.0, widget.ids.length * _extent - height));

  void focusItem(int index) {
    if (widget.ids.isEmpty) return;
    focusedIndex = index.clamp(0, widget.ids.length - 1);
    final request = ++_request;
    final node = _node(focusedIndex);
    final attached = node.context != null;
    if (attached) {
      // Transfer focus before the next paint, including cached edge rows.
      node.requestFocus();
    } else {
      for (final previous in _nodes.values) {
        if (previous.hasFocus) previous.unfocus();
      }
    }
    final scroll = _scroll;
    if (scroll != null && scroll.hasClients) {
      final position = scroll.position;
      final top = focusedIndex * _extent;
      final bottom = top + _extent;
      final offset = top < position.pixels
          ? top
          : bottom > position.pixels + position.viewportDimension
              ? bottom - position.viewportDimension
              : position.pixels;
      final target =
          offset.clamp(position.minScrollExtent, position.maxScrollExtent);
      if (target != position.pixels) scroll.jumpTo(target);
    }
    if (attached) return;
    // Only unbuilt rows need a layout pass before receiving focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && request == _request) {
        final node = _node(focusedIndex);
        if (node.context != null) node.requestFocus();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        _scroll ??= ScrollController(
            initialScrollOffset: _offset(focusedIndex, constraints.maxHeight));
        if (_resetOffset) {
          _resetOffset = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scroll!.hasClients) {
              _scroll!.jumpTo(
                  _offset(focusedIndex, _scroll!.position.viewportDimension));
            }
          });
        }
        return ListView.builder(
          controller: _scroll,
          padding: EdgeInsets.zero,
          itemExtent: _extent,
          itemCount: widget.ids.length,
          itemBuilder: (context, index) => Focus(
            onKeyEvent: (_, event) {
              if (event is KeyUpEvent) return KeyEventResult.ignored;
              switch (event.logicalKey) {
                case LogicalKeyboardKey.arrowUp:
                  if (focusedIndex == 0) {
                    widget.onAbove?.call();
                  } else {
                    focusItem(focusedIndex - 1);
                  }
                case LogicalKeyboardKey.arrowDown:
                  focusItem(math.min(focusedIndex + 1, widget.ids.length - 1));
                case LogicalKeyboardKey.arrowLeft:
                  widget.onLeft?.call();
                case LogicalKeyboardKey.arrowRight:
                  widget.onRight?.call();
                default:
                  return KeyEventResult.ignored;
              }
              return KeyEventResult.handled;
            },
            child: TvFocusableAction(
              key: ValueKey(widget.ids[index]),
              focusNode: _node(index),
              focusId: '${widget.focusPrefix}:${widget.ids[index]}',
              autofocus: widget.autofocus && index == widget.initialIndex,
              onFocused: () {
                focusedIndex = index;
                widget.onFocused?.call(index);
              },
              onPressed: () => widget.onPressed(index),
              child: widget.itemBuilder(index),
            ),
          ),
        );
      });

  @override
  void dispose() {
    ++_request;
    _scroll?.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }
}
