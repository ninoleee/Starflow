import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/playback/data/online_subtitle_repository_stub.dart'
    if (dart.library.io) 'package:starflow/features/playback/data/online_subtitle_repository_io.dart'
    as impl;
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

final onlineSubtitleRepositoryProvider = Provider<OnlineSubtitleRepository>((
  ref,
) {
  return impl.createOnlineSubtitleRepository(ref);
});

abstract class OnlineSubtitleRepository {
  Future<List<SubtitleSearchResult>> search(
    String query, {
    List<OnlineSubtitleSource> sources = const [OnlineSubtitleSource.assrt],
    int maxResults = 0,
  });

  Future<SubtitleDownloadResult> download(SubtitleSearchResult result);
}
