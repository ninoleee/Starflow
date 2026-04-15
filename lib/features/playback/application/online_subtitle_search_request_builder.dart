import 'package:starflow/features/playback/application/online_subtitle_search_request_builder_stub.dart'
    if (dart.library.io)
        'package:starflow/features/playback/application/online_subtitle_search_request_builder_io.dart'
    as impl;
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
}) {
  return impl.buildOnlineSubtitleSearchRequestForTarget(
    target: target,
    query: query,
    title: title,
    originalTitle: originalTitle,
    imdbId: imdbId,
    tmdbId: tmdbId,
    languages: languages,
    preferHearingImpaired: preferHearingImpaired,
  );
}

Future<OnlineSubtitleSearchRequest> buildOnlineSubtitleSearchRequestForRoute(
  SubtitleSearchRequest request, {
  List<String> languages = const <String>[],
  bool preferHearingImpaired = false,
}) {
  return impl.buildOnlineSubtitleSearchRequestForRoute(
    request,
    languages: languages,
    preferHearingImpaired: preferHearingImpaired,
  );
}
