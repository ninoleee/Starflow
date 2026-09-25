import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/application/mpv_playback_diagnostics.dart';

void main() {
  test('health snapshots read only bounded local diagnostics', () async {
    final names = <String>[];
    final properties =
        await readMpvHealthProperties(readProperty: (name) async {
      names.add(name);
      return null;
    });
    expect(names, [
      'demuxer-cache-duration',
      'cache-speed',
      'hwdec-current',
      'decoder-frame-drop-count',
      'frame-drop-count',
      'avsync'
    ]);
    expect(properties.length, 6);
    expect(properties.values.every((value) => value == null), isTrue);
  });

  test('health logging is limited to once per ten seconds per session', () {
    final gate = MpvHealthLogGate();
    final now = DateTime(2026);
    expect(gate.admit(now), isTrue);
    expect(gate.admit(now.add(const Duration(milliseconds: 9999))), isFalse);
    expect(gate.admit(now.add(const Duration(seconds: 10))), isTrue);
    expect(MpvHealthLogGate().admit(now), isTrue);
  });
  test('disabled diagnostics only reads the functional bandwidth sample',
      () async {
    final reads = <String>[];
    final values = await readMpvShutdownProperties(
      includeDiagnostics: false,
      readProperty: (name) async {
        reads.add(name);
        return '1200000';
      },
    );
    expect(reads, ['cache-speed']);
    expect(values, {'cache-speed': '1200000'});
  });

  test('enabled diagnostics reads each property once in parallel', () async {
    final pending = <String, Completer<String?>>{};
    final result = readMpvShutdownProperties(
      includeDiagnostics: true,
      readProperty: (name) => (pending[name] = Completer<String?>()).future,
    );
    expect(pending.length, 12);
    for (final entry in pending.entries) {
      entry.value.complete(entry.key == 'avsync' ? null : entry.key);
    }
    final values = await result;
    expect(values['cache-speed'], 'cache-speed');
    expect(values['audio-out-params/channel-count'],
        'audio-out-params/channel-count');
    expect(values['avsync'], isNull);
  });
}
