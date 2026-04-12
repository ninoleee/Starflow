import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:starflow/core/storage/persistent_image_cache.dart';
import 'package:starflow/core/utils/network_image_headers.dart';
import 'package:starflow/features/playback/application/playback_session.dart';

typedef AppNetworkImageErrorBuilder = Widget Function(
    BuildContext context, Object error, StackTrace? stackTrace);
typedef AppNetworkImageLoadingBuilder = Widget Function(BuildContext context);

enum AppNetworkImageCachePolicy {
  persistent,
  networkOnly,
}

class AppNetworkImageSource {
  const AppNetworkImageSource({
    required this.url,
    this.headers = const {},
    this.cachePolicy = AppNetworkImageCachePolicy.persistent,
  });

  final String url;
  final Map<String, String> headers;
  final AppNetworkImageCachePolicy cachePolicy;
}

class AppNetworkImage extends ConsumerStatefulWidget {
  const AppNetworkImage(
    this.url, {
    super.key,
    this.headers,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.cacheWidth,
    this.cacheHeight,
    this.filterQuality = FilterQuality.low,
    this.errorBuilder,
    this.loadingBuilder,
    this.debugLabel = '',
    this.fallbackSources = const [],
    this.cachePolicy = AppNetworkImageCachePolicy.persistent,
  });

  final String url;
  final Map<String, String>? headers;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final int? cacheWidth;
  final int? cacheHeight;
  final FilterQuality filterQuality;
  final AppNetworkImageErrorBuilder? errorBuilder;
  final AppNetworkImageLoadingBuilder? loadingBuilder;
  final String debugLabel;
  final List<AppNetworkImageSource> fallbackSources;
  final AppNetworkImageCachePolicy cachePolicy;

  @override
  ConsumerState<AppNetworkImage> createState() => _AppNetworkImageState();
}

final Map<String, Future<_ResolvedImageContent>> _resolvedImageFutureCache = {};

class _AppNetworkImageState extends ConsumerState<AppNetworkImage> {
  Future<_ResolvedImageContent>? _resolvedImageFuture;

  @override
  void initState() {
    super.initState();
    _refreshResolvedImageFuture();
  }

