import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

final Set<String> _loggedPosterLayoutKeys = <String>{};
const _posterDebugKeyword = '9号秘事';

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
    this.focusId,
    this.autofocus = false,
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
  final String? focusId;
  final bool autofocus;

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
        debugLabel: title.contains(_posterDebugKeyword) ? 'poster:$title' : '',
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
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: posterChild),
            if (imageBadgeText.trim().isNotEmpty)
              Positioned(
                left: 10,
                bottom: 10,
                child: DecoratedBox(
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
                      imageBadgeText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
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
          final layoutLogKey =
              '$title|${constraints.maxWidth.toStringAsFixed(1)}x'
              '${constraints.maxHeight.toStringAsFixed(1)}|'
              '${posterHeight.toStringAsFixed(1)}';
          if (title.contains(_posterDebugKeyword) &&
              _loggedPosterLayoutKeys.add(layoutLogKey)) {
            debugPrint(
              '[PosterLayout] $title '
              'constraints=${constraints.maxWidth.toStringAsFixed(1)}x'
              '${constraints.maxHeight.toStringAsFixed(1)} '
              'naturalPoster=${naturalPosterHeight.toStringAsFixed(1)} '
              'availablePoster=${availablePosterHeight.toStringAsFixed(1)} '
              'poster=${posterHeight.toStringAsFixed(1)} '
              'subtitle=${subtitle.trim().isNotEmpty}',
            );
          }

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
        autofocus: autofocus,
        borderRadius: BorderRadius.circular(16),
        visualStyle: TvFocusVisualStyle.subtle,
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
