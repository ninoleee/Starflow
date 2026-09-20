import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/live_tv/data/live_probe_network.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'system events distinguish connection types, deduplicate and unsubscribe',
      () async {
    const channel =
        MethodChannel('dev.fluttercommunity.plus/connectivity_status');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final events = <bool>[];
    final subscription =
        container.read(liveProbeNetworkProvider).listen(events.add);
    await Future<void>.delayed(Duration.zero);
    Future<void> emit(List<String> interfaces) async {
      await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeSuccessEnvelope(interfaces),
          (_) {});
      await Future<void>.delayed(Duration.zero);
    }

    await emit(['wifi']);
    await emit(['wifi']);
    await emit(['mobile']);
    await emit(['none']);
    await emit(['wifi', 'vpn']);
    await emit(['vpn', 'wifi']);
    expect(events, [true, true, false, true]);
    await subscription.cancel();
    expect(calls, ['listen', 'cancel']);
  });
}
