import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:starflow/core/storage/persistent_image_cache.dart';
import 'package:starflow/core/utils/network_image_headers.dart';

typedef AppNetworkImageErrorBuilder =
    Widget Function(BuildContext context, Object error, StackTrace? stackTrace);
typedef AppNetworkImageLoadingBuilder =
    Widget Function(BuildContext context);

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
    this.filterQuality = FilterQuality.medium,
    this.errorBuilder,
    this.loadingBuilder,
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

  @override
  State<AppNetworkImage> createState() => _AppNetworkImageState();
}

class _AppNetworkImageState extends State<AppNetworkImage> {
  Future<Uint8List>? _manualImageFuture;

  @override
  void initState() {
    super.initState();
    _manualImageFuture = _resolveManualImageFuture();
  }

  @override
  void didUpdateWidget(covariant AppNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.headers != widget.headers) {
      _manualImageFuture = _resolveManualImageFuture();
    }
  }

  Future<Uint8List>? _resolveManualImageFuture() {
    final url = widget.url.trim();
    if (url.isEmpty) {
      return null;
    }
    final headers = (widget.headers?.isNotEmpty ?? false)
        ? widget.headers
        : networkImageHeadersForUrl(url);
    return persistentImageCache.load(url, headers: headers);
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

    return FutureBuilder<Uint8List>(
      future: _manualImageFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildError(context, snapshot.error!, snapshot.stackTrace);
        }

        final bytes = snapshot.data;
        if (bytes == null) {
          return _buildLoading(context);
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

  Widget _buildLoading(BuildContext context) {
    return widget.loadingBuilder?.call(context) ?? const SizedBox.shrink();
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
