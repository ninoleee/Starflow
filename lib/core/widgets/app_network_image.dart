import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/utils/douban_cover_debug.dart';
import 'package:starflow/core/utils/network_image_headers.dart';

typedef AppNetworkImageErrorBuilder =
    Widget Function(BuildContext context, Object error, StackTrace? stackTrace);
typedef AppNetworkImageLoadingBuilder =
    Widget Function(BuildContext context);

class AppNetworkImage extends StatefulWidget {
  const AppNetworkImage(
    this.url, {
    super.key,
    this.debugTitle = '',
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
  final String debugTitle;
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
    if (!requiresManualNetworkImageFetch(url)) {
      return null;
    }

    final headers = widget.headers ?? networkImageHeadersForUrl(url);
    return _ManualNetworkImageCache.instance.load(url, headers);
  }

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = widget.url.trim();
    final headers = widget.headers ?? networkImageHeadersForUrl(trimmedUrl);
    if (trimmedUrl.isEmpty) {
      return _buildError(
        context,
        StateError('Image URL is empty.'),
      );
    }

    final isDoubanImage = isDoubanImageUrl(trimmedUrl);
    if (isDoubanImage) {
      debugLogDoubanCover(
        'image-request',
        title: widget.debugTitle,
        url: trimmedUrl,
        detail: headers == null
            ? 'headers=none'
            : 'headers=${headers.keys.join(',')}',
      );
    }

    if (!requiresManualNetworkImageFetch(trimmedUrl)) {
      return Image.network(
        trimmedUrl,
        headers: headers,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        alignment: widget.alignment,
        cacheWidth: widget.cacheWidth,
        cacheHeight: widget.cacheHeight,
        filterQuality: widget.filterQuality,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            if (isDoubanImage) {
              debugLogDoubanCover(
                'image-success',
                title: widget.debugTitle,
                url: trimmedUrl,
                detail: 'network-image',
              );
            }
            return child;
          }
          return _buildLoading(context);
        },
        errorBuilder: (context, error, stackTrace) {
          if (isDoubanImage) {
            debugLogDoubanCover(
              'image-fail',
              title: widget.debugTitle,
              url: trimmedUrl,
              detail: '$error',
            );
          }
          return _buildError(context, error, stackTrace);
        },
      );
    }

    return FutureBuilder<Uint8List>(
      future: _manualImageFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (isDoubanImage) {
            debugLogDoubanCover(
              'image-fail',
              title: widget.debugTitle,
              url: trimmedUrl,
              detail: '${snapshot.error}',
            );
          }
          return _buildError(context, snapshot.error!, snapshot.stackTrace);
        }

        final bytes = snapshot.data;
        if (bytes == null) {
          return _buildLoading(context);
        }

        if (isDoubanImage) {
          debugLogDoubanCover(
            'image-success',
            title: widget.debugTitle,
            url: trimmedUrl,
            detail: 'manual-bytes=${bytes.length}',
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

class _ManualNetworkImageCache {
  _ManualNetworkImageCache._();

  static final _ManualNetworkImageCache instance = _ManualNetworkImageCache._();

  static final http.Client _client = http.Client();
  static const int _maxEntries = 96;

  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  final Map<String, Future<Uint8List>> _inflight = <String, Future<Uint8List>>{};

  Future<Uint8List> load(String url, Map<String, String>? headers) {
    final trimmedUrl = url.trim();
    final cached = _cache.remove(trimmedUrl);
    if (cached != null) {
      _cache[trimmedUrl] = cached;
      return SynchronousFuture<Uint8List>(cached);
    }

    final inflight = _inflight[trimmedUrl];
    if (inflight != null) {
      return inflight;
    }

    final future = _fetch(trimmedUrl, headers);
    _inflight[trimmedUrl] = future;
    future.whenComplete(() {
      _inflight.remove(trimmedUrl);
    });
    return future;
  }

  Future<Uint8List> _fetch(String url, Map<String, String>? headers) async {
    final uri = Uri.parse(url);
    final response = await _client.get(uri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'HTTP request failed, statusCode: ${response.statusCode}, $url',
      );
    }

    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      throw StateError('Image response body is empty: $url');
    }

    _cache.remove(url);
    _cache[url] = bytes;
    if (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    return bytes;
  }
}