  @override
  void didUpdateWidget(covariant AppNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url.trim() != widget.url.trim() ||
        !_sameHeaders(oldWidget.headers, widget.headers) ||
        oldWidget.cachePolicy != widget.cachePolicy ||
        !_sameImageSources(
          oldWidget.fallbackSources,
          widget.fallbackSources,
        )) {
      _refreshResolvedImageFuture(force: true);
    }
  }

  void _refreshResolvedImageFuture({bool force = false}) {
    final backgroundImageLoadingSuspended =
        ref.read(backgroundImageLoadingSuspendedProvider);
    if (backgroundImageLoadingSuspended) {
      if (force) {
        _resolvedImageFuture = null;
      }
      return;
    }
    _resolvedImageFuture = _resolveImageFuture();
  }

  Future<_ResolvedImageContent>? _resolveImageFuture() {
    final candidates = _buildCandidateSources();
    if (candidates.isEmpty) {
      return null;
    }
    if (!_shouldUseResolvedImageFutureCache(candidates)) {
      return _loadAndAnalyze(candidates);
    }
    final cacheKey = _buildCandidatesCacheKey(candidates);
    final cachedFuture = _resolvedImageFutureCache[cacheKey];
    if (cachedFuture != null) {
      return cachedFuture;
    }
    final future = _loadAndAnalyze(candidates);
    _resolvedImageFutureCache[cacheKey] = future;
    future.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {
        _resolvedImageFutureCache.remove(cacheKey);
        return;
      },
    );
    return future;
  }

  Future<_ResolvedImageContent> _loadAndAnalyze(
    List<AppNetworkImageSource> candidates,
  ) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (final candidate in candidates) {
      try {
        final bytes = await persistentImageCache.load(
          candidate.url,
          headers: candidate.headers,
          persist:
              candidate.cachePolicy == AppNetworkImageCachePolicy.persistent,
        );
        return _ResolvedImageContent(
          bytes: bytes,
          isSvg: _looksLikeSvg(candidate.url, bytes),
          sourceUrl: candidate.url,
          sourceHeaders: candidate.headers,
          sourceCachePolicy: candidate.cachePolicy,
        );
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
      }
    }
    if (lastError != null && lastStackTrace != null) {
      Error.throwWithStackTrace(lastError, lastStackTrace);
    }
    throw StateError('Image URL is empty.');
  }

  @override
  Widget build(BuildContext context) {
    final backgroundImageLoadingSuspended =
        ref.watch(backgroundImageLoadingSuspendedProvider);
    final hasCandidates = _buildCandidateSources().isNotEmpty;
    if (!hasCandidates) {
      return _buildError(
        context,
        StateError('Image URL is empty.'),
      );
    }

    if (backgroundImageLoadingSuspended) {
      return _buildLoading(context);
    }

    _resolvedImageFuture ??= _resolveImageFuture();
    final resolvedImageFuture = _resolvedImageFuture;
    if (resolvedImageFuture == null) {
      return _buildError(
        context,
        StateError('Image URL is empty.'),
      );
    }

    return FutureBuilder<_ResolvedImageContent>(
      future: resolvedImageFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildError(context, snapshot.error!, snapshot.stackTrace);
        }

        final resolved = snapshot.data;
        if (resolved == null) {
          return _buildLoading(context);
        }

        final bytes = resolved.bytes;
        if (resolved.isSvg) {
          return SvgPicture.memory(
            bytes,
            width: widget.width,
            height: widget.height,
            fit: widget.fit ?? BoxFit.contain,
            alignment: widget.alignment,
            placeholderBuilder: (context) => _buildLoading(context),
          );
        }
        final rasterImageProvider = ResizeImage.resizeIfNeeded(
          widget.cacheWidth,
          widget.cacheHeight,
          resolved.rasterProvider,
        );
        return Image(
          image: rasterImageProvider,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          alignment: widget.alignment,
          filterQuality: widget.filterQuality,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return _buildError(context, error, stackTrace);
          },
        );
      },
    );
  }

  bool _looksLikeSvg(String url, Uint8List bytes) {
    if (url.trim().toLowerCase().contains('.svg')) {
      return true;
    }
    final prefix = String.fromCharCodes(bytes.take(256));
    return prefix.contains('<svg');
  }

  Widget _buildLoading(BuildContext context) {
    return widget.loadingBuilder?.call(context) ?? const SizedBox.shrink();
  }

  List<AppNetworkImageSource> _buildCandidateSources() {
    final seen = <String>{};
    final candidates = <AppNetworkImageSource>[];

    void add(
      String url,
      Map<String, String>? headers,
      AppNetworkImageCachePolicy cachePolicy,
    ) {
      final trimmedUrl = url.trim();
      final resolvedHeaders = (headers?.isNotEmpty ?? false)
          ? headers!
          : (networkImageHeadersForUrl(trimmedUrl) ?? const <String, String>{});
      final sourceIdentity = _buildSourceIdentity(
        trimmedUrl,
        resolvedHeaders,
        cachePolicy: cachePolicy,
      );
      if (trimmedUrl.isEmpty || !seen.add(sourceIdentity)) {
        return;
      }
      candidates.add(
        AppNetworkImageSource(
          url: trimmedUrl,
          headers: resolvedHeaders,
          cachePolicy: cachePolicy,
        ),
      );
    }

    add(widget.url, widget.headers, widget.cachePolicy);
    for (final source in widget.fallbackSources) {
      add(source.url, source.headers, source.cachePolicy);
    }
    return candidates;
  }

  bool _shouldUseResolvedImageFutureCache(
    List<AppNetworkImageSource> candidates,
  ) {
    return candidates.every(
      (candidate) =>
          candidate.cachePolicy == AppNetworkImageCachePolicy.persistent,
    );
  }

  String _buildCandidatesCacheKey(List<AppNetworkImageSource> candidates) {
    return candidates
        .map((candidate) =>
            _buildSourceIdentity(
              candidate.url,
              candidate.headers,
              cachePolicy: candidate.cachePolicy,
            ))
        .join('\u0000');
  }

  Widget _buildError(
    BuildContext context,
    Object error, [
    StackTrace? stackTrace,
  ]) {
    return widget.errorBuilder?.call(context, error, stackTrace) ??
        const SizedBox.shrink();
  }
}

