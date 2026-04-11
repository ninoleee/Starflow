import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final detailExternalEpisodeVariantServiceProvider =
    Provider<DetailExternalEpisodeVariantService>(
  (ref) => const DetailExternalEpisodeVariantService(),
);

class DetailExternalEpisodeVariantState {
  const DetailExternalEpisodeVariantState({
    required this.choices,
    required this.selectedIndex,
  });

  final List<MediaDetailTarget> choices;
  final int selectedIndex;
}

class DetailExternalEpisodeVariantService {
  const DetailExternalEpisodeVariantService();

  Future<DetailExternalEpisodeVariantState?> loadChoices({
    required MediaDetailTarget target,
    required AppSettings settings,
    required NasMediaIndexer nasMediaIndexer,
  }) async {
    if (!_supportsTarget(target)) {
      return null;
    }

    final source = settings.mediaSources
        .where(
          (candidate) =>
              candidate.enabled &&
              candidate.id == target.sourceId &&
              (candidate.kind == MediaSourceKind.nas ||
                  candidate.kind == MediaSourceKind.quark),
        )
        .firstOrNull;
    if (source == null) {
      return null;
    }

    final items = await nasMediaIndexer.loadEpisodeVariants(
      source,
      itemId: target.itemId,
      sectionId: target.sectionId,
    );
    if (items.length <= 1) {
      return null;
    }

    final choices = items
        .map((item) => _buildChoiceTarget(item: item, current: target))
        .toList(growable: false);
    if (choices.length <= 1) {
      return null;
    }

    return DetailExternalEpisodeVariantState(
      choices: choices,
      selectedIndex: _resolveSelectedIndex(target: target, choices: choices),
    );
  }

  bool _supportsTarget(MediaDetailTarget target) {
    final itemType = target.itemType.trim().toLowerCase();
    final playback = target.playbackTarget;
    final isEpisodeLike =
        itemType == 'episode' || playback?.normalizedItemType == 'episode';
    return isEpisodeLike &&
        target.sourceId.trim().isNotEmpty &&
        target.itemId.trim().isNotEmpty &&
        (target.sourceKind == MediaSourceKind.nas ||
            target.sourceKind == MediaSourceKind.quark);
  }

  int _resolveSelectedIndex({
    required MediaDetailTarget target,
    required List<MediaDetailTarget> choices,
  }) {
    final targetItemId = target.itemId.trim();
    if (targetItemId.isNotEmpty) {
      final byItemId = choices.indexWhere(
        (choice) => choice.itemId.trim() == targetItemId,
      );
      if (byItemId >= 0) {
        return byItemId;
      }
    }

    final targetPlaybackId = target.playbackTarget?.itemId.trim() ?? '';
    if (targetPlaybackId.isNotEmpty) {
      final byPlaybackId = choices.indexWhere(
        (choice) => choice.playbackTarget?.itemId.trim() == targetPlaybackId,
      );
      if (byPlaybackId >= 0) {
        return byPlaybackId;
      }
    }

    final targetPath = _normalizedPath(
      target.playbackTarget?.actualAddress ?? target.resourcePath,
    );
    if (targetPath.isNotEmpty) {
      final byPath = choices.indexWhere(
        (choice) =>
            _normalizedPath(
              choice.playbackTarget?.actualAddress ?? choice.resourcePath,
            ) ==
            targetPath,
      );
      if (byPath >= 0) {
        return byPath;
      }
    }

    return 0;
  }

