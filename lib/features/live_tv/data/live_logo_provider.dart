import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/network/bounded_http_request.dart';
import 'package:starflow/core/network/starflow_http_transport.dart';
import 'package:starflow/core/scheduling/async_work_pool.dart';
import 'live_playlist_parser.dart';

final _pool = AsyncWorkPool(4);
final liveLogoProvider =
    FutureProvider.autoDispose.family<Uint8List, String>((ref, url) async {
  if (!isLiveHttpUrl(url)) throw const FormatException('Invalid logo');
  final cancel = Completer<void>();
  ref.onDispose(() {
    if (!cancel.isCompleted) cancel.complete();
  });
  return _pool.run(() async {
    if (cancel.isCompleted) throw StateError('Cancelled');
    final client = createStarflowTransportClient();
    try {
      final response = await sendBoundedRequest(client, 'GET', Uri.parse(url),
          cancel: cancel.future,
          timeout: const Duration(seconds: 15),
          maxBytes: 2 * 1024 * 1024);
      if (response.statusCode != 200) throw StateError('Logo unavailable');
      return response.bodyBytes;
    } catch (_) {
      throw StateError('Logo unavailable');
    } finally {
      client.close();
    }
  });
});
