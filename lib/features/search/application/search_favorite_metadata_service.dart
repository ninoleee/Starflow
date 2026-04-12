import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/utils/metadata_search_trace.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/metadata/data/metadata_match_resolver.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

typedef SearchFavoriteMetadataResolver = Future<MetadataMatchResult?> Function({
  required AppSettings settings,
  required MetadataMatchRequest request,
});

final searchFavoriteMetadataServiceProvider =
    Provider<SearchFavoriteMetadataService>((ref) {
  final resolver = ref.read(metadataMatchResolverProvider);
  return SearchFavoriteMetadataService(
    resolveMatch: ({
      required AppSettings settings,
      required MetadataMatchRequest request,
    }) {
      return resolver.match(
        settings: settings,
        request: request,
      );
    },
  );
});

class SearchFavoriteMetadataService {
  const SearchFavoriteMetadataService({
    SearchFavoriteMetadataResolver? resolveMatch,
  }) : _resolveMatch = resolveMatch;

  final SearchFavoriteMetadataResolver? _resolveMatch;

  Future<SearchResult> enrichFavorite({
    required SearchResult result,
    required String query,
    required AppSettings settings,
  }) async {
    metadataSearchTrace(
      'favorite.enrich.start',
      fields: <String, Object?>{
        'query': query,
        'resultTitle': result.title,
        'favoriteFolderName': result.favoriteFolderName,
        'originalSearchTitle': result.originalSearchTitle,
        'detailTitle': result.detailTarget?.title ?? '',
        'detailSearchQuery': result.detailTarget?.searchQuery ?? '',
        'doubanId': result.doubanId,
        'imdbId': result.imdbId,
        'tmdbId': result.tmdbId,
      },
    );
    final seeded = _seedResult(result, query);
    metadataSearchTrace(
      'favorite.enrich.seeded',
      fields: <String, Object?>{
        'title': seeded.title,
        'favoriteFolderName': seeded.favoriteFolderName,
        'originalSearchTitle': seeded.originalSearchTitle,
        'metadataMediaType': seeded.metadataMediaType,
        'detailTitle': seeded.detailTarget?.title ?? '',
        'detailSearchQuery': seeded.detailTarget?.searchQuery ?? '',
        'doubanId': seeded.doubanId,
        'imdbId': seeded.imdbId,
        'tmdbId': seeded.tmdbId,
      },
    );
    if (_hasResolvedFavoriteMetadata(seeded)) {
      metadataSearchTrace(
        'favorite.enrich.skip-resolved',
        fields: <String, Object?>{
          'title': seeded.title,
          'favoriteFolderName': seeded.favoriteFolderName,
          'tmdbId': seeded.tmdbId,
        },
      );
      return seeded;
    }

    final request = _buildRequest(seeded, query);
    metadataSearchTrace(
      'favorite.enrich.request',
      fields: <String, Object?>{
        'query': request.query,
        'doubanId': request.doubanId,
        'imdbId': request.imdbId,
        'year': request.year,
        'preferSeries': request.preferSeries,
        'firstActor': request.actors.isEmpty ? '' : request.actors.first,
      },
    );
    if (_resolveMatch == null ||
        (request.query.trim().isEmpty &&
            request.doubanId.trim().isEmpty &&
            request.imdbId.trim().isEmpty)) {
      metadataSearchTrace(
        'favorite.enrich.skip-request',
        fields: <String, Object?>{
          'hasResolver': _resolveMatch != null,
          'query': request.query,
          'doubanId': request.doubanId,
          'imdbId': request.imdbId,
        },
      );
      return seeded;
    }

    try {
      final match = await _resolveMatch(
        settings: settings.copyWith(
          metadataMatchPriority: MetadataMatchProvider.tmdb,
        ),
        request: request,
      );
      if (match == null) {
        metadataSearchTrace(
          'favorite.enrich.no-match',
          fields: <String, Object?>{
            'query': request.query,
            'doubanId': request.doubanId,
            'imdbId': request.imdbId,
          },
        );
        return seeded;
      }
      final applied = _applyMatch(seeded, match);
      metadataSearchTrace(
        'favorite.enrich.matched',
        fields: <String, Object?>{
          'provider': match.provider.name,
          'matchTitle': match.title,
          'matchImdbId': match.imdbId,
          'matchTmdbId': match.tmdbId,
          'nextTitle': applied.title,
          'nextFavoriteFolderName': applied.favoriteFolderName,
        },
      );
      return applied;
    } catch (error, stackTrace) {
      metadataSearchTrace(
        'favorite.enrich.failed',
        fields: <String, Object?>{
          'query': request.query,
          'doubanId': request.doubanId,
          'imdbId': request.imdbId,
        },
        error: error,
        stackTrace: stackTrace,
      );
      return seeded;
    }
  }

