import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/scheduling/queue_wait_diagnostics.dart';
import 'package:starflow/core/storage/persistent_image_cache.dart';
import 'package:starflow/core/utils/network_image_headers.dart';

typedef AppNetworkImageErrorBuilder = Widget Function(
    BuildContext context, Object error, StackTrace? stackTrace);
typedef AppNetworkImageLoadingBuilder = Widget Function(BuildContext context);

const int _kTvRasterImageLoadConcurrency = 4;
const Duration _kTvRasterImagePermitLease = Duration(seconds: 8);
const Duration _kTvRasterImageWaitWarningThreshold = Duration(seconds: 4);
const List<Duration> _kImageLoadRetryDelays = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 4),
  Duration(seconds: 12),
];

final _tvRasterImageLoadGate =
    _TvRasterImageLoadGate(_kTvRasterImageLoadConcurrency);

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
    this.throttleOnTelevision = true,
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
  final bool throttleOnTelevision;

  @override
  ConsumerState<AppNetworkImage> createState() => _AppNetworkImageState();
}

class _AppNetworkImageState extends ConsumerState<AppNetworkImage> {
  Future<Uint8List>? _resolvedSvgBytesFuture;
  Future<ImageProvider<Object>>? _resolvedRasterProviderFuture;
  _TvRasterImageLoadRequest? _tvRasterLoadRequest;
  _TvRasterImageLoadPermit? _tvRasterLoadPermit;
  Timer? _tvRasterLoadPermitTimeout;
  String? _tvRasterLoadIdentity;
  bool _tvRasterLoadSettled = false;
  int _activeCandidateIndex = 0;
  bool _candidateAdvanceScheduled = false;
  Timer? _imageRetryTimer;
  String? _imageRetryIdentity;
  int _imageRetryAttempt = 0;
  bool _imageRetryExhaustedLogged = false;

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
      _resetCandidateResolution(resetRetryState: true);
    }
  }

  void _resetCandidateResolution({
    bool resetCandidateIndex = true,
    bool resetRetryState = false,
  }) {
    if (resetCandidateIndex) {
      _activeCandidateIndex = 0;
    }
    _candidateAdvanceScheduled = false;
    _resolvedSvgBytesFuture = null;
    _resolvedRasterProviderFuture = null;
    _resetTvRasterLoadThrottle();
    if (resetRetryState) {
      _resetImageRetryState();
    }
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
        _resetCandidateResolution(
          resetCandidateIndex: false,
          resetRetryState: false,
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final throttleRasterLoads = widget.throttleOnTelevision &&
        _shouldThrottleTvRasterLoads(ref.watch(isTelevisionProvider));
    final candidates = _buildCandidateSources();
    if (candidates.isEmpty) {
      return _buildError(
        context,
        StateError('Image URL is empty.'),
      );
    }

    final candidateIndex =
        _activeCandidateIndex.clamp(0, candidates.length - 1);
    final candidate = candidates[candidateIndex];
    if (_urlLooksLikeSvg(candidate.url)) {
      _resetTvRasterLoadThrottle();
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
      throttleRasterLoads: throttleRasterLoads,
    );
  }

  @override
  void dispose() {
    _imageRetryTimer?.cancel();
    _imageRetryTimer = null;
    _resetTvRasterLoadThrottle();
    super.dispose();
  }

  Widget _buildSvgCandidate(
    BuildContext context, {
    required AppNetworkImageSource candidate,
    required List<AppNetworkImageSource> candidates,
    required int candidateIndex,
  }) {
    _resolvedSvgBytesFuture ??= persistentImageCache.load(
      candidate.url,
      headers: candidate.headers,
      persist: candidate.cachePolicy == AppNetworkImageCachePolicy.persistent,
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
          errorBuilder: (context, error, stackTrace) {
            if (candidate.cachePolicy ==
                AppNetworkImageCachePolicy.persistent) {
              unawaited(
                persistentImageCache.evict(
                  candidate.url,
                  headers: candidate.headers,
                ),
              );
            }
            return _buildCandidateFailure(
              context,
              error,
              stackTrace,
              candidates: candidates,
              candidateIndex: candidateIndex,
            );
          },
        );
      },
    );
  }

  Widget _buildRasterCandidate(
    BuildContext context, {
    required AppNetworkImageSource candidate,
    required List<AppNetworkImageSource> candidates,
    required int candidateIndex,
    required bool throttleRasterLoads,
  }) {
    if (!throttleRasterLoads) {
      _resetTvRasterLoadThrottle();
      return _buildResolvedRasterCandidate(
        context,
        candidate: candidate,
        candidates: candidates,
        candidateIndex: candidateIndex,
      );
    }

    return _buildThrottledRasterCandidate(
      context,
      candidate: candidate,
      candidates: candidates,
      candidateIndex: candidateIndex,
    );
  }

  Widget _buildThrottledRasterCandidate(
    BuildContext context, {
    required AppNetworkImageSource candidate,
    required List<AppNetworkImageSource> candidates,
    required int candidateIndex,
  }) {
    final loadIdentity = _buildRasterLoadIdentity(candidate);
    _ensureTvRasterLoadIdentity(loadIdentity);
    if (_tvRasterLoadSettled) {
      return _buildResolvedRasterCandidate(
        context,
        candidate: candidate,
        candidates: candidates,
        candidateIndex: candidateIndex,
      );
    }

    final request = _tvRasterLoadRequest ??= _tvRasterImageLoadGate.request();
    return FutureBuilder<_TvRasterImageLoadPermit>(
      future: request.future,
      builder: (context, snapshot) {
        if (_tvRasterLoadIdentity != loadIdentity) {
          return _buildLoading(context);
        }
        if (snapshot.hasError) {
          return _buildLoading(context);
        }

        final permit = snapshot.data;
        if (permit == null) {
          return _buildLoading(context);
        }
        if (permit.isReleased) {
          _tvRasterLoadSettled = true;
          _tvRasterLoadRequest = null;
          return _buildResolvedRasterCandidate(
            context,
            candidate: candidate,
            candidates: candidates,
            candidateIndex: candidateIndex,
          );
        }

        _trackTvRasterLoadPermit(permit);
        return _buildResolvedRasterCandidate(
          context,
          candidate: candidate,
          candidates: candidates,
          candidateIndex: candidateIndex,
          onLoadSettled: _markTvRasterLoadSettled,
        );
      },
    );
  }

  Widget _buildResolvedRasterCandidate(
    BuildContext context, {
    required AppNetworkImageSource candidate,
    required List<AppNetworkImageSource> candidates,
    required int candidateIndex,
    VoidCallback? onLoadSettled,
  }) {
    _resolvedRasterProviderFuture ??=
        candidate.cachePolicy == AppNetworkImageCachePolicy.networkOnly
            ? persistentImageCache
                .load(
                  candidate.url,
                  headers: candidate.headers,
                  persist: false,
                )
                .then<ImageProvider<Object>>((bytes) => MemoryImage(bytes))
            : persistentImageCache.resolveRasterProvider(
                candidate.url,
                headers: candidate.headers,
                persist: true,
              );
    final resolvedRasterProviderFuture = _resolvedRasterProviderFuture!;
    return FutureBuilder<ImageProvider<Object>>(
      future: resolvedRasterProviderFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          onLoadSettled?.call();
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
          candidate: candidate,
          candidates: candidates,
          candidateIndex: candidateIndex,
          onLoadSettled: onLoadSettled,
        );
      },
    );
  }

  Widget _buildRasterImage(
    BuildContext context,
    ImageProvider<Object> provider, {
    required AppNetworkImageSource candidate,
    required List<AppNetworkImageSource> candidates,
    required int candidateIndex,
    VoidCallback? onLoadSettled,
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
          onLoadSettled?.call();
          _markImageLoadSucceeded();
          return child;
        }
        return _buildLoading(context);
      },
      errorBuilder: (context, error, stackTrace) {
        onLoadSettled?.call();
        unawaited(rasterImageProvider.evict());
        if (candidate.cachePolicy == AppNetworkImageCachePolicy.persistent) {
          unawaited(
            persistentImageCache.evict(
              candidate.url,
              headers: candidate.headers,
            ),
          );
        }
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

  void _trackTvRasterLoadPermit(_TvRasterImageLoadPermit permit) {
    if (identical(_tvRasterLoadPermit, permit)) {
      return;
    }
    _tvRasterLoadPermitTimeout?.cancel();
    _tvRasterLoadPermit = permit;
    _tvRasterLoadPermitTimeout = Timer(const Duration(seconds: 4), () {
      _markTvRasterLoadSettled();
    });
  }

  void _ensureTvRasterLoadIdentity(String loadIdentity) {
    if (_tvRasterLoadIdentity == loadIdentity) {
      return;
    }
    _resetTvRasterLoadThrottle();
    _tvRasterLoadIdentity = loadIdentity;
  }

  void _markTvRasterLoadSettled() {
    if (_tvRasterLoadSettled) {
      return;
    }
    _tvRasterLoadSettled = true;
    _tvRasterLoadPermitTimeout?.cancel();
    _tvRasterLoadPermitTimeout = null;
    _tvRasterLoadPermit?.release();
    _tvRasterLoadPermit = null;
    _tvRasterLoadRequest = null;
  }

  void _resetTvRasterLoadThrottle() {
    _tvRasterLoadRequest?.cancel();
    _tvRasterLoadRequest = null;
    _tvRasterLoadPermitTimeout?.cancel();
    _tvRasterLoadPermitTimeout = null;
    _tvRasterLoadPermit?.release();
    _tvRasterLoadPermit = null;
    _tvRasterLoadIdentity = null;
    _tvRasterLoadSettled = false;
  }

  String _buildRasterLoadIdentity(AppNetworkImageSource candidate) {
    final buffer = StringBuffer(
      _buildSourceIdentity(
        candidate.url,
        candidate.headers,
        cachePolicy: candidate.cachePolicy,
      ),
    )
      ..write('|')
      ..write(widget.cacheWidth ?? '')
      ..write('x')
      ..write(widget.cacheHeight ?? '');
    return buffer.toString();
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
    if (_scheduleImageRetry(candidates, error)) {
      return _buildLoading(context);
    }
    return _buildError(context, error, stackTrace);
  }

  bool _scheduleImageRetry(
    List<AppNetworkImageSource> candidates,
    Object error,
  ) {
    final identity = candidates
        .map(
          (source) => _buildSourceIdentity(
            source.url,
            source.headers,
            cachePolicy: source.cachePolicy,
          ),
        )
        .join('\u0000');
    if (_imageRetryIdentity != identity) {
      _resetImageRetryState();
      _imageRetryIdentity = identity;
    }
    if (_imageRetryTimer != null) {
      return true;
    }
    if (_imageRetryAttempt >= _kImageLoadRetryDelays.length) {
      if (!_imageRetryExhaustedLogged) {
        _imageRetryExhaustedLogged = true;
        _logImageLoadFailure(
          candidates.last,
          error,
          message: 'Image load retries exhausted',
        );
      }
      return false;
    }

    if (_imageRetryAttempt == 0) {
      _logImageLoadFailure(
        candidates.last,
        error,
        message: 'Image load failed; retry scheduled',
      );
    }
    final delay = _kImageLoadRetryDelays[_imageRetryAttempt];
    _imageRetryAttempt += 1;
    _imageRetryTimer = Timer(delay, () {
      _imageRetryTimer = null;
      if (!mounted) {
        return;
      }
      final latestIdentity = _buildCandidateSources()
          .map(
            (source) => _buildSourceIdentity(
              source.url,
              source.headers,
              cachePolicy: source.cachePolicy,
            ),
          )
          .join('\u0000');
      if (latestIdentity != identity) {
        return;
      }
      setState(() {
        _activeCandidateIndex = 0;
        _candidateAdvanceScheduled = false;
        _resetCandidateResolution(
          resetCandidateIndex: false,
          resetRetryState: false,
        );
      });
    });
    return true;
  }

  void _markImageLoadSucceeded() {
    if (_imageRetryAttempt > 0) {
      appLogTrace(
        'image.load',
        'Image load recovered after retry',
        fields: <String, Object?>{
          'retryAttempt': _imageRetryAttempt,
          'debugLabel': widget.debugLabel,
        },
      );
    }
    _resetImageRetryState();
  }

  void _resetImageRetryState() {
    _imageRetryTimer?.cancel();
    _imageRetryTimer = null;
    _imageRetryIdentity = null;
    _imageRetryAttempt = 0;
    _imageRetryExhaustedLogged = false;
  }

  void _logImageLoadFailure(
    AppNetworkImageSource source,
    Object error, {
    required String message,
  }) {
    final uri = Uri.tryParse(source.url.trim());
    appLogWarning(
      'image.load',
      message,
      fields: <String, Object?>{
        'host': uri?.host ?? '',
        'cachePolicy': source.cachePolicy.name,
        'retryAttempt': _imageRetryAttempt,
        'debugLabel': widget.debugLabel,
        'errorType': error.runtimeType.toString(),
      },
    );
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

bool _shouldThrottleTvRasterLoads(AsyncValue<bool> isTelevision) {
  return isTelevision.maybeWhen(
    data: (value) => value,
    orElse: () => !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
  );
}

class _TvRasterImageLoadGate {
  _TvRasterImageLoadGate(this.maxConcurrent) {
    _waitDiagnostics = QueueWaitDiagnostics(
      category: 'image.load-gate',
      message: 'TV image load request remained queued',
      warningThreshold: _kTvRasterImageWaitWarningThreshold,
      pendingCount: () => _pending.length,
      oldestEnqueuedAt: () =>
          _pending.isEmpty ? null : _pending.first.enqueuedAt,
      snapshotFields: () => <String, Object?>{
        'activeCount': _activePermits.length,
        'maxConcurrent': maxConcurrent,
      },
    );
  }

  final int maxConcurrent;
  final Queue<_TvRasterImageLoadRequest> _pending =
      Queue<_TvRasterImageLoadRequest>();
  final Set<_TvRasterImageLoadPermit> _activePermits =
      <_TvRasterImageLoadPermit>{};
  late final QueueWaitDiagnostics _waitDiagnostics;

  _TvRasterImageLoadRequest request() {
    final request = _TvRasterImageLoadRequest._(this);
    _pending.add(request);
    _waitDiagnostics.update();
    _drain();
    return request;
  }

  void _cancel(_TvRasterImageLoadRequest request) {
    _pending.remove(request);
    _waitDiagnostics.update();
  }

  void _release(_TvRasterImageLoadPermit permit) {
    if (_activePermits.remove(permit)) {
      scheduleMicrotask(_drain);
    }
  }

  void _drain() {
    while (_activePermits.length < maxConcurrent && _pending.isNotEmpty) {
      final request = _pending.removeFirst();
      if (request._isCancelled) {
        continue;
      }
      final permit = _TvRasterImageLoadPermit._(
        this,
        lease: _kTvRasterImagePermitLease,
      );
      _activePermits.add(permit);
      request._complete(permit);
    }
    _waitDiagnostics.update();
  }

  void _handleLeaseExpired(_TvRasterImageLoadPermit permit) {
    if (!_activePermits.contains(permit)) {
      return;
    }
    appLogWarning(
      'image.load-gate',
      'TV image load permit lease expired and was released',
      fields: <String, Object?>{
        'activeCount': _activePermits.length,
        'pendingCount': _pending.length,
        'maxConcurrent': maxConcurrent,
      },
    );
    permit.release();
  }
}

class _TvRasterImageLoadRequest {
  _TvRasterImageLoadRequest._(this._gate) : enqueuedAt = DateTime.now();

  final _TvRasterImageLoadGate _gate;
  final Completer<_TvRasterImageLoadPermit> _completer =
      Completer<_TvRasterImageLoadPermit>();
  final DateTime enqueuedAt;
  _TvRasterImageLoadPermit? _permit;
  bool _isCancelled = false;

  Future<_TvRasterImageLoadPermit> get future => _completer.future;

  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    final permit = _permit;
    if (permit != null) {
      permit.release();
      _permit = null;
      return;
    }
    _gate._cancel(this);
  }

  void _complete(_TvRasterImageLoadPermit permit) {
    if (_isCancelled) {
      permit.release();
      return;
    }
    _permit = permit;
    _completer.complete(permit);
  }
}

class _TvRasterImageLoadPermit {
  _TvRasterImageLoadPermit._(
    this._gate, {
    required Duration lease,
  }) {
    _leaseTimer = Timer(lease, () => _gate._handleLeaseExpired(this));
  }

  final _TvRasterImageLoadGate _gate;
  Timer? _leaseTimer;
  bool _isReleased = false;

  bool get isReleased => _isReleased;

  void release() {
    if (_isReleased) {
      return;
    }
    _isReleased = true;
    _leaseTimer?.cancel();
    _leaseTimer = null;
    _gate._release(this);
  }
}
