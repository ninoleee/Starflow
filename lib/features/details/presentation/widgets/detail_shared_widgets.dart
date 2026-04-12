import 'package:flutter/material.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/desktop_horizontal_pager.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';

class DetailBlock extends StatelessWidget {
  const DetailBlock({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class InfoLabel extends StatelessWidget {
  const InfoLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF8FA0BD),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class PersonRail extends StatelessWidget {
  const PersonRail({
    super.key,
    required this.people,
    required this.focusScopePrefix,
    required this.onPersonTap,
  });

  final List<MediaPersonProfile> people;
  final String focusScopePrefix;
  final ValueChanged<MediaPersonProfile> onPersonTap;

  @override
  Widget build(BuildContext context) {
    final visiblePeople = people
        .where((item) => item.name.trim().isNotEmpty)
        .toList(growable: false);
    if (visiblePeople.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 128,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: visiblePeople.length,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final person = visiblePeople[index];
          return TvFocusableAction(
            onPressed: () => onPersonTap(person),
            focusId: '$focusScopePrefix:${person.name}',
            autofocus: index == 0,
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 86,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _PersonAvatar(person: person),
                  const SizedBox(height: 10),
                  Text(
                    person.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({required this.person});

  final MediaPersonProfile person;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = person.avatarUrl.trim();
    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF162233),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: avatarUrl.isEmpty
          ? Center(
              child: Text(
                _personInitial(person.name),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : AppNetworkImage(
              avatarUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Center(
                  child: Text(
                    _personInitial(person.name),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class PlatformRail extends StatelessWidget {
  const PlatformRail({super.key, required this.platforms});

  final List<MediaPersonProfile> platforms;

  @override
  Widget build(BuildContext context) {
    final visiblePlatforms = platforms
        .where(
          (item) =>
              item.name.trim().isNotEmpty && item.avatarUrl.trim().isNotEmpty,
        )
        .toList(growable: false);
    if (visiblePlatforms.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 24,
      runSpacing: 18,
      children: visiblePlatforms
          .map((platform) => _PlatformLogo(platform: platform))
          .toList(growable: false),
    );
  }
}

class _PlatformLogo extends StatelessWidget {
  const _PlatformLogo({required this.platform});

  final MediaPersonProfile platform;
  static const double _logoDisplayWidth = 200;
  static const double _logoDisplayHeight = 100;

  @override
  Widget build(BuildContext context) {
    final logoUrl = platform.avatarUrl.trim();
    if (logoUrl.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: _logoDisplayWidth,
      height: _logoDisplayHeight,
      child: Center(
        child: AppNetworkImage(
          logoUrl,
          width: _logoDisplayWidth,
          height: _logoDisplayHeight,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          errorBuilder: (context, error, stackTrace) {
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

String _personInitial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}

class FactRow extends StatelessWidget {
  const FactRow({
    super.key,
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8FA0BD),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: selectable
              ? SelectableText(
                  value,
                  style: const TextStyle(
                    color: Color(0xFFE6EDFD),
                    fontSize: 14,
                    height: 1.5,
                  ),
                )
              : Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFFE6EDFD),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
        ),
      ],
    );
  }
}

class DetailImageAsset {
  const DetailImageAsset({
    required this.url,
    this.headers = const {},
    this.cachePolicy = AppNetworkImageCachePolicy.persistent,
  });

  final String url;
  final Map<String, String> headers;
  final AppNetworkImageCachePolicy cachePolicy;
}

class DetailImageGallery extends StatelessWidget {
  const DetailImageGallery({
    super.key,
    required this.images,
    this.focusIdPrefix = 'detail:gallery',
  });

  final List<DetailImageAsset> images;
  final String focusIdPrefix;

  @override
  Widget build(BuildContext context) {
    Future<void> openPreview(DetailImageAsset image) {
      return showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 28,
              vertical: 24,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Color(0xFF07121F),
                  ),
                  child: AppNetworkImage(
                    image.url,
                    headers: image.headers,
                    cachePolicy: image.cachePolicy,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const ColoredBox(color: Color(0xFF0D192A));
                    },
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    return SizedBox(
      height: 164,
      child: DesktopHorizontalPager(
        builder: (context, controller) => ListView.separated(
          controller: controller,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: images.length,
          separatorBuilder: (context, index) => const SizedBox(width: 14),
          itemBuilder: (context, index) {
            final image = images[index];
            return TvFocusableAction(
              onPressed: () => openPreview(image),
              focusId: '$focusIdPrefix:$index',
              borderRadius: BorderRadius.circular(22),
              visualStyle: TvFocusVisualStyle.subtle,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: SizedBox(
                    width: 268,
                    child: AppNetworkImage(
                      image.url,
                      headers: image.headers,
                      cachePolicy: image.cachePolicy,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const ColoredBox(color: Color(0xFF0D192A));
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

List<DetailImageAsset> buildDetailGalleryImages(MediaDetailTarget target) {
  final seen = <String>{};
  final images = <DetailImageAsset>[];

  void add(
    String url,
    Map<String, String> headers,
    AppNetworkImageCachePolicy cachePolicy,
  ) {
    final trimmed = url.trim();
    if (trimmed.isEmpty || !seen.add(trimmed)) {
      return;
    }
    images.add(
      DetailImageAsset(
        url: trimmed,
        headers: headers,
        cachePolicy: cachePolicy,
      ),
    );
  }

  add(
    target.backdropUrl,
    target.backdropHeaders,
    _shouldBypassPersistentCacheForBackdrop(target)
        ? AppNetworkImageCachePolicy.networkOnly
        : AppNetworkImageCachePolicy.persistent,
  );
  add(
    target.bannerUrl,
    target.bannerHeaders,
    AppNetworkImageCachePolicy.persistent,
  );
  for (final url in target.extraBackdropUrls) {
    add(
      url,
      target.extraBackdropHeaders,
      AppNetworkImageCachePolicy.networkOnly,
    );
  }
  return images;
}

bool _shouldBypassPersistentCacheForBackdrop(MediaDetailTarget target) {
  final itemType = target.itemType.trim().toLowerCase();
  if (itemType != 'episode') {
    return false;
  }
  final backdropUrl = target.backdropUrl.trim();
  final bannerUrl = target.bannerUrl.trim();
  return backdropUrl.isNotEmpty &&
      bannerUrl.isNotEmpty &&
      backdropUrl != bannerUrl;
}
