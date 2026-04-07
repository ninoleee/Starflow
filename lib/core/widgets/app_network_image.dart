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

class AppNetworkImageSource {
  const AppNetworkImageSource({
    required this.url,
    this.headers = const {},
  });

  final String url;
  final Map<String, String> headers;
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
  ConsumerState<AppNetworkImage> createState() => _AppNetworkImageState();
}

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
    if (oldWidget.url != widget.url ||
        oldWidget.headers != widget.headers ||
        !_sameImageSources(
          oldWidget.fallbackSources,
          widget.fallbackSources,
        )) {
      _refreshResolvedImageFuture(force: true);
    }
  }

  void _refreshResolvedImageFuture({bool force = false}) {
    final backgroundWorkSuspended = ref.read(backgroundWorkSuspendedProvider);
    if (backgroundWorkSuspended) {
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
    final backgroundWorkSuspended = ref.watch(backgroundWorkSuspendedProvider);
    final trimmedUrl = widget.url.trim();
    if (trimmedUrl.isEmpty) {
      return _buildError(
        context,
        StateError('Image URL is empty.'),
      );
    }

    if (backgroundWorkSuspended) {
      return _buildLoading(context);
    }

    _resolvedImageFuture ??= _resolveImageFuture();

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
