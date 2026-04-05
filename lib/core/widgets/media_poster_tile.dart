import 'package:flutter/material.dart';
import 'package:starflow/core/widgets/app_network_image.dart';

class MediaPosterTile extends StatelessWidget {
  const MediaPosterTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.posterUrl,
    this.posterHeaders = const {},
    required this.onTap,
    this.width = 140,
    this.titleColor,
    this.subtitleColor,
  });

  final String title;
  final String subtitle;
  final String posterUrl;
  final Map<String, String> posterHeaders;
  final VoidCallback onTap;
  final double? width;
  final Color? titleColor;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 0.7,
                child: posterChild,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
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
                  color: subtitleColor ?? theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
