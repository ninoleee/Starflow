import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/playback/data/online_subtitle_repository.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

OnlineSubtitleRepository createOnlineSubtitleRepository(Ref ref) {
  return const UnsupportedOnlineSubtitleRepository();
}

class UnsupportedOnlineSubtitleRepository implements OnlineSubtitleRepository {
  const UnsupportedOnlineSubtitleRepository();

  @override
  Future<List<SubtitleSearchResult>> search(String query) {
    throw UnsupportedError('当前平台暂不支持应用内在线字幕搜索。');
  }

  @override
  Future<SubtitleDownloadResult> download(SubtitleSearchResult result) {
    throw UnsupportedError('当前平台暂不支持应用内在线字幕下载。');
  }
}
