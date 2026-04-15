import 'package:starflow/features/playback/domain/online_subtitle_structured_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

Future<OnlineSubtitleSearchRequest> buildOnlineSubtitleSearchRequestForTarget({
  required PlaybackTarget target,
  String query = '',
  String title = '',
  String originalTitle = '',
  String imdbId = '',
  String tmdbId = '',
  List<String> languages = const <String>[],
  bool preferHearingImpaired = false,
}) async {
  return OnlineSubtitleSearchRequest.fromPlaybackTarget(
    target,
    query: query.trim().isNotEmpty ? query.trim() : buildSubtitleSearchQuery(target),
    originalTitle: originalTitle,
    imdbId: imdbId,
    tmdbId: tmdbId,
    languages: languages,
    context: {
      if (title.trim().isNotEmpty) 'display_title': title.trim(),
    },
  );
}

Future<OnlineSubtitleSearchRequest> buildOnlineSubtitleSearchRequestForRoute(
  SubtitleSearchRequest request, {
  List<String> languages = const <String>[],
  bool preferHearingImpaired = false,
}) async {
  return OnlineSubtitleSearchRequest(
    query: request.query,
    title: request.title,
    originalTitle: request.originalTitle,
    year: request.year,
    imdbId: request.imdbId,
    tmdbId: request.tmdbId,
    seasonNumber: request.seasonNumber,
    episodeNumber: request.episodeNumber,
    filePath: request.filePath,
    languages: languages,
    preferHearingImpaired: preferHearingImpaired,
  );
}
