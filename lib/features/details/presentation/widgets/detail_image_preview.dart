import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/tv_remote_input.dart';

const int detailGalleryImageDecodeWidth = 804;
const int detailGalleryImageDecodeHeight = 452;
const int detailPreviewImageDecodeWidth = 2048;

void evictDetailImageMemory(
  ImageProvider<Object> provider, {
  bool evictSource = true,
  bool evictThumbnail = true,
  bool evictPreview = true,
}) {
  void evictResized({required int width, required int? height}) {
    // Clear both keys because the gallery and preview use different resize
    // policies, and older builds may have left either one in ImageCache.
    for (final policy in const [
      ResizeImagePolicy.exact,
      ResizeImagePolicy.fit,
    ]) {
      unawaited(
        ResizeImage(
          provider,
          width: width,
          height: height,
          policy: policy,
        ).evict(),
      );
    }
  }

  if (evictThumbnail) {
    evictResized(
      width: detailGalleryImageDecodeWidth,
      height: detailGalleryImageDecodeHeight,
    );
  }
  if (evictPreview) {
    evictResized(
      width: detailPreviewImageDecodeWidth,
      height: null,
    );
    evictResized(
      width: detailPreviewImageDecodeWidth,
      height: detailPreviewImageDecodeWidth,
    );
  }
  if (evictSource) {
    unawaited(provider.evict());
  }
}

class DetailImagePreview extends StatefulWidget {
  const DetailImagePreview({
    super.key,
    required this.image,
    this.initialProvider,
  });

  final AppNetworkImageSource image;
  final ImageProvider<Object>? initialProvider;

  @override
  State<DetailImagePreview> createState() => _DetailImagePreviewState();
}

