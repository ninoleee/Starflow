import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

class MediaPosterTile extends ConsumerWidget {
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
    this.tvPosterFocusOutlineOnly = false,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    final trimmedPoster = posterUrl.trim();
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (136 * pixelRatio).round();
    final cacheHeight = (196 * pixelRatio).round();
    final posterUri = Uri.tryParse(trimmedPoster);
    final host = posterUri?.host.toLowerCase() ?? '';
    // 豆瓣带 imageView2 等参数的图在部分设备上与 decode 尺寸限制组合可能解码失败，故不缩采样。
    final skipResizeForDecode =
        host.endsWith('.doubanio.com') || host == 'img.douban.com';
    final enablePosterFocusOutline = isTelevision && tvPosterFocusOutlineOnly;

    final Widget posterChild;
    if (trimmedPoster.isEmpty) {
      posterChild = Container(
        color: theme.colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          Icons.movie_creation_outlined,
          size: 32,
          color: theme.colorScheme.primary,
        ),
      );
    } else {
      posterChild = AppNetworkImage(
        trimmedPoster,
        headers: posterHeaders,
        fallbackSources: posterFallbackSources,
        fit: BoxFit.cover,
        cacheWidth: skipResizeForDecode ? null : cacheWidth,
        cacheHeight: skipResizeForDecode ? null : cacheHeight,
        filterQuality: FilterQuality.low,
        loadingBuilder: (context) {
          return Container(
            color: theme.colorScheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.1,
                color: theme.colorScheme.primary,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: theme.colorScheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: Icon(
              Icons.movie_creation_outlined,
              size: 32,
              color: theme.colorScheme.primary,
            ),
          );
        },
      );
    }

    Widget buildPosterFrame() {
      final posterFrame = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: posterChild),
            if (imageBadgeText.trim().isNotEmpty)
              Positioned(
                left: 10,
                bottom: 10,
                child: _PosterImageBadge(
                  text: imageBadgeText,
                  textStyle: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                    fontSize: 10,
                  ),
                ),
              ),
            if (imageTopRightBadgeText.trim().isNotEmpty)
              Positioned(
                top: 10,
                right: 10,
                child: _PosterImageBadge(
                  text: imageTopRightBadgeText,
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
      );
      if (!enablePosterFocusOutline) {
        return posterFrame;
      }
      return Builder(
        builder: (context) {
          final focusState = Focus.of(context);
          final isPosterFocused =
              focusState.hasFocus || focusState.hasPrimaryFocus;
          return Stack(
            fit: StackFit.expand,
            children: [
              posterFrame,
              IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 110),
                  curve: Curves.easeOut,
                  opacity: isPosterFocused ? 1 : 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 1.1,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    final content = SizedBox(
      width: width,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedHeight) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 0.7,
                  child: buildPosterFrame(),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.22,
                    color: titleColor,
                  ),
                ),
                if (subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          subtitleColor ?? theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            );
          }

          const titleAreaHeight = 18.0;
          final subtitleAreaHeight = subtitle.trim().isNotEmpty ? 18.0 : 0.0;
          final detailsReservedHeight =
              6.0 + titleAreaHeight + subtitleAreaHeight;
          final availablePosterHeight =
              (constraints.maxHeight - detailsReservedHeight)
                  .clamp(0.0, constraints.maxHeight)
                  .toDouble();
          final naturalPosterHeight =
              constraints.hasBoundedWidth ? constraints.maxWidth / 0.7 : 0.0;
          final posterHeight = naturalPosterHeight < availablePosterHeight
              ? naturalPosterHeight
              : availablePosterHeight;

          return ClipRect(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: posterHeight,
                  width: double.infinity,
                  child: SizedBox.expand(child: buildPosterFrame()),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ClipRect(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.22,
                              color: titleColor,
                            ),
                          ),
                          if (subtitle.trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: subtitleColor ??
                                    theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (isTelevision) {
      return TvFocusableAction(
        onPressed: onTap,
        onContextAction: onContextAction,
        focusId: focusId,
        focusNode: focusNode,
        autofocus: autofocus,
        borderRadius: BorderRadius.circular(16),
        visualStyle: TvFocusVisualStyle.floating,
        child: content,
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      onLongPress: onContextAction,
      onSecondaryTap: onContextAction,
      child: content,
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
