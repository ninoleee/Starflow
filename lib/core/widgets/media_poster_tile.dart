import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_network_image.dart';

class MediaPosterTile extends ConsumerStatefulWidget {
  const MediaPosterTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.posterUrl,
    this.posterHeaders = const {},
    this.posterFallbackSources = const [],
    required this.onTap,
    this.onContextAction,
    this.width = 140,
    this.titleColor,
    this.subtitleColor,
    this.imageBadgeText = '',
    this.imageTopRightBadgeText = '',
    this.focusId,
    this.focusNode,
    this.autofocus = false,
    this.tvPosterFocusOutlineOnly = true,
    this.tvPosterFocusShowBorder = true,
    this.tvPosterFocusScale = 1.0,
  });

  final String title;
  final String subtitle;
  final String posterUrl;
  final Map<String, String> posterHeaders;
  final List<AppNetworkImageSource> posterFallbackSources;
  final VoidCallback onTap;
  final VoidCallback? onContextAction;
  final double? width;
  final Color? titleColor;
  final Color? subtitleColor;
  final String imageBadgeText;
  final String imageTopRightBadgeText;
  final String? focusId;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool tvPosterFocusOutlineOnly;
  final bool tvPosterFocusShowBorder;
  final double tvPosterFocusScale;

  @override
  ConsumerState<MediaPosterTile> createState() => _MediaPosterTileState();
}

class _MediaPosterTileState extends ConsumerState<MediaPosterTile> {
  final ValueNotifier<bool> _isFocusedNotifier = ValueNotifier<bool>(false);
  FocusNode? _ownedFocusNode;

  FocusNode get _effectiveFocusNode =>
      widget.focusNode ??
      (_ownedFocusNode ??= FocusNode(
          debugLabel: 'media-poster:${widget.focusId ?? widget.key}'));

  @override
  void initState() {
    super.initState();
    _effectiveFocusNode.addListener(_handleFocusChanged);
    _handleFocusChanged();
  }

  @override
  void didUpdateWidget(covariant MediaPosterTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousFocusNode = oldWidget.focusNode ?? _ownedFocusNode;
    final nextFocusNode = _effectiveFocusNode;
    if (!identical(previousFocusNode, nextFocusNode)) {
      previousFocusNode?.removeListener(_handleFocusChanged);
      nextFocusNode.addListener(_handleFocusChanged);
      _handleFocusChanged();
      if (oldWidget.focusNode == null && widget.focusNode != null) {
        _ownedFocusNode?.dispose();
        _ownedFocusNode = null;
      }
    }
  }

  void _handleFocusChanged() {
    final isFocused =
        _effectiveFocusNode.hasFocus || _effectiveFocusNode.hasPrimaryFocus;
    if (_isFocusedNotifier.value == isFocused) {
      return;
    }
    _isFocusedNotifier.value = isFocused;
  }

