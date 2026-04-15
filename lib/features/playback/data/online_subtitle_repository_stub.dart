import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/playback/data/online_subtitle_repository.dart';
import 'package:starflow/features/playback/domain/online_subtitle_structured_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

OnlineSubtitleRepository createOnlineSubtitleRepository(Ref ref) {
  return const UnsupportedOnlineSubtitleRepository();
}

class UnsupportedOnlineSubtitleRepository implements OnlineSubtitleRepository {
  const UnsupportedOnlineSubtitleRepository();

  @override
  Future<List<SubtitleSearchResult>> search(
    String query, {
    List<OnlineSubtitleSource> sources = const [OnlineSubtitleSource.assrt],
    int maxResults = 0,
  }) {
    throw UnsupportedError('当前平台暂不支持应用内在线字幕搜索。');
  }

  @override
  Future<List<ValidatedSubtitleCandidate>> searchStructured(
    OnlineSubtitleSearchRequest request, {
    List<OnlineSubtitleSource> sources = const [
      OnlineSubtitleSource.assrt,
      OnlineSubtitleSource.opensubtitles,
      OnlineSubtitleSource.subdl,
    ],
    int maxResults = 0,
    int maxValidated = 0,
  }) {
    throw UnsupportedError('当前平台暂不支持结构化在线字幕搜索。');
  }

  @override
  Future<SubtitleDownloadResult> download(SubtitleSearchResult result) {
    throw UnsupportedError('当前平台暂不支持应用内在线字幕下载。');
  }
}