class _DetailImagePreviewState extends State<DetailImagePreview>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  final _dismissOffset = ValueNotifier<Offset>(Offset.zero);
  final _viewerKey = GlobalKey();
  late final AnimationController _dismissController;
  Animation<Offset>? _dismissAnimation;
  ImageProvider<Object>? _retryProvider;
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;
  double? _imageAspectRatio;
  double? _pendingImageAspectRatio;
  Offset? _interactionStartPosition;
  final Set<int> _activePointers = <int>{};
  Offset? _tapDownPosition;
  Offset? _lastTapPosition;
  DateTime? _lastTapTime;
  bool _tapMoved = false;
  bool _dismissCandidate = false;
  bool _verticalDismiss = false;
  bool _isDismissing = false;
  bool _closeAfterDismiss = false;
  bool _closeRequested = false;
  final _closeKeys = TvRemoteKeyHandler();
  int _attempt = 0;

  static const _doubleTapScale = 2.5;
  static const _dismissThreshold = 0.2;
  static const _dismissFlickVelocity = 1000.0;

  @override
  void initState() {
    super.initState();
    _dismissController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )
      ..addListener(_handleDismissAnimationTick)
      ..addStatusListener(_handleDismissAnimationStatus);
  }

  void _observeImageProvider(ImageProvider<Object> provider) {
    final stream = provider.resolve(ImageConfiguration.empty);
    if (identical(stream, _imageStream)) {
      return;
    }
    final oldStream = _imageStream;
    final oldListener = _imageStreamListener;
    if (oldStream != null && oldListener != null) {
      oldStream.removeListener(oldListener);
    }

    final listener = ImageStreamListener((info, synchronousCall) {
      final image = info.image;
      if (image.width <= 0 || image.height <= 0) {
        return;
      }
      final aspectRatio = image.width / image.height;
      if (!mounted || _imageAspectRatio == aspectRatio) {
        return;
      }
      _pendingImageAspectRatio = aspectRatio;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _pendingImageAspectRatio != aspectRatio) {
          return;
        }
        _pendingImageAspectRatio = null;
        setState(() => _imageAspectRatio = aspectRatio);
      });
    });
    _imageStream = stream;
    _imageStreamListener = listener;
    stream.addListener(listener);
  }

  @override
  void dispose() {
    _closeKeys.dispose();
    final imageStream = _imageStream;
    final imageStreamListener = _imageStreamListener;
    if (imageStream != null && imageStreamListener != null) {
      imageStream.removeListener(imageStreamListener);
    }
    final initialProvider = widget.initialProvider;
    if (initialProvider != null) {
      evictDetailImageMemory(
        initialProvider,
        evictSource: false,
        evictThumbnail: false,
      );
    }
    final retryProvider = _retryProvider;
    if (retryProvider != null) {
      evictDetailImageMemory(retryProvider);
    }
    _dismissController.dispose();
    _dismissOffset.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _handleDismissAnimationTick() {
    final animation = _dismissAnimation;
    if (animation != null) {
      _dismissOffset.value = animation.value;
    }
  }

  void _handleDismissAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) {
      return;
    }
    final close = _closeAfterDismiss;
    _closeAfterDismiss = false;
    if (close && mounted) {
      _closePreview();
    }
  }

  void _stopDismissAnimation({bool resetOffset = false}) {
    _dismissController.stop();
    _dismissAnimation = null;
    _closeAfterDismiss = false;
    _isDismissing = false;
    if (resetOffset) {
      _dismissOffset.value = Offset.zero;
    }
  }

  void _animateDismissOffset(Offset target, {required bool close}) {
    _dismissController.stop();
    _closeAfterDismiss = close;
    _isDismissing = close;
    _dismissAnimation = Tween<Offset>(
      begin: _dismissOffset.value,
      end: target,
    ).animate(
      CurvedAnimation(
        parent: _dismissController,
        curve: Curves.easeOutCubic,
      ),
    );
    _dismissController.forward(from: 0);
  }

  void _handleInteractionStart(ScaleStartDetails details) {
    _stopDismissAnimation(resetOffset: true);
    _interactionStartPosition = details.localFocalPoint;
    _dismissCandidate = _transform.value.getMaxScaleOnAxis() <= 1.01;
    _verticalDismiss = false;
  }

  void _handleInteractionUpdate(ScaleUpdateDetails details) {
    if (!_dismissCandidate || _isDismissing) {
      return;
    }
    if (details.pointerCount > 1 ||
        _transform.value.getMaxScaleOnAxis() > 1.01) {
      _dismissCandidate = false;
      _verticalDismiss = false;
      _dismissOffset.value = Offset.zero;
      return;
    }

    final start = _interactionStartPosition;
    if (start == null) {
      return;
    }
    final delta = details.localFocalPoint - start;
    if (!_verticalDismiss && delta.distance >= 8) {
      _verticalDismiss = delta.dy > delta.dx.abs();
    }
    if (!_verticalDismiss) {
      return;
    }

    _dismissOffset.value = Offset(0, delta.dy.clamp(0.0, double.infinity));
  }

  void _handleInteractionEnd(ScaleEndDetails details) {
    final offset = _dismissOffset.value;
    final height = MediaQuery.sizeOf(context).height;
    final shouldClose = _verticalDismiss &&
        (offset.dy >= height * _dismissThreshold ||
            (details.velocity.pixelsPerSecond.dy >= _dismissFlickVelocity &&
                offset.dy >= 32));
    _dismissCandidate = false;
    _verticalDismiss = false;
    _interactionStartPosition = null;
    if (shouldClose) {
      _animateDismissOffset(Offset(0, height), close: true);
    } else if (offset != Offset.zero) {
      _animateDismissOffset(Offset.zero, close: false);
    }
  }

  void _handleDoubleTap(Offset focalPoint) {
    _stopDismissAnimation(resetOffset: true);
    final currentScale = _transform.value.getMaxScaleOnAxis();
    if (currentScale > 1.01) {
      _transform.value = Matrix4.identity();
      return;
    }

    final focalPointScene = _transform.toScene(focalPoint);
    _transform.value = Matrix4.identity()
      ..translateByDouble(focalPointScene.dx, focalPointScene.dy, 0, 1)
      ..scaleByDouble(
        _doubleTapScale,
        _doubleTapScale,
        _doubleTapScale,
        1,
      )
      ..translateByDouble(-focalPointScene.dx, -focalPointScene.dy, 0, 1);
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length == 1) {
      _tapDownPosition = event.localPosition;
      _tapMoved = false;
    } else {
      _tapDownPosition = null;
      _tapMoved = true;
      _lastTapPosition = null;
      _lastTapTime = null;
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final start = _tapDownPosition;
    if (_activePointers.length != 1 || start == null) {
      return;
    }
    if ((event.localPosition - start).distance > 12) {
      _tapMoved = true;
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.isNotEmpty || _tapDownPosition == null) {
      return;
    }
    final tapPosition = event.localPosition;
    final tapTime = DateTime.now();
    if (!_tapMoved &&
        _imageAspectRatio != null &&
        _transform.value.getMaxScaleOnAxis() <= 1.01 &&
        !_displayedImageRect().contains(tapPosition)) {
      _tapDownPosition = null;
      _tapMoved = false;
      _lastTapPosition = null;
      _lastTapTime = null;
      _closePreview();
      return;
    }
    final isDoubleTap = !_tapMoved &&
        _lastTapTime != null &&
        tapTime.difference(_lastTapTime!) <=
            const Duration(milliseconds: 300) &&
        (tapPosition - _lastTapPosition!).distance <= 48;
    _tapDownPosition = null;
    _tapMoved = false;
    if (isDoubleTap) {
      _lastTapTime = null;
      _lastTapPosition = null;
      _handleDoubleTap(tapPosition);
    } else {
      _lastTapTime = tapTime;
      _lastTapPosition = tapPosition;
    }
  }

  Rect _displayedImageRect() {
    final renderObject = _viewerKey.currentContext?.findRenderObject();
    final viewport = renderObject is RenderBox ? renderObject.size : Size.zero;
    final aspectRatio = _imageAspectRatio;
    if (viewport.isEmpty || aspectRatio == null || aspectRatio <= 0) {
      return Offset.zero & viewport;
    }

    final viewportAspectRatio = viewport.width / viewport.height;
    final imageSize = aspectRatio > viewportAspectRatio
        ? Size(viewport.width, viewport.width / aspectRatio)
        : Size(viewport.height * aspectRatio, viewport.height);
    return Alignment.center.inscribe(imageSize, Offset.zero & viewport);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) {
      _tapDownPosition = null;
      _tapMoved = false;
      _lastTapTime = null;
      _lastTapPosition = null;
    }
  }

  void _closePreview() {
    if (_closeRequested ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    _closeRequested = true;
    Navigator.of(context).pop();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final closesPreview =
        tvBackKeys.contains(key) || tvConfirmKeys.contains(key);
    if (!closesPreview) {
      return KeyEventResult.ignored;
    }
    return _closeKeys.handle(event, onPressed: _closePreview);
  }

  Widget _loading(BuildContext context) => const Center(
        child: CircularProgressIndicator(),
      );

  Widget _error(BuildContext context, Object error, StackTrace? stackTrace) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('图片加载失败'),
          const SizedBox(height: 12),
          IconButton(
            tooltip: '重新加载',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {
              _attempt++;
              _imageAspectRatio = null;
              _pendingImageAspectRatio = null;
              _transform.value = Matrix4.identity();
            }),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = _attempt == 0 ? widget.initialProvider : null;
    if (provider != null) {
      _observeImageProvider(
        ResizeImage(provider, width: detailPreviewImageDecodeWidth),
      );
    }
    final image = provider == null
        ? AppNetworkImage(
            widget.image.url,
            key: ValueKey(_attempt),
            headers: widget.image.headers,
            cachePolicy: widget.image.cachePolicy,
            cacheWidth: detailPreviewImageDecodeWidth,
            fit: BoxFit.contain,
            throttleOnTelevision: false,
            onImageReady: (provider) {
              _retryProvider = provider;
              _observeImageProvider(
                ResizeImage(provider, width: detailPreviewImageDecodeWidth),
              );
            },
            loadingBuilder: _loading,
            errorBuilder: _error,
          )
        : Image(
            image: ResizeImage(
              provider,
              width: detailPreviewImageDecodeWidth,
            ),
            fit: BoxFit.contain,
            frameBuilder: (context, child, frame, synchronous) =>
                synchronous || frame != null ? child : _loading(context),
            // A preview failure must not evict the gallery's working source.
            errorBuilder: _error,
          );
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            _closePreview();
          }
        },
        child: SafeArea(
          child: Focus(
            autofocus: true,
            skipTraversal: true,
            onKeyEvent: _handleKeyEvent,
            child: AnimatedBuilder(
              animation: _dismissOffset,
              builder: (context, child) {
                final progress = (_dismissOffset.value.dy /
                        MediaQuery.sizeOf(context).height)
                    .clamp(0.0, 1.0)
                    .toDouble();
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: Colors.black.withValues(
                        alpha: 1 - progress * 0.78,
                      ),
                    ),
                    Positioned.fill(
                      child: Transform.translate(
                        offset: _dismissOffset.value,
                        child: child,
                      ),
                    ),
                  ],
                );
              },
              child: Listener(
                key: _viewerKey,
                onPointerDown: _handlePointerDown,
                onPointerMove: _handlePointerMove,
                onPointerUp: _handlePointerUp,
                onPointerCancel: _handlePointerCancel,
                child: InteractiveViewer(
                  transformationController: _transform,
                  minScale: 1,
                  maxScale: 5,
                  onInteractionStart: _handleInteractionStart,
                  onInteractionUpdate: _handleInteractionUpdate,
                  onInteractionEnd: _handleInteractionEnd,
                  child: SizedBox.expand(child: image),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
