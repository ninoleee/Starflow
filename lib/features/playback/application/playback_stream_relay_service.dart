import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_service_stub.dart'
    if (dart.library.io) 'package:starflow/features/playback/application/playback_stream_relay_service_io.dart'
    as impl;

final playbackStreamRelayServiceProvider =
    Provider<PlaybackStreamRelayService>((ref) {
  final service = impl.createPlaybackStreamRelayService();
  ref.onDispose(() {
    unawaited(service.close());
  });
  return service;
});