class _ResolvedImageContent {
  const _ResolvedImageContent({
    required this.bytes,
    required this.isSvg,
    required this.sourceUrl,
    required this.sourceHeaders,
    required this.sourceCachePolicy,
  });

  final Uint8List bytes;
  final bool isSvg;
  final String sourceUrl;
  final Map<String, String> sourceHeaders;
  final AppNetworkImageCachePolicy sourceCachePolicy;

  ImageProvider<Object> get rasterProvider {
    return _PersistentMemoryImageProvider(
      bytes: bytes,
      sourceKey: _buildSourceIdentity(
        sourceUrl,
        sourceHeaders,
        cachePolicy: sourceCachePolicy,
      ),
      bytesFingerprint: _fingerprintBytes(bytes),
    );
  }
}

bool _sameHeaders(Map<String, String>? left, Map<String, String>? right) {
  final normalizedLeft = left == null || left.isEmpty
      ? null
      : Map<String, String>.from(left);
  final normalizedRight = right == null || right.isEmpty
      ? null
      : Map<String, String>.from(right);
  return mapEquals(normalizedLeft, normalizedRight);
}

bool _sameImageSources(
  List<AppNetworkImageSource> left,
  List<AppNetworkImageSource> right,
) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    final leftSource = left[index];
    final rightSource = right[index];
    if (leftSource.url != rightSource.url ||
        !mapEquals(leftSource.headers, rightSource.headers) ||
        leftSource.cachePolicy != rightSource.cachePolicy) {
      return false;
    }
  }
  return true;
}

String _buildSourceIdentity(
  String url,
  Map<String, String> headers, {
  AppNetworkImageCachePolicy cachePolicy =
      AppNetworkImageCachePolicy.persistent,
}) {
  final normalizedUrl = url.trim();
  final buffer = StringBuffer()
    ..write(cachePolicy.name)
    ..write('|')
    ..write(normalizedUrl);
  if (headers.isEmpty) {
    return buffer.toString();
  }
  final normalizedHeaders = headers.entries
      .map((entry) =>
          MapEntry(entry.key.trim().toLowerCase(), entry.value.trim()))
      .where((entry) => entry.key.isNotEmpty && entry.value.isNotEmpty)
      .toList(growable: false)
    ..sort((a, b) => a.key.compareTo(b.key));
  if (normalizedHeaders.isEmpty) {
    return buffer.toString();
  }
  for (final entry in normalizedHeaders) {
    buffer
      ..write('\n')
      ..write(entry.key)
      ..write(':')
      ..write(entry.value);
  }
  return buffer.toString();
}

String _fingerprintBytes(Uint8List bytes) {
  var hash = 2166136261;
  for (final value in bytes) {
    hash = 0x1fffffff & (hash ^ value);
    hash = 0x1fffffff & (hash * 16777619);
  }
  return hash.toRadixString(16);
}

@immutable
class _PersistentMemoryImageProvider
    extends ImageProvider<_PersistentMemoryImageProvider> {
  const _PersistentMemoryImageProvider({
    required this.bytes,
    required this.sourceKey,
    required this.bytesFingerprint,
  });

  final Uint8List bytes;
  final String sourceKey;
  final String bytesFingerprint;

  @override
  Future<_PersistentMemoryImageProvider> obtainKey(
      ImageConfiguration configuration) {
    return SynchronousFuture<_PersistentMemoryImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _PersistentMemoryImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: key.sourceKey,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        StringProperty('Source', sourceKey),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
    _PersistentMemoryImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(key.bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) {
    return other is _PersistentMemoryImageProvider &&
        other.sourceKey == sourceKey &&
        other.bytesFingerprint == bytesFingerprint;
  }

  @override
  int get hashCode => Object.hash(
        sourceKey,
        bytesFingerprint,
      );
}
