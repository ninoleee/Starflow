import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:starflow/core/storage/persistent_image_cache.dart';
import 'package:starflow/core/utils/network_image_headers.dart';

typedef AppNetworkImageErrorBuilder = Widget Function(
    BuildContext context, Object error, StackTrace? stackTrace);
typedef AppNetworkImageLoadingBuilder = Widget Function(BuildContext context);

class AppNetworkImageSource {
  const AppNetworkImageSource({
    required this.url,
    this.headers = const {},
  });

  final String url;
  final Map<String, String> headers;
}

class AppNetworkImage extends StatefulWidget {
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

  @override
  State<AppNetworkImage> createState() => _AppNetworkImageState();
}

class _AppNetworkImageState extends State<AppNetworkImage> {
  Future<_ResolvedImageContent>? _resolvedImageFuture;
  bool _hasLoggedImageInfo = false;

  @override
  void initState() {
    super.initState();
    _resolvedImageFuture = _resolveImageFuture();
  }

  @override
  void didUpdateWidget(covariant AppNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.headers != widget.headers ||
        !_sameImageSources(
          oldWidget.fallbackSources,
          widget.fallbackSources,
        )) {
      _resolvedImageFuture = _resolveImageFuture();
      _hasLoggedImageInfo = false;
    }
  }

  Future<_ResolvedImageContent>? _resolveImageFuture() {
    final candidates = _buildCandidateSources();
    if (candidates.isEmpty) {
      return null;
    }
    return _loadAndAnalyze(candidates);
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
        );
        return _ResolvedImageContent(
          bytes: bytes,
          isSvg: _looksLikeSvg(candidate.url, bytes),
          sourceUrl: candidate.url,
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
    final trimmedUrl = widget.url.trim();
    if (trimmedUrl.isEmpty) {
      return _buildError(
        context,
        StateError('Image URL is empty.'),
      );
    }

    return FutureBuilder<_ResolvedImageContent>(
      future: _resolvedImageFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildError(context, snapshot.error!, snapshot.stackTrace);
        }

        final resolved = snapshot.data;
        if (resolved == null) {
          return _buildLoading(context);
        }

        final bytes = resolved.bytes;
        _logImageInfoIfNeeded(bytes);
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
        return Image.memory(
          bytes,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          alignment: widget.alignment,
          cacheWidth: widget.cacheWidth,
          cacheHeight: widget.cacheHeight,
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

    void add(String url, Map<String, String>? headers) {
      final trimmedUrl = url.trim();
      if (trimmedUrl.isEmpty || !seen.add(trimmedUrl)) {
        return;
      }
      candidates.add(
        AppNetworkImageSource(
          url: trimmedUrl,
          headers: (headers?.isNotEmpty ?? false)
              ? headers!
              : (networkImageHeadersForUrl(trimmedUrl) ??
                    const <String, String>{}),
        ),
      );
    }

    add(widget.url, widget.headers);
    for (final source in widget.fallbackSources) {
      add(source.url, source.headers);
    }
    return candidates;
  }

  Widget _buildError(
    BuildContext context,
    Object error, [
    StackTrace? stackTrace,
  ]) {
    return widget.errorBuilder?.call(context, error, stackTrace) ??
        const SizedBox.shrink();
  }

  void _logImageInfoIfNeeded(Uint8List bytes) {
    if (!kDebugMode ||
        _hasLoggedImageInfo ||
        widget.debugLabel.trim().isEmpty ||
        _looksLikeSvg(widget.url, bytes)) {
      return;
    }
    _hasLoggedImageInfo = true;
    unawaited(_decodeAndLogImageInfo(bytes));
  }

  Future<void> _decodeAndLogImageInfo(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      debugPrint(
        '[ImageInfo] ${widget.debugLabel} '
        'source=${frame.image.width}x${frame.image.height} '
        'target=${widget.width?.toStringAsFixed(1) ?? 'auto'}x'
        '${widget.height?.toStringAsFixed(1) ?? 'auto'} '
        'fit=${widget.fit}',
      );
      frame.image.dispose();
      codec.dispose();
    } catch (error, stackTrace) {
      debugPrint(
        '[ImageInfo] ${widget.debugLabel} decode_failed=$error\n$stackTrace',
      );
    }
  }
}

class _ResolvedImageContent {
  const _ResolvedImageContent({
    required this.bytes,
    required this.isSvg,
    required this.sourceUrl,
  });

  final Uint8List bytes;
  final bool isSvg;
  final String sourceUrl;
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
        !mapEquals(leftSource.headers, rightSource.headers)) {
      return false;
    }
  }
  return true;
}
