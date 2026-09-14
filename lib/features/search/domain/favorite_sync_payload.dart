import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';

Map<String, dynamic> favoriteSyncResultJson(SearchResult result) =>
    _compact(_resultFields(result));

// Keep local presentation outside the replicated state, including empty core fields.
SearchResult preserveFavoritePresentation(
    SearchResult synced, SearchResult local) {
  if (identical(synced, local)) return local;
  final fields = {...local.toJson(), ..._resultFields(synced)};
  final detail = synced.detailTarget;
  final localDetail = local.detailTarget;
  if (detail != null &&
      localDetail != null &&
      detail.sourceKind == localDetail.sourceKind &&
      detail.sourceId == localDetail.sourceId &&
      detail.itemId == localDetail.itemId &&
      detail.searchQuery == localDetail.searchQuery &&
      detail.title == localDetail.title) {
    final detailFields = {...localDetail.toJson(), ..._detailFields(detail)};
    final playback = detail.playbackTarget;
    final localPlayback = localDetail.playbackTarget;
    if (playback != null &&
        localPlayback != null &&
        playback.sourceKind == localPlayback.sourceKind &&
        playback.sourceId == localPlayback.sourceId &&
        playback.itemId == localPlayback.itemId &&
        playback.streamUrl == localPlayback.streamUrl &&
        playback.actualAddress == localPlayback.actualAddress) {
      detailFields['playbackTarget'] = {
        ...localPlayback.toJson(),
        ..._playbackFields(playback),
      };
    }
    fields['detailTarget'] = detailFields;
  }
  return SearchResult.fromJson(fields);
}

Map<String, dynamic> _resultFields(SearchResult result) => {
      'id': result.id,
      'title': result.title,
      'providerId': result.providerId,
      'providerName': result.providerName,
      'resourceUrl': result.resourceUrl,
      'password': result.password,
      'cloudType': result.cloudType,
      'favoriteFolderName': result.favoriteFolderName,
      'originalSearchTitle': result.originalSearchTitle,
      'metadataMediaType': result.metadataMediaType,
      'doubanId': result.doubanId,
      'imdbId': result.imdbId,
      'tmdbId': result.tmdbId,
      'tvdbId': result.tvdbId,
      'wikidataId': result.wikidataId,
      // Legacy linkless favorites include summary in their stable identity.
      if (result.detailTarget == null &&
          normalizeSearchResourceUrl(result.resourceUrl).isEmpty)
        'summary': result.summary,
      'detailTarget': result.detailTarget == null
          ? null
          : _detailFields(result.detailTarget!),
    };

Map<String, dynamic> _detailFields(MediaDetailTarget detail) => {
      'title': detail.title,
      'year': detail.year,
      'searchQuery': detail.searchQuery,
      'itemId': detail.itemId,
      'sourceId': detail.sourceId,
      'itemType': detail.itemType,
      'seasonNumber': detail.seasonNumber,
      'episodeNumber': detail.episodeNumber,
      'sectionId': detail.sectionId,
      'sectionName': detail.sectionName,
      'resourcePath': detail.resourcePath,
      'doubanId': detail.doubanId,
      'imdbId': detail.imdbId,
      'tmdbId': detail.tmdbId,
      'tvdbId': detail.tvdbId,
      'wikidataId': detail.wikidataId,
      'tmdbSetId': detail.tmdbSetId,
      'providerIds': detail.providerIds,
      'sourceKind': detail.sourceKind?.name,
      'sourceName': detail.sourceName,
      'playbackTarget': detail.playbackTarget == null
          ? null
          : _playbackFields(detail.playbackTarget!),
    };

Map<String, dynamic> _playbackFields(PlaybackTarget playback) => {
      'title': playback.title,
      'sourceId': playback.sourceId,
      'sourceName': playback.sourceName,
      'sourceKind': playback.sourceKind.name,
      'streamUrl': playback.streamUrl,
      'actualAddress': normalizePlaybackActualAddress(playback.actualAddress),
      'originalTitle': playback.originalTitle,
      'allowResume': playback.allowResume,
      'itemId': playback.itemId,
      'itemType': playback.itemType,
      'year': playback.year,
      'imdbId': playback.imdbId,
      'tmdbId': playback.tmdbId,
      'seriesId': playback.seriesId,
      'seriesTitle': playback.seriesTitle,
      'preferredMediaSourceId': playback.preferredMediaSourceId,
      'headers': playback.headers,
      'container': playback.container,
      'videoCodec': playback.videoCodec,
      'audioCodec': playback.audioCodec,
      'width': playback.width,
      'height': playback.height,
      'bitrate': playback.bitrate,
      'fileSizeBytes': playback.fileSizeBytes,
      'seasonNumber': playback.seasonNumber,
      'episodeNumber': playback.episodeNumber,
    };

Map<String, dynamic> _compact(Map<String, dynamic> fields) {
  final compact = <String, dynamic>{};
  for (final entry in fields.entries) {
    var value = entry.value;
    if (value is Map<String, String>) {
      // Keep transport header values intact, including explicit empty values.
      final values = value;
      value = {
        for (final key in values.keys.toList()..sort()) key: values[key]!,
      };
    } else if (value is Map<String, dynamic>) {
      value = _compact(value);
    }
    if (value == null ||
        value == '' ||
        (value is Map && value.isEmpty) ||
        (value is List && value.isEmpty)) {
      continue;
    }
    compact[entry.key] = value;
  }
  return compact;
}
