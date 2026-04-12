import 'dart:async';

import 'package:media_kit/media_kit.dart';

enum MpvStallRecoveryLevel { none, soft, hard }

class MpvPlaybackSnapshot {
  const MpvPlaybackSnapshot({
    required this.position,
    required this.duration,
    required this.playing,
    required this.buffering,
    required this.bufferingPercentage,
  });

  factory MpvPlaybackSnapshot.fromPlayer(Player player) {
    final state = player.state;
    return MpvPlaybackSnapshot(
      position: state.position,
      duration: state.duration,
      playing: state.playing,
      buffering: state.buffering,
      bufferingPercentage: state.bufferingPercentage,
    );
  }

  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;
  final double bufferingPercentage;
}

class MpvStallWatchdogConfig {
  const MpvStallWatchdogConfig({
    this.minBufferingBeforeCheck = const Duration(seconds: 2),
    this.softRecoverAfter = const Duration(seconds: 6),
    this.hardRecoverAfter = const Duration(seconds: 12),
    this.progressDeltaThreshold = const Duration(milliseconds: 250),
    this.endOfStreamTolerance = const Duration(seconds: 1),
    this.requirePlaying = true,
  });

  final Duration minBufferingBeforeCheck;
  final Duration softRecoverAfter;
  final Duration hardRecoverAfter;
  final Duration progressDeltaThreshold;
  final Duration endOfStreamTolerance;
  final bool requirePlaying;
}

class MpvStallDecision {
  const MpvStallDecision({
    required this.level,
    required this.triggered,
    required this.bufferingFor,
    required this.stagnantFor,
    required this.position,
    required this.bufferingPercentage,
    required this.reason,
  });

  const MpvStallDecision.none({
    required this.position,
    required this.bufferingPercentage,
    this.bufferingFor = Duration.zero,
    this.stagnantFor = Duration.zero,
    this.reason = 'healthy',
  })  : level = MpvStallRecoveryLevel.none,
        triggered = false;

  final MpvStallRecoveryLevel level;
  final bool triggered;
  final Duration bufferingFor;
  final Duration stagnantFor;
  final Duration position;
  final double bufferingPercentage;
  final String reason;

  bool get shouldRecover => level != MpvStallRecoveryLevel.none;
}

typedef MpvStallRecoveryCallback = FutureOr<void> Function(
  MpvStallDecision decision,
);

class MpvStallWatchdog {
  MpvStallWatchdog({
    this.config = const MpvStallWatchdogConfig(),
    this.onSoftRecover,
    this.onHardRecover,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final MpvStallWatchdogConfig config;
  final MpvStallRecoveryCallback? onSoftRecover;
  final MpvStallRecoveryCallback? onHardRecover;
  final DateTime Function() _clock;

  Duration? _lastPosition;
  DateTime? _bufferingStartedAt;
  DateTime? _lastProgressAt;
  bool _softTriggered = false;
  bool _hardTriggered = false;

  void reset() {
    _bufferingStartedAt = null;
    _lastProgressAt = null;
    _softTriggered = false;
    _hardTriggered = false;
  }

  MpvStallDecision evaluate(
    MpvPlaybackSnapshot snapshot, {
    DateTime? now,
  }) {
    final current = now ?? _clock();

    if (_didProgress(snapshot.position)) {
      _lastProgressAt = current;
      _softTriggered = false;
      _hardTriggered = false;
    }
    _lastPosition = snapshot.position;

    if (_isNearEnd(snapshot)) {
      reset();
      return MpvStallDecision.none(
        position: snapshot.position,
        bufferingPercentage: snapshot.bufferingPercentage,
        reason: 'near-end-of-stream',
      );
    }

    final canDetect = snapshot.buffering &&
        (!config.requirePlaying || snapshot.playing) &&
        !snapshot.position.isNegative;
    if (!canDetect) {
      reset();
      return MpvStallDecision.none(
        position: snapshot.position,
        bufferingPercentage: snapshot.bufferingPercentage,
        reason: 'buffering-inactive',
      );
    }

    _bufferingStartedAt ??= current;
    _lastProgressAt ??= current;

    final bufferingFor = current.difference(_bufferingStartedAt!);
    final stagnantFor = current.difference(_lastProgressAt!);
    if (bufferingFor < config.minBufferingBeforeCheck ||
        stagnantFor < config.minBufferingBeforeCheck) {
      return MpvStallDecision.none(
        position: snapshot.position,
        bufferingPercentage: snapshot.bufferingPercentage,
        bufferingFor: bufferingFor,
        stagnantFor: stagnantFor,
        reason: 'warmup',
      );
    }

    if (stagnantFor >= config.hardRecoverAfter && !_hardTriggered) {
      _hardTriggered = true;
      _softTriggered = true;
      return MpvStallDecision(
        level: MpvStallRecoveryLevel.hard,
        triggered: true,
        bufferingFor: bufferingFor,
        stagnantFor: stagnantFor,
        position: snapshot.position,
        bufferingPercentage: snapshot.bufferingPercentage,
        reason: 'stalled-hard-threshold',
      );
    }

    if (stagnantFor >= config.softRecoverAfter && !_softTriggered) {
      _softTriggered = true;
      return MpvStallDecision(
        level: MpvStallRecoveryLevel.soft,
        triggered: true,
        bufferingFor: bufferingFor,
        stagnantFor: stagnantFor,
        position: snapshot.position,
        bufferingPercentage: snapshot.bufferingPercentage,
        reason: 'stalled-soft-threshold',
      );
    }

    if (_hardTriggered) {
      return MpvStallDecision(
        level: MpvStallRecoveryLevel.hard,
        triggered: false,
        bufferingFor: bufferingFor,
        stagnantFor: stagnantFor,
        position: snapshot.position,
        bufferingPercentage: snapshot.bufferingPercentage,
        reason: 'stalled-hard-persistent',
      );
    }
    if (_softTriggered) {
      return MpvStallDecision(
        level: MpvStallRecoveryLevel.soft,
        triggered: false,
        bufferingFor: bufferingFor,
        stagnantFor: stagnantFor,
        position: snapshot.position,
        bufferingPercentage: snapshot.bufferingPercentage,
        reason: 'stalled-soft-persistent',
      );
    }

    return MpvStallDecision.none(
      position: snapshot.position,
      bufferingPercentage: snapshot.bufferingPercentage,
      bufferingFor: bufferingFor,
      stagnantFor: stagnantFor,
      reason: 'healthy-buffering',
    );
  }

  Future<MpvStallDecision> evaluateAndNotify(
    MpvPlaybackSnapshot snapshot, {
    DateTime? now,
  }) async {
    final decision = evaluate(snapshot, now: now);
    if (!decision.triggered) {
      return decision;
    }
    switch (decision.level) {
      case MpvStallRecoveryLevel.none:
        return decision;
      case MpvStallRecoveryLevel.soft:
        await onSoftRecover?.call(decision);
        return decision;
      case MpvStallRecoveryLevel.hard:
        await onHardRecover?.call(decision);
        return decision;
    }
  }

  bool _didProgress(Duration position) {
    final previous = _lastPosition;
    if (previous == null) {
      return false;
    }
    final delta = position - previous;
    return delta >= config.progressDeltaThreshold;
  }

  bool _isNearEnd(MpvPlaybackSnapshot snapshot) {
    if (snapshot.duration <= Duration.zero) {
      return false;
    }
    final remaining = snapshot.duration - snapshot.position;
    return remaining <= config.endOfStreamTolerance;
  }
}
