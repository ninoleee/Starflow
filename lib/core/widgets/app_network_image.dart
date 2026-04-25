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

class _AppNetworkImageState extends ConsumerState<AppNetworkImage> {
  Future<Uint8List>? _resolvedSvgBytesFuture;
  Future<ImageProvider<Object>>? _resolvedRasterProviderFuture;
  int _activeCandidateIndex = 0;
  bool _candidateAdvanceScheduled = false;

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
      _resetCandidateResolution();
    }
  }

  void _resetCandidateResolution({bool resetCandidateIndex = true}) {
    if (resetCandidateIndex) {
      _activeCandidateIndex = 0;
    }
    _candidateAdvanceScheduled = false;
    _resolvedSvgBytesFuture = null;
    _resolvedRasterProviderFuture = null;
  }

  void _scheduleAdvanceCandidate({
    required List<AppNetworkImageSource> candidates,
    required int candidateIndex,
  }) {
    if (_candidateAdvanceScheduled || candidateIndex >= candidates.length - 1) {
      return;
    }
    _candidateAdvanceScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _candidateAdvanceScheduled = false;
      if (!mounted) {
        return;
      }
      final latestCandidates = _buildCandidateSources();
      final safeIndex =
          _activeCandidateIndex.clamp(0, latestCandidates.length - 1);
      if (safeIndex >= latestCandidates.length - 1) {
        return;
      }
      setState(() {
        _activeCandidateIndex = safeIndex + 1;
        _resetCandidateResolution(resetCandidateIndex: false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final backgroundImageLoadingSuspended =
        ref.watch(backgroundImageLoadingSuspendedProvider);
    final candidates = _buildCandidateSources();
    if (candidates.isEmpty) {
      return _buildError(
        context,
        StateError('Image URL is empty.'),
      );
    }

    if (backgroundImageLoadingSuspended) {
      return _buildLoading(context);
    }

    final candidateIndex =
        _activeCandidateIndex.clamp(0, candidates.length - 1);
    final candidate = candidates[candidateIndex];
    if (_urlLooksLikeSvg(candidate.url)) {
      return _buildSvgCandidate(
        context,
        candidate: candidate,
        candidates: candidates,
        candidateIndex: candidateIndex,
      );
    }

    return _buildRasterCandidate(
      context,
      candidate: candidate,
      candidates: candidates,
      candidateIndex: candidateIndex,
    );
  }

  Widget _buildSvgCandidate(
    BuildContext context, {
    required AppNetworkImageSource candidate,
    required List<AppNetworkImageSource> candidates,
    required int candidateIndex,
  }) {
    if (candidate.cachePolicy == AppNetworkImageCachePolicy.networkOnly) {
      return SvgPicture.network(
        candidate.url,
        headers: candidate.headers.isEmpty ? null : candidate.headers,
        width: widget.width,
        height: widget.height,
        fit: widget.fit ?? BoxFit.contain,
        alignment: widget.alignment,
        placeholderBuilder: (context) => _buildLoading(context),
        errorBuilder: (context, error, stackTrace) {
          return _buildCandidateFailure(
            context,
            error,
            stackTrace,
            candidates: candidates,
            candidateIndex: candidateIndex,
          );
        },
      );
    }

    _resolvedSvgBytesFuture ??= persistentImageCache.load(
      candidate.url,
      headers: candidate.headers,
      persist: true,
    );
    final resolvedSvgBytesFuture = _resolvedSvgBytesFuture!;
    return FutureBuilder<Uint8List>(
      future: resolvedSvgBytesFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildCandidateFailure(
            context,
            snapshot.error!,
            snapshot.stackTrace,
            candidates: candidates,
            candidateIndex: candidateIndex,
          );
        }

        final bytes = snapshot.data;
        if (bytes == null) {
          return _buildLoading(context);
        }

        return SvgPicture.memory(
          bytes,
          width: widget.width,
          height: widget.height,
          fit: widget.fit ?? BoxFit.contain,
          alignment: widget.alignment,
          placeholderBuilder: (context) => _buildLoading(context),
        );
      },
    );
  }

  Widget _buildRasterCandidate(
    BuildContext context, {
    required AppNetworkImageSource candidate,
    required List<AppNetworkImageSource> candidates,
    required int candidateIndex,
  }) {
    if (candidate.cachePolicy == AppNetworkImageCachePolicy.networkOnly) {
      return _buildRasterImage(
        context,
        _networkRasterProvider(candidate),
        candidates: candidates,
        candidateIndex: candidateIndex,
      );
    }

    _resolvedRasterProviderFuture ??=
        persistentImageCache.resolveRasterProvider(
      candidate.url,
      headers: candidate.headers,
      persist: true,
    );
    final resolvedRasterProviderFuture = _resolvedRasterProviderFuture!;
    return FutureBuilder<ImageProvider<Object>>(
      future: resolvedRasterProviderFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildCandidateFailure(
            context,
            snapshot.error!,
            snapshot.stackTrace,
            candidates: candidates,
            candidateIndex: candidateIndex,
          );
        }

        final provider = snapshot.data;
        if (provider == null) {
          return _buildLoading(context);
        }

        return _buildRasterImage(
          context,
          provider,
          candidates: candidates,
          candidateIndex: candidateIndex,
        );
      },
    );
  }

  Widget _buildRasterImage(
    BuildContext context,
    ImageProvider<Object> provider, {
    required List<AppNetworkImageSource> candidates,
    required int candidateIndex,
  }) {
    final rasterImageProvider = ResizeImage.resizeIfNeeded(
      widget.cacheWidth,
      widget.cacheHeight,
      provider,
    );
    return Image(
      image: rasterImageProvider,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      filterQuality: widget.filterQuality,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return _buildLoading(context);
      },
      errorBuilder: (context, error, stackTrace) {
        return _buildCandidateFailure(
          context,
          error,
          stackTrace,
          candidates: candidates,
          candidateIndex: candidateIndex,
        );
      },
    );
  }

  ImageProvider<Object> _networkRasterProvider(
      AppNetworkImageSource candidate) {
    return NetworkImage(
      candidate.url,
      headers: candidate.headers.isEmpty ? null : candidate.headers,
    );
  }

  Widget _buildCandidateFailure(
    BuildContext context,
    Object error,
    StackTrace? stackTrace, {
    required List<AppNetworkImageSource> candidates,
    required int candidateIndex,
  }) {
    if (candidateIndex < candidates.length - 1) {
      _scheduleAdvanceCandidate(
        candidates: candidates,
        candidateIndex: candidateIndex,
      );
      return _buildLoading(context);
    }
    return _buildError(context, error, stackTrace);
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

  Widget _buildError(
    BuildContext context,
    Object error, [
    StackTrace? stackTrace,
  ]) {
    return widget.errorBuilder?.call(context, error, stackTrace) ??
        const SizedBox.shrink();
  }
}

bool _sameHeaders(Map<String, String>? left, Map<String, String>? right) {
  final normalizedLeft =
      left == null || left.isEmpty ? null : Map<String, String>.from(left);
  final normalizedRight =
      right == null || right.isEmpty ? null : Map<String, String>.from(right);
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

bool _urlLooksLikeSvg(String url) {
  final trimmedUrl = url.trim();
  if (trimmedUrl.isEmpty) {
    return false;
  }
  final normalized = trimmedUrl.toLowerCase();
  if (normalized.startsWith('data:image/svg+xml')) {
    return true;
  }
  final uri = Uri.tryParse(trimmedUrl);
  final path = (uri?.path ?? trimmedUrl).toLowerCase();
  return path.endsWith('.svg') || path.endsWith('.svgz');
}