  MediaDetailTarget _buildChoiceTarget({
    required MediaItem item,
    required MediaDetailTarget current,
  }) {
    final base = MediaDetailTarget.fromMediaItem(
      item,
      availabilityLabel: current.availabilityLabel.trim().isNotEmpty
          ? current.availabilityLabel
          : (item.isPlayable
              ? '资源已就绪：${item.sourceKind.label} · ${item.sourceName}'
              : ''),
      searchQuery: current.searchQuery.trim().isNotEmpty
          ? current.searchQuery
          : item.title,
    );
    final currentPlayback = current.playbackTarget;
    final basePlayback = base.playbackTarget;
    final mergedPlayback = basePlayback?.copyWith(
      seriesId: basePlayback.seriesId.trim().isNotEmpty
          ? basePlayback.seriesId
          : (currentPlayback?.seriesId.trim().isNotEmpty == true
              ? currentPlayback!.seriesId.trim()
              : ''),
      seriesTitle: basePlayback.seriesTitle.trim().isNotEmpty
          ? basePlayback.seriesTitle
          : (currentPlayback?.resolvedSeriesTitle.trim().isNotEmpty == true
              ? currentPlayback!.resolvedSeriesTitle.trim()
              : current.title),
    );

    return base.copyWith(
      title: current.title.trim().isNotEmpty ? current.title : base.title,
      posterUrl:
          base.posterUrl.trim().isNotEmpty ? base.posterUrl : current.posterUrl,
      posterHeaders: base.posterUrl.trim().isNotEmpty
          ? base.posterHeaders
          : current.posterHeaders,
      backdropUrl: base.backdropUrl.trim().isNotEmpty
          ? base.backdropUrl
          : current.backdropUrl,
      backdropHeaders: base.backdropUrl.trim().isNotEmpty
          ? base.backdropHeaders
          : current.backdropHeaders,
      logoUrl: base.logoUrl.trim().isNotEmpty ? base.logoUrl : current.logoUrl,
      logoHeaders: base.logoUrl.trim().isNotEmpty
          ? base.logoHeaders
          : current.logoHeaders,
      bannerUrl:
          base.bannerUrl.trim().isNotEmpty ? base.bannerUrl : current.bannerUrl,
      bannerHeaders: base.bannerUrl.trim().isNotEmpty
          ? base.bannerHeaders
          : current.bannerHeaders,
      extraBackdropUrls: base.extraBackdropUrls.isNotEmpty
          ? base.extraBackdropUrls
          : current.extraBackdropUrls,
      extraBackdropHeaders: base.extraBackdropUrls.isNotEmpty
          ? base.extraBackdropHeaders
          : current.extraBackdropHeaders,
      overview:
          base.overview.trim().isNotEmpty ? base.overview : current.overview,
      year: base.year > 0 ? base.year : current.year,
      durationLabel: base.durationLabel.trim().isNotEmpty
          ? base.durationLabel
          : current.durationLabel,
      ratingLabels: _mergeUniqueStrings(
        current.ratingLabels,
        base.ratingLabels,
      ),
      genres: base.genres.isNotEmpty ? base.genres : current.genres,
      directors: base.directors.isNotEmpty ? base.directors : current.directors,
      directorProfiles: base.directorProfiles.isNotEmpty
          ? base.directorProfiles
          : current.directorProfiles,
      actors: base.actors.isNotEmpty ? base.actors : current.actors,
      actorProfiles: base.actorProfiles.isNotEmpty
          ? base.actorProfiles
          : current.actorProfiles,
      platforms: base.platforms.isNotEmpty ? base.platforms : current.platforms,
      platformProfiles: base.platformProfiles.isNotEmpty
          ? base.platformProfiles
          : current.platformProfiles,
      doubanId:
          base.doubanId.trim().isNotEmpty ? base.doubanId : current.doubanId,
      imdbId: base.imdbId.trim().isNotEmpty ? base.imdbId : current.imdbId,
      tmdbId: base.tmdbId.trim().isNotEmpty ? base.tmdbId : current.tmdbId,
      tvdbId: base.tvdbId.trim().isNotEmpty ? base.tvdbId : current.tvdbId,
      wikidataId: base.wikidataId.trim().isNotEmpty
          ? base.wikidataId
          : current.wikidataId,
      tmdbSetId:
          base.tmdbSetId.trim().isNotEmpty ? base.tmdbSetId : current.tmdbSetId,
      providerIds:
          base.providerIds.isNotEmpty ? base.providerIds : current.providerIds,
      sourceKind: base.sourceKind ?? current.sourceKind,
      sourceName: base.sourceName.trim().isNotEmpty
          ? base.sourceName
          : current.sourceName,
      playbackTarget: mergedPlayback,
    );
  }

  List<String> _mergeUniqueStrings(
    Iterable<String> primary,
    Iterable<String> secondary,
  ) {
    final seen = <String>{};
    final merged = <String>[];
    for (final item in [...primary, ...secondary]) {
      final trimmed = item.trim();
      final normalized = trimmed.toLowerCase();
      if (trimmed.isEmpty || !seen.add(normalized)) {
        continue;
      }
      merged.add(trimmed);
    }
    return merged;
  }

  String _normalizedPath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(trimmed);
    final rawPath = uri != null && uri.hasScheme ? uri.path : trimmed;
    return rawPath.replaceAll('\\', '/').trim();
  }
}
