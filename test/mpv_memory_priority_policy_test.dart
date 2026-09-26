import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/application/mpv_memory_priority_policy.dart';

MpvMemoryCacheSample cache({
  bool? idle = true,
  bool? eof = false,
  bool? underrun = false,
  int? bytes = 1000,
  double? seconds = 40,
  double? end = 50,
  double? reader = 10,
}) =>
    MpvMemoryCacheSample(
        idle: idle,
        eof: eof,
        underrun: underrun,
        forwardBytes: bytes,
        seconds: seconds,
        end: end,
        reader: reader);

void main() {
  test('lease refresh does not ratchet the learned refill threshold down', () {
    final policy = MpvMemoryPriorityPolicy();
    policy.sample(cache(), active: true);
    expect(policy.sample(cache(reader: 11), active: true), isTrue);
    expect(policy.refill!.seconds, 30);
    policy.refill = null;
    for (var i = 12; i < 20; i++) {
      expect(
          policy.sample(cache(reader: i.toDouble(), seconds: 50.0 - i),
              active: true),
          isTrue);
      expect(policy.refill, isNull);
    }
  });

  test('startup idle and non-advancing reader cannot grant readiness', () {
    final policy = MpvMemoryPriorityPolicy();
    for (var i = 0; i < 5; i++) {
      expect(policy.sample(cache(), active: true), isFalse);
    }
    expect(policy.refill, isNull);
    expect(policy.sample(cache(reader: 11, seconds: 39), active: true), isTrue);
    expect(policy.refill!.seconds, 30);
    expect(policy.refill!.bytes, 750);
  });

  test('refill invalidates readiness and learns a new actual high water', () {
    final policy = MpvMemoryPriorityPolicy();
    policy.sample(cache(), active: true);
    expect(policy.sample(cache(reader: 11), active: true), isTrue);
    expect(policy.sample(cache(idle: false), active: true), isFalse);
    expect(policy.refill, isNull);
    expect(
        policy.sample(cache(end: 100, seconds: 20, bytes: 600), active: true),
        isFalse);
    expect(policy.sample(cache(end: 100, reader: 12), active: true), isTrue);
    expect(policy.refill!.seconds, 15);
    expect(policy.refill!.bytes, 450);
  });

  test('EOF must be established but never supplies a refill threshold', () {
    final policy = MpvMemoryPriorityPolicy();
    expect(policy.sample(cache(eof: true), active: true), isFalse);
    expect(policy.sample(cache(eof: true, reader: 11), active: true), isTrue);
    expect(policy.refill, isNull);
  });

  test('paused, buffering, unknown and invalid samples fail closed', () {
    for (final sample in [
      cache(idle: null),
      cache(eof: null),
      cache(underrun: null),
      cache(underrun: true),
      cache(bytes: null),
      cache(bytes: 0),
      cache(seconds: null),
      cache(seconds: double.nan),
      cache(seconds: 0),
      cache(end: double.infinity),
      cache(reader: null),
      cache(reader: 50),
    ]) {
      final policy = MpvMemoryPriorityPolicy();
      policy.sample(cache(), active: true);
      expect(policy.sample(cache(reader: 11), active: true), isTrue);
      expect(policy.sample(sample, active: true), isFalse);
      expect(policy.refill, isNull);
    }
    final policy = MpvMemoryPriorityPolicy();
    policy.sample(cache(), active: true);
    policy.sample(cache(reader: 11), active: true);
    expect(policy.sample(cache(reader: 12), active: false), isFalse);
    expect(policy.sample(cache(reader: 13), active: true), isFalse);
  });

  test('seek/reset and changing cache endpoint require fresh establishment',
      () {
    final policy = MpvMemoryPriorityPolicy();
    policy.sample(cache(), active: true);
    expect(policy.sample(cache(reader: 11), active: true), isTrue);
    policy.reset();
    expect(policy.sample(cache(reader: 12), active: true), isFalse);
    expect(policy.sample(cache(reader: 13, end: 60), active: true), isFalse);
    expect(policy.sample(cache(reader: 14, end: 60), active: true), isTrue);
  });
}
