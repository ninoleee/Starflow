import 'package:flutter/material.dart';

import '../domain/live_models.dart';

/// Tracks laid-out rows, excluding ListView's offscreen cache extent.
class LiveProbeViewport extends StatefulWidget {
  const LiveProbeViewport(
      {super.key, required this.onChanged, required this.child});

  final ValueChanged<List<LiveChannel>> onChanged;
  final Widget child;

  @override
  State<LiveProbeViewport> createState() => _LiveProbeViewportState();
}

class _LiveProbeViewportState extends State<LiveProbeViewport> {
  final _items = <_LiveProbeViewportItemState>{};
  final _bounds = GlobalKey();
  bool _scheduled = false;

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final viewport = _bounds.currentContext?.findRenderObject();
      if (viewport is! RenderBox || !viewport.hasSize) return;
      final visible = <(double, LiveChannel)>[];
      for (final item in _items) {
        final row = item.context.findRenderObject();
        if (row is! RenderBox || !row.attached || !row.hasSize) continue;
        final origin = row.localToGlobal(Offset.zero, ancestor: viewport);
        if ((origin & row.size).overlaps(Offset.zero & viewport.size)) {
          visible.add((origin.dy, item.widget.channel));
        }
      }
      visible.sort((a, b) => a.$1.compareTo(b.$1));
      widget.onChanged([for (final item in visible) item.$2]);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    _schedule();
    return _ViewportScope(
      owner: this,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _schedule();
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _schedule();
            return false;
          },
          child: SizedBox(key: _bounds, child: widget.child),
        ),
      ),
    );
  }
}

class LiveProbeViewportItem extends StatefulWidget {
  const LiveProbeViewportItem(
      {super.key, required this.channel, required this.child});
  final LiveChannel channel;
  final Widget child;

  @override
  State<LiveProbeViewportItem> createState() => _LiveProbeViewportItemState();
}

class _LiveProbeViewportItemState extends State<LiveProbeViewportItem> {
  _LiveProbeViewportState? _owner;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owner =
        context.dependOnInheritedWidgetOfExactType<_ViewportScope>()!.owner;
    _owner?._items.remove(this);
    _owner = owner;
    owner._items.add(this);
    owner._schedule();
  }

  @override
  void activate() {
    super.activate();
    _owner?._items.add(this);
    _owner?._schedule();
  }

  @override
  void deactivate() {
    _owner?._items.remove(this);
    _owner?._schedule();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    _owner?._schedule();
    return widget.child;
  }
}

class _ViewportScope extends InheritedWidget {
  const _ViewportScope({required this.owner, required super.child});
  final _LiveProbeViewportState owner;

  @override
  bool updateShouldNotify(_ViewportScope oldWidget) => owner != oldWidget.owner;
}
