import 'dart:async';
import 'package:clock/clock.dart';

import 'package:flutter/foundation.dart';

import '../data/live_channel_probe.dart';
import '../domain/live_models.dart';

class LiveProbeEntry {
  const LiveProbeEntry(this.line, this.lineIndex,
      {this.checking = false, this.result});

  final LiveLine line;
  final int lineIndex;
  final bool checking;
  final LiveProbeResult? result;

  String get label => result?.label ?? (checking ? '检测中' : '待测');
}

class LiveChannelProbeController extends ChangeNotifier {
  LiveChannelProbeController(
    this._probe, {
    this.visibilityDelay = const Duration(milliseconds: 200),
    this.successTtl = const Duration(minutes: 5),
    this.failureTtl = const Duration(seconds: 45),
    DateTime Function()? now,
  }) : _now = now ?? clock.now;

  final LiveChannelProbe _probe;
  final Duration visibilityDelay, successTtl, failureTtl;
  final DateTime Function() _now;
  final _visibleSince = <String, DateTime>{};
  final _checkedAt = <String, DateTime>{};
  final _failures = <String, int>{};
  // One wakeup covers both viewport admission and cached-result expiry.
  Timer? _admission;
  String? _priorityId;
  bool _networkAvailable = true;
  final _entries = <String, LiveProbeEntry>{};
  final _active = <_ProbeWork>{};
  Map<String, LiveProbeEntry> _visible = {};
  bool _disposed = false;
  bool _running = false;
  bool get running => _running;
  int get total => _visible.length;
  int get completed =>
      _visible.keys.where((id) => _entries[id]?.result != null).length;

  LiveProbeEntry? entry(LiveChannel channel, int preferredLine) {
    if (channel.lines.isEmpty) return null;
    final index = preferredLine.clamp(0, channel.lines.length - 1);
    final cached = _entries[channel.id];
    final line = channel.lines[index];
    if (cached == null ||
        cached.lineIndex != index ||
        cached.line.url != line.url ||
        !mapEquals(cached.line.headers, line.headers)) {
      return null;
    }
    return cached;
  }

  void start(List<LiveChannel> channels, LiveSnapshot snapshot) {
    if (running || _disposed) return;
    _visibleSince.clear();
    _visible = {};
    _running = true;
    updateVisible(channels, snapshot);
    notifyListeners();
  }

  void updateVisible(List<LiveChannel> channels, LiveSnapshot snapshot) {
    if (!running || _disposed) return;
    final targets = <String, LiveProbeEntry>{};
    for (final channel in channels) {
      if (channel.lines.isEmpty ||
          snapshot.preference(channel).hidden ||
          !snapshot.sources.any(
              (source) => source.id == channel.sourceId && source.enabled)) {
        continue;
      }
      final index =
          snapshot.preference(channel).line.clamp(0, channel.lines.length - 1);
      final source = channel.lines[index];
      final previous = _visible[channel.id];
      final target = LiveProbeEntry(
          LiveLine(source.url, headers: Map.unmodifiable(source.headers)),
          index);
      targets[channel.id] = _sameLine(previous, target) ? previous! : target;
      final entered = !_sameLine(previous, target);
      if (entered) _visibleSince[channel.id] = _now();
      if (!_sameLine(_entries[channel.id], target)) {
        _entries[channel.id] = target;
        _checkedAt.remove(channel.id);
        _failures.remove(channel.id);
      }
    }
    if (mapEquals(_visible, targets) &&
        listEquals(_visible.keys.toList(), targets.keys.toList())) {
      return;
    }
    _visible = targets;
    for (final work in _active) {
      if (!identical(targets[work.id], work.target)) {
        work.cancel();
        _clearChecking(work.id);
      }
    }
    _entries.removeWhere(
        (id, entry) => !targets.containsKey(id) && entry.result == null);
    _visibleSince.removeWhere((id, _) => !targets.containsKey(id));
    _pump();
    notifyListeners();
  }

  Duration _freshFor(String id) {
    final result = _entries[id]?.result;
    final checked = _checkedAt[id];
    if (result == null || checked == null) return Duration.zero;
    final ttl = result.status == LiveProbeStatus.responded
        ? successTtl
        : Duration(
            microseconds: (failureTtl.inMicroseconds *
                    (1 << ((_failures[id] ?? 1) - 1).clamp(0, 3)))
                .clamp(0, const Duration(minutes: 5).inMicroseconds));
    final age = _now().difference(checked);
    return age.isNegative ? Duration.zero : ttl - age;
  }

  void _clearChecking(String id) {
    final entry = _entries[id];
    if (entry != null && entry.checking) {
      _entries[id] =
          LiveProbeEntry(entry.line, entry.lineIndex, result: entry.result);
    }
  }

