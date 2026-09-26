part of '../player_page.dart';

extension _PlayerPageStateMemoryPriority on _PlayerPageState {
  void _publishMpvMemoryReady(Player player, bool ready) {
    final relay = _mpvRelays[player];
    if (relay is PlaybackRelayBufferControl) {
      (relay as PlaybackRelayBufferControl).updateBufferState(
        memoryReady: ready,
        url: _mpvRelayUrls[player],
      );
    }
  }

  void _invalidateMpvMemoryReady(Player player) {
    if (identical(_player, player)) {
      _mpvMemoryEpoch++;
      _mpvMemoryPolicy.reset();
    }
    _publishMpvMemoryReady(player, false);
  }

  void _stopMpvMemorySampling() {
    _mpvMemoryTimer?.cancel();
    _mpvMemoryTimer = null;
    final player = _player;
    if (player != null) _invalidateMpvMemoryReady(player);
  }

  void _startMpvMemorySampling(Player player) {
    _stopMpvMemorySampling();
    _mpvMemoryPolicy = MpvMemoryPriorityPolicy();
    _mpvMemoryTimer = Timer.periodic(const Duration(milliseconds: 750), (_) {
      unawaited(_sampleMpvMemory(player));
    });
    _mpvLifecycle.listen(player.stream.buffering, (buffering) {
      if (buffering && identical(_player, player)) {
        _invalidateMpvMemoryReady(player);
      }
    });
    unawaited(_sampleMpvMemory(player));
  }

  Future<void> _sampleMpvMemory(Player player) async {
    if (_mpvMemoryBusy || !mounted || !identical(_player, player)) return;
    _mpvMemoryBusy = true;
    final epoch = _mpvMemoryEpoch;
    final relay = _mpvRelays[player];
    final url = _mpvRelayUrls[player];
    bool current() =>
        mounted &&
        identical(_player, player) &&
        epoch == _mpvMemoryEpoch &&
        identical(relay, _mpvRelays[player]) &&
        url == _mpvRelayUrls[player];
    Future<String?> read(String name) async {
      try {
        final native = player.platform;
        if (native == null) return null;
        final String value = await (native as dynamic)
            .getProperty(name, waitForInitialization: false)
            .timeout(const Duration(milliseconds: 200));
        return value.isEmpty ? null : value;
      } catch (_) {
        return null;
      }
    }

    try {
      const names = [
        'demuxer-cache-state/idle',
        'demuxer-cache-state/eof',
        'demuxer-cache-state/underrun',
        'demuxer-cache-state/fw-bytes',
        'demuxer-cache-state/cache-duration',
        'demuxer-cache-state/cache-end',
        'demuxer-cache-state/reader-pts',
        'pause',
        'paused-for-cache',
        'seeking',
      ];
      final values = await Future.wait([
        for (final name in names) read(name),
      ]);
      if (!current()) return;
      bool? flag(int i) => switch (values[i]) {
            'yes' => true,
            'no' => false,
            _ => null,
          };
      double? number(int i) => double.tryParse(values[i] ?? '');
      final ready = _mpvMemoryPolicy.sample(
        MpvMemoryCacheSample(
          idle: flag(0),
          eof: flag(1),
          underrun: flag(2),
          forwardBytes: int.tryParse(values[3] ?? ''),
          seconds: number(4),
          end: number(5),
          reader: number(6),
        ),
        active: _isReady &&
            player.state.playing &&
            !player.state.buffering &&
            !player.state.completed &&
            flag(7) == false &&
            flag(8) == false &&
            flag(9) == false,
      );
      _publishMpvMemoryReady(player, ready);
      final refill = _mpvMemoryPolicy.refill;
      if (!ready || refill == null) return;
      _mpvMemoryPolicy.refill = null;
      final target = _resolvedTarget ?? widget.target;
      if (!isLikelyRemotePlaybackTargetTransport(target) ||
          isLikelyLiveRemotePlaybackUrl(target.streamUrl)) {
        return;
      }
      // These are documented runtime options. Probe each independently:
      // older cores support seconds but not necessarily bytes.
      await Future.wait([
        for (final (name, value) in [
          ('demuxer-hysteresis-secs', refill.seconds.toStringAsFixed(3)),
          ('demuxer-hysteresis-bytes', '${refill.bytes}'),
        ])
          () async {
            if (!current()) return;
            final supported = await read('options/$name');
            if (!current()) return;
            if (supported == null) return;
            final native = player.platform;
            if (native == null) return;
            await (native as dynamic)
                .setProperty(name, value, waitForInitialization: false)
                .timeout(const Duration(milliseconds: 250));
          }()
      ]);
    } catch (_) {
      if (current()) {
        _mpvMemoryPolicy.reset();
        _publishMpvMemoryReady(player, false);
      }
    } finally {
      _mpvMemoryBusy = false;
    }
  }
}