  SearchResult _seedResult(SearchResult result, String query) {
    final detailTarget = result.detailTarget;
    final preferredSearchName = _preferredSearchName(result, query);
    final normalizedTitle = result.title.trim();
    return result.copyWith(
      title: preferredSearchName.isNotEmpty
          ? preferredSearchName
          : normalizedTitle.isNotEmpty
              ? normalizedTitle
              : _firstNonEmpty([
                  detailTarget?.title ?? '',
                  detailTarget?.searchQuery ?? '',
                ]),
      favoriteFolderName: result.favoriteFolderName.trim().isNotEmpty
          ? result.favoriteFolderName.trim()
          : preferredSearchName,
      originalSearchTitle: result.originalSearchTitle.trim().isNotEmpty
          ? result.originalSearchTitle.trim()
          : normalizedTitle,
      metadataMediaType: _firstNonEmpty([
        result.metadataMediaType,
        _detailTargetMediaType(detailTarget),
      ]),
      doubanId: _firstNonEmpty([
        result.doubanId,
        detailTarget?.doubanId ?? '',
      ]),
      imdbId: _normalizeImdbId(
        _firstNonEmpty([
          result.imdbId,
          detailTarget?.imdbId ?? '',
        ]),
      ),
      tmdbId: _firstNonEmpty([
        result.tmdbId,
        detailTarget?.tmdbId ?? '',
      ]),
      tvdbId: _firstNonEmpty([
        result.tvdbId,
        detailTarget?.tvdbId ?? '',
      ]),
      wikidataId: _normalizeWikidataId(
        _firstNonEmpty([
          result.wikidataId,
          detailTarget?.wikidataId ?? '',
        ]),
      ),
    );
  }

  bool _hasResolvedFavoriteMetadata(SearchResult result) {
    return result.tmdbId.trim().isNotEmpty &&
        result.title.trim().isNotEmpty &&
        result.favoriteFolderName.trim().isNotEmpty;
  }

  MetadataMatchRequest _buildRequest(SearchResult result, String query) {
    final detailTarget = result.detailTarget;
    return MetadataMatchRequest(
      query: _firstNonEmpty([
        query,
        detailTarget?.searchQuery ?? '',
        result.favoriteFolderName,
        result.originalSearchTitle,
        result.title,
      ]),
      doubanId: result.doubanId,
      imdbId: result.imdbId,
      year: detailTarget?.year ?? 0,
      preferSeries: _preferSeries(result, query),
      actors: detailTarget?.actors ?? const [],
    );
  }

  SearchResult _applyMatch(SearchResult result, MetadataMatchResult match) {
    final nextTitle = result.title.trim().isNotEmpty
        ? result.title.trim()
        : match.title.trim().isNotEmpty
            ? match.title.trim()
            : result.title;
    final nextOriginalTitle = result.originalSearchTitle.trim().isNotEmpty
        ? result.originalSearchTitle.trim()
        : result.title.trim();
    return result.copyWith(
      title: nextTitle,
      originalSearchTitle: nextOriginalTitle,
      favoriteFolderName: result.favoriteFolderName.trim().isNotEmpty
          ? result.favoriteFolderName.trim()
          : nextTitle,
      metadataMediaType: _firstNonEmpty([
        match.mediaType.toItemType,
        result.metadataMediaType,
      ]),
      doubanId: _firstNonEmpty([
        match.doubanId,
        result.doubanId,
      ]),
      imdbId: _normalizeImdbId(
        _firstNonEmpty([
          match.imdbId,
          result.imdbId,
        ]),
      ),
      tmdbId: _firstNonEmpty([
        match.tmdbId,
        result.tmdbId,
      ]),
      tvdbId: result.tvdbId,
      wikidataId: _normalizeWikidataId(result.wikidataId),
    );
  }

  bool _preferSeries(SearchResult result, String query) {
    final mediaType = result.metadataMediaType.trim().toLowerCase();
    if (mediaType == 'series') {
      return true;
    }

    final detailTarget = result.detailTarget;
    final itemType = detailTarget?.itemType.trim().toLowerCase() ?? '';
    if (itemType == 'series' || itemType == 'season' || itemType == 'episode') {
      return true;
    }

    final hint = [
      query,
      result.originalSearchTitle,
      result.title,
      detailTarget?.searchQuery ?? '',
    ].join(' ');
    return _seriesHintPattern.hasMatch(hint);
  }
}

String _preferredSearchName(SearchResult result, String query) {
  return _firstNonEmpty([
    query,
    result.favoriteFolderName,
    result.detailTarget?.searchQuery ?? '',
    result.title,
    result.detailTarget?.title ?? '',
  ]);
}

final RegExp _seriesHintPattern = RegExp(
  r'(第\s*[0-9一二三四五六七八九十百零两]+\s*[季部篇集])|(season\s*\d+)|(s\d{1,2})|(episode\s*\d+)|(e\d{1,2})',
  caseSensitive: false,
);

String _detailTargetMediaType(MediaDetailTarget? detailTarget) {
  final itemType = detailTarget?.itemType.trim().toLowerCase() ?? '';
  if (itemType == 'movie') {
    return 'movie';
  }
  if (itemType == 'series' || itemType == 'season' || itemType == 'episode') {
    return 'series';
  }
  return '';
}

String _firstNonEmpty(Iterable<String> values) {
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '';
}

String _normalizeImdbId(String value) {
  return value.trim().toLowerCase();
}

String _normalizeWikidataId(String value) {
  return value.trim().toUpperCase();
}