  void prioritize(String id) {
    _priorityId = id;
    _pump();
  }

  void invalidateNetwork({bool available = true}) {
    if (_disposed) return;
    _networkAvailable = available;
    for (final work in _active) {
      work.cancel();
    }
    _entries.clear();
    _checkedAt.clear();
    _failures.clear();
    _visible = {
      for (final item in _visible.entries)
        item.key: LiveProbeEntry(item.value.line, item.value.lineIndex),
    };
    _visibleSince.clear();
    for (final item in _visible.entries) {
      _visibleSince[item.key] = _now();
      _entries[item.key] = item.value;
    }
    _pump();
    notifyListeners();
  }

  /// Reconcile before the next layout so obsolete requests cannot commit.
  void updateSnapshot(LiveSnapshot snapshot) {
    if (_disposed) return;
    final valid = {for (final c in snapshot.channels) c.id: c};
    final enabled =
        snapshot.sources.where((s) => s.enabled).map((s) => s.id).toSet();
    _entries.removeWhere((id, cached) {
      final c = valid[id];
      return c == null ||
          !enabled.contains(c.sourceId) ||
          snapshot.preference(c).hidden ||
          entry(c, snapshot.preference(c).line) == null;
    });
    _checkedAt.removeWhere((id, _) => !_entries.containsKey(id));
    _failures.removeWhere((id, _) => !_entries.containsKey(id));
    updateVisible([
      for (final id in _visible.keys)
        if (valid[id] case final channel?) channel,
    ], snapshot);
  }

  bool _sameLine(LiveProbeEntry? a, LiveProbeEntry b) =>
      a != null &&
      a.lineIndex == b.lineIndex &&
      a.line.url == b.line.url &&
      mapEquals(a.line.headers, b.line.headers);

  void _pump() {
    _admission?.cancel();
    _admission = null;
    if (!running || _disposed || !_networkAvailable) return;
    final ordered = _visible.entries.toList();
    final priority = ordered.indexWhere((item) => item.key == _priorityId);
    if (priority > 0) ordered.insert(0, ordered.removeAt(priority));
    Duration? next;
    for (final item in ordered) {
      // Cancelled requests retain their slot until transport cleanup finishes.
      if (_active.length >= 2) break;
      if (_active.any((work) => work.id == item.key)) {
        continue;
      }
      final admission =
          visibilityDelay - _now().difference(_visibleSince[item.key]!);
      final fresh = _freshFor(item.key);
      final remaining = admission > fresh ? admission : fresh;
      if (remaining > Duration.zero) {
        if (next == null || remaining < next) next = remaining;
        continue;
      }
      final work = _ProbeWork(item.key, item.value);
      _active.add(work);
      _entries[item.key] = LiveProbeEntry(item.value.line, item.value.lineIndex,
          checking: true, result: _entries[item.key]?.result);
      unawaited(_run(work));
    }
    if (next != null && _active.length < 2) {
      _admission = Timer(next, () {
        _pump();
        if (!_disposed) notifyListeners();
      });
    }
  }

  Future<void> _run(_ProbeWork work) async {
    try {
      LiveProbeResult result;
      try {
        result = await _probe.probe(work.target.line,
            cancel: work.cancellation.future);
      } catch (_) {
        result = LiveProbeResult(LiveProbeStatus.networkError,
            checkedAt: DateTime.now());
      }
      if (!_disposed &&
          running &&
          !work.cancellation.isCompleted &&
          identical(_visible[work.id], work.target)) {
        _entries[work.id] = LiveProbeEntry(
            work.target.line, work.target.lineIndex,
            result: result);
        _checkedAt[work.id] = _now();
        if (result.status == LiveProbeStatus.responded) {
          _failures.remove(work.id);
        } else {
          _failures[work.id] = ((_failures[work.id] ?? 0) + 1).clamp(1, 4);
        }
      }
    } finally {
      work.cancel();
      _active.remove(work);
      work.done.complete();
      _pump();
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> stop() {
    _running = false;
    _admission?.cancel();
    _admission = null;
    _visibleSince.clear();
    _visible = {};
    for (final work in _active) {
      work.cancel();
      _clearChecking(work.id);
    }
    _entries.removeWhere((_, entry) => entry.result == null);
    if (!_disposed) notifyListeners();
    return Future.wait(_active.map((work) => work.done.future));
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}

class _ProbeWork {
  _ProbeWork(this.id, this.target);
  final String id;
  final LiveProbeEntry target;
  final cancellation = Completer<void>();
  final done = Completer<void>();
  void cancel() {
    if (!cancellation.isCompleted) cancellation.complete();
  }
}
