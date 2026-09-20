import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/live_logo_provider.dart';

class LiveLogo extends ConsumerWidget {
  const LiveLogo({super.key, required this.url});
  final String url;
  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
      width: 64,
      height: 40,
      child: url.startsWith('https://') || url.startsWith('http://')
          ? ref.watch(liveLogoProvider(url)).when(
              data: (bytes) => Image(
                  // Bound decoding without changing the logo's aspect ratio.
                  image: ResizeImage(MemoryImage(bytes),
                      width: 192,
                      height: 120,
                      policy: ResizeImagePolicy.fit),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.live_tv)),
              loading: () => const Icon(Icons.live_tv),
              error: (_, __) => const Icon(Icons.live_tv))
          : const Icon(Icons.live_tv));
}
