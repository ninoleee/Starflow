import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _kTvPlatformChannel = MethodChannel('starflow/platform');

final isTelevisionProvider = FutureProvider<bool>((ref) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return false;
  }

  try {
    final result = await _kTvPlatformChannel.invokeMethod<bool>('isTelevision');
    return result ?? false;
  } catch (_) {
    return false;
  }
});
