import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

final detailStartPlaybackResolverProvider =
    Provider<DetailStartPlaybackResolver>(
  (ref) => DetailStartPlaybackResolver(ref.read(mediaRepositoryProvider)),
);

class DetailStartPlaybackResolver {
  const DetailStartPlaybackResolver(this.repository);

  final MediaRepository repository;

  Future<PlaybackTarget> resolve({
    required MediaDetailTarget detail,
  }) async {
    final target = detail.playbackTarget;
    final isEpisode = target?.isEpisode == true ||
        detail.itemType.trim().toLowerCase() == 'episode';
    if (!detail.isSeries && !isEpisode) {
      return _withDetailArtwork(await _movieTarget(detail), detail)
          .copyWith(allowResume: false);
    }
    final sourceId = detail.isSeries
        ? detail.sourceId.trim()
        : (target?.sourceId ?? detail.sourceId).trim();
    final seriesId = detail.isSeries
        ? detail.itemId.trim()
        : (target?.seriesId ?? '').trim();
    if (seriesId.isEmpty || sourceId.isEmpty) {
      throw const DetailStartPlaybackException('无法确定剧集所属系列，请从系列详情页从头播放');
    }
    Future<List<MediaItem>> loadChildren(String parentId) =>
        repository.fetchChildren(
          sourceId: sourceId,
          parentId: parentId,
          sectionId: detail.sectionId,
          sectionName: detail.sectionName,
          limit: 500,
        );

    final children = await loadChildren(seriesId);
    final seasons = children.where(
      (item) => item.itemType.trim().toLowerCase() == 'season',
    );
    // Match the browser: keep the source's season order and sort its episodes.
    final firstSeason = seasons.isEmpty ? null : seasons.first;
    final childrenInSeason =
        firstSeason == null ? children : await loadChildren(firstSeason.id);
    final episodes = sortEpisodesForDetailBrowser(childrenInSeason
        .where((item) => item.itemType.trim().toLowerCase() == 'episode')
        .toList(growable: false));
    for (final episode in episodes) {
      final first = PlaybackTarget.fromMediaItem(episode);
      if (!first.canPlay) continue;
      // Use the first episode's own transport and version, never history's URL.
      return _withDetailArtwork(first, detail).copyWith(
        allowResume: false,
        seriesId: seriesId,
        seriesTitle:
            detail.isSeries ? detail.title : target?.resolvedSeriesTitle,
        seasonNumber: first.seasonNumber ?? firstSeason?.seasonNumber,
      );
    }
    throw const DetailStartPlaybackException('最前面的季没有可播放剧集');
  }

  Future<PlaybackTarget> _movieTarget(MediaDetailTarget detail) async {
    if (detail.playbackTarget != null) return detail.playbackTarget!;
    // A matched resource can precede its playback metadata. Load only its source.
    final items = await repository.fetchLibrary(
      sourceId: detail.sourceId,
      sectionId: detail.sectionId.isEmpty ? null : detail.sectionId,
      limit: 2000,
    );
    for (final item in items) {
      if (item.sourceId == detail.sourceId && item.id == detail.itemId) {
        final target = PlaybackTarget.fromMediaItem(item);
        if (target.canPlay) return target;
      }
    }
    throw const DetailStartPlaybackException('匹配资源暂时不可播放，请刷新资源后重试');
  }

  PlaybackTarget _withDetailArtwork(
      PlaybackTarget target, MediaDetailTarget detail) {
    return target.copyWith(
      posterUrl: target.posterUrl.trim().isNotEmpty
          ? target.posterUrl
          : detail.posterUrl,
      posterHeaders: target.posterUrl.trim().isNotEmpty
          ? target.posterHeaders
          : detail.posterHeaders,
      backdropUrl: target.backdropUrl.trim().isNotEmpty
          ? target.backdropUrl
          : detail.backdropUrl,
      backdropHeaders: target.backdropUrl.trim().isNotEmpty
          ? target.backdropHeaders
          : detail.backdropHeaders,
    );
  }
}

class DetailStartPlaybackException implements Exception {
  const DetailStartPlaybackException(this.message);

  final String message;

  @override
  String toString() => message;
}