  @override
  void dispose() {
    final currentFocusNode = widget.focusNode ?? _ownedFocusNode;
    currentFocusNode?.removeListener(_handleFocusChanged);
    _ownedFocusNode?.dispose();
    _isFocusedNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final trimmedPoster = widget.posterUrl.trim();
    String effectivePosterUrl = trimmedPoster;
    if (effectivePosterUrl.isEmpty) {
      for (final source in widget.posterFallbackSources) {
        final trimmedFallback = source.url.trim();
        if (trimmedFallback.isEmpty) {
          continue;
        }
        effectivePosterUrl = trimmedFallback;
        break;
      }
    }
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheHeight = (196 * pixelRatio).round();
    final posterUri = Uri.tryParse(effectivePosterUrl);
    final host = posterUri?.host.toLowerCase() ?? '';
    // 豆瓣带 imageView2 等参数的图在部分设备上与 decode 尺寸限制组合可能解码失败，故不缩采样。
    final skipResizeForDecode =
        host.endsWith('.doubanio.com') || host == 'img.douban.com';
    final enablePosterFocusOutline =
        isTelevision && widget.tvPosterFocusOutlineOnly;
    final hasPosterCandidate =
        trimmedPoster.isNotEmpty || widget.posterFallbackSources.isNotEmpty;

    late final Widget posterChild;
    if (!hasPosterCandidate) {
      posterChild = _buildPosterPlaceholder(theme);
    } else {
      posterChild = AppNetworkImage(
        trimmedPoster,
        headers: widget.posterHeaders,
        fallbackSources: widget.posterFallbackSources,
        fit: BoxFit.cover,
        // Only constrain decode height so landscape fallbacks keep
        // their original aspect ratio before BoxFit.cover crops them.
        cacheHeight: skipResizeForDecode ? null : cacheHeight,
        filterQuality: FilterQuality.low,
        loadingBuilder: (context) {
          return _buildPosterPlaceholder(theme);
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildPosterPlaceholder(theme);
        },
      );
    }

    Widget buildPosterFrame() {
      final posterFrame = RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: posterChild),
              if (widget.imageBadgeText.trim().isNotEmpty)
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: _PosterImageBadge(
                    text: widget.imageBadgeText,
                    textStyle: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                      fontSize: 10,
                    ),
                  ),
                ),
              if (widget.imageTopRightBadgeText.trim().isNotEmpty)
                Positioned(
                  top: 10,
                  right: 10,
                  child: _PosterImageBadge(
                    text: widget.imageTopRightBadgeText,
                    textStyle: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      if (!enablePosterFocusOutline) {
        return posterFrame;
      }
      return ValueListenableBuilder<bool>(
        valueListenable: _isFocusedNotifier,
        child: posterFrame,
        builder: (context, isPosterFocused, child) {
          Widget currentChild = child!;
          if (isPosterFocused && widget.tvPosterFocusShowBorder) {
            currentChild = Stack(
              fit: StackFit.expand,
              children: [
                currentChild,
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white,
                        width: 2.4,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          return AnimatedScale(
            scale: isPosterFocused ? widget.tvPosterFocusScale : 1.0,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: currentChild,
          );
        },
      );
    }

    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.22,
      color: widget.titleColor,
    );
    final subtitlePresent = widget.subtitle.trim().isNotEmpty;
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: widget.subtitleColor ?? theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    final content = SizedBox(
      width: widget.width,
      child: RepaintBoundary(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 0.7,
              child: buildPosterFrame(),
            ),
            const SizedBox(height: 4),
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
            if (subtitlePresent) ...[
              const SizedBox(height: 2),
              Text(
                widget.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: subtitleStyle,
              ),
            ],
          ],
        ),
      ),
    );

    if (isTelevision) {
      return _TelevisionPosterAction(
        focusNode: _effectiveFocusNode,
        autofocus: widget.autofocus,
        onPressed: widget.onTap,
        onContextAction: widget.onContextAction,
        child: content,
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: widget.onTap,
      onLongPress: widget.onContextAction,
      onSecondaryTap: widget.onContextAction,
      child: content,
    );
  }

  Widget _buildPosterPlaceholder(ThemeData theme) {
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class _TelevisionPosterContextMenuIntent extends Intent {
  const _TelevisionPosterContextMenuIntent();
}

class _TelevisionPosterAction extends StatelessWidget {
  const _TelevisionPosterAction({
    required this.child,
    required this.onPressed,
    required this.focusNode,
    this.onContextAction,
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback onPressed;
  final VoidCallback? onContextAction;
  final FocusNode focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.contextMenu):
            _TelevisionPosterContextMenuIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonY):
            _TelevisionPosterContextMenuIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onPressed();
              return null;
            },
          ),
          _TelevisionPosterContextMenuIntent:
              CallbackAction<_TelevisionPosterContextMenuIntent>(
            onInvoke: (_) {
              onContextAction?.call();
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: focusNode,
          autofocus: autofocus,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            onLongPress: onContextAction,
            onSecondaryTap: onContextAction,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _PosterImageBadge extends StatelessWidget {
  const _PosterImageBadge({
    required this.text,
    this.textStyle,
  });

  final String text;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 4,
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyle,
        ),
      ),
    );
  }
}
