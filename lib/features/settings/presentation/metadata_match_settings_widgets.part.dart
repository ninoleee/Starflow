part of 'metadata_match_settings_page.dart';

class _TestResultCard extends StatelessWidget {
  const _TestResultCard({
    required this.title,
    required this.lines,
    this.imageUrl = '',
    this.overview = '',
  });

  final String title;
  final List<String> lines;
  final String imageUrl;
  final String overview;

  @override
  Widget build(BuildContext context) {
    final overviewText = sanitizeMetadataOverviewText(overview);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl.trim().isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AppNetworkImage(
                imageUrl,
                headers: networkImageHeadersForUrl(imageUrl),
                width: 86,
                height: 124,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _TestPosterPlaceholder(title: title);
                },
                loadingBuilder: (context) {
                  return const SizedBox(
                    width: 86,
                    height: 124,
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                for (final line in lines) Text(line),
                if (overviewText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    overviewText,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TestPosterPlaceholder extends StatelessWidget {
  const _TestPosterPlaceholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final trimmed = title.trim();
    final letter = trimmed.isEmpty ? '?' : trimmed.substring(0, 1);
    return Container(
      width: 86,
      height: 124,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        letter.toUpperCase(),
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}
