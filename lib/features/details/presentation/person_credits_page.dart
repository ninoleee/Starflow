import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

enum PersonCreditsRole {
  director,
  actor,
}

extension PersonCreditsRoleX on PersonCreditsRole {
  String get label {
    switch (this) {
      case PersonCreditsRole.director:
        return '导演作品';
      case PersonCreditsRole.actor:
        return '演员作品';
    }
  }

  TmdbPersonCreditsRole get tmdbRole {
    switch (this) {
      case PersonCreditsRole.director:
        return TmdbPersonCreditsRole.director;
      case PersonCreditsRole.actor:
        return TmdbPersonCreditsRole.actor;
    }
  }
}

class PersonCreditsPageTarget {
  const PersonCreditsPageTarget({
    required this.person,
    required this.role,
  });

  final MediaPersonProfile person;
  final PersonCreditsRole role;
}

class PersonCreditsPage extends ConsumerStatefulWidget {
  const PersonCreditsPage({super.key, required this.target});

  final PersonCreditsPageTarget target;

  @override
  ConsumerState<PersonCreditsPage> createState() => _PersonCreditsPageState();
}

class _PersonCreditsPageState extends ConsumerState<PersonCreditsPage> {
  final TvFocusMemoryController _tvFocusMemoryController =
      TvFocusMemoryController();

  @override
  void dispose() {
    _tvFocusMemoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    final target = widget.target;
    final resultAsync = ref.watch(_personCreditsPageProvider(target));

    return TvFocusMemoryScope(
      controller: _tvFocusMemoryController,
      scopeId: 'person-credits',
      enabled: isTelevision,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            AppPageBackground(
              child: ListView(
                padding: overlayToolbarPagePadding(context),
                children: [
                  _PersonCreditsHeader(target: target),
                  const SizedBox(height: 22),
                  resultAsync.when(
                    data: (result) {
                      if (result.items.isEmpty) {
                        return _EmptyState(message: result.message);
                      }
                      return _PersonCreditsGrid(items: result.items);
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, stackTrace) => _EmptyState(
                      message: '加载关联影片失败：$error',
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: OverlayToolbar(
                onBack: () => context.pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final _personCreditsPageProvider = FutureProvider.autoDispose
    .family<_PersonCreditsPageResult, PersonCreditsPageTarget>(
        (ref, target) async {
  final settings = ref.read(appSettingsProvider);
  final token = settings.tmdbReadAccessToken.trim();
  if (!settings.tmdbMetadataMatchEnabled || token.isEmpty) {
    return const _PersonCreditsPageResult(
      items: [],
      message: '未配置 TMDB Read Access Token。',
    );
  }

  final credits = await ref.read(tmdbMetadataClientProvider).fetchPersonCredits(
        name: target.person.name,
        avatarUrl: target.person.avatarUrl,
        role: target.role.tmdbRole,
        readAccessToken: token,
      );
  if (credits.isEmpty) {
    return const _PersonCreditsPageResult(
      items: [],
      message: '没有找到关联影片。',
    );
  }

  return _PersonCreditsPageResult(
    items: credits.map(_toPersonCreditCard).toList(growable: false),
    message: '',
  );
});

class _PersonCreditsPageResult {
  const _PersonCreditsPageResult({
    required this.items,
    required this.message,
  });

  final List<_PersonCreditCardData> items;
  final String message;
}

class _PersonCreditCardData {
  const _PersonCreditCardData({
    required this.title,
    required this.subtitle,
    required this.ratingLabel,
    required this.detailTarget,
  });

  final String title;
  final String subtitle;
  final String ratingLabel;
  final MediaDetailTarget detailTarget;
}

_PersonCreditCardData _toPersonCreditCard(TmdbPersonCredit credit) {
  final detailTarget = MediaDetailTarget(
    title: credit.title,
    posterUrl: credit.posterUrl,
    backdropUrl: credit.backdropUrl,
    bannerUrl: credit.bannerUrl,
    overview: credit.overview,
    year: credit.year,
    ratingLabels: credit.ratingLabels,
    availabilityLabel: '无',
    searchQuery: credit.title,
    itemType: credit.isSeries ? 'series' : 'movie',
    sourceName: 'TMDB',
  );
  final preferredRating = _preferredRatingLabel(credit.ratingLabels);
  final subtitleParts = <String>[
    if (credit.year > 0) '${credit.year}',
    if (credit.subtitle.trim().isNotEmpty) credit.subtitle.trim(),
  ];
  return _PersonCreditCardData(
    title: credit.title,
    subtitle: subtitleParts.join(' · '),
    ratingLabel: preferredRating,
    detailTarget: detailTarget,
  );
}

String _preferredRatingLabel(Iterable<String> labels) {
  final normalized = labels
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (normalized.isEmpty) {
    return '';
  }
  for (final keyword in const ['imdb', '豆瓣', 'tmdb']) {
    for (final label in normalized) {
      if (label.toLowerCase().contains(keyword)) {
        return label;
      }
    }
  }
  return normalized.first;
}

List<AppNetworkImageSource> _buildPosterFallbackSources(
    MediaDetailTarget target) {
  final sources = <AppNetworkImageSource>[];
  final seen = <String>{target.posterUrl.trim()};

  void add(String url, Map<String, String> headers) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty || !seen.add(trimmedUrl)) {
      return;
    }
    sources.add(
      AppNetworkImageSource(
        url: trimmedUrl,
        headers: headers,
      ),
    );
  }

  add(target.bannerUrl, target.bannerHeaders);
  add(target.backdropUrl, target.backdropHeaders);
  for (final url in target.extraBackdropUrls) {
    add(url, target.extraBackdropHeaders);
  }
  return sources;
}

class _PersonCreditsHeader extends StatelessWidget {
  const _PersonCreditsHeader({required this.target});

  final PersonCreditsPageTarget target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _PersonAvatar(person: target.person, size: 72),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                target.person.name,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                target.role.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF90A0BD),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({
    required this.person,
    this.size = 74,
  });

  final MediaPersonProfile person;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = person.avatarUrl.trim();
    return Container(
      width: size,
      height: size,
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
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.32,
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
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

String _personInitial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return trimmed.characters.first.toUpperCase();
}

class _PersonCreditsGrid extends StatelessWidget {
  const _PersonCreditsGrid({required this.items});

  final List<_PersonCreditCardData> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final maxWidth = constraints.maxWidth;
        final crossAxisCount =
            math.max(2, ((maxWidth + spacing) / 150).floor());
        final itemWidth =
            (maxWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;
        final itemHeight = itemWidth / 0.7 + 54;
        final childAspectRatio = itemWidth / itemHeight;

        return GridView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: childAspectRatio,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return MediaPosterTile(
              focusId:
                  'person-credits:${item.detailTarget.itemId.isNotEmpty ? item.detailTarget.itemId : item.title}',
              autofocus: index == 0,
              title: item.title,
              subtitle: item.subtitle,
              imageBadgeText: item.ratingLabel,
              posterUrl: item.detailTarget.posterUrl,
              posterHeaders: item.detailTarget.posterHeaders,
              posterFallbackSources: _buildPosterFallbackSources(
                item.detailTarget,
              ),
              width: null,
              onTap: () {
                context.pushNamed(
                  'detail',
                  extra: item.detailTarget,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Center(
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF90A0BD),
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}
