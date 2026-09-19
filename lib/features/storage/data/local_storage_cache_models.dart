import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

enum DetailMetadataRefreshStatus {
  never,
  succeeded,
  failed,
}

class DetailTargetCacheSaveRequest {
  const DetailTargetCacheSaveRequest({
    required this.seedTarget,
    required this.resolvedTarget,
    this.metadataRefreshStatus,
    this.libraryMatchChoices,
    this.selectedLibraryMatchIndex,
    this.subtitleSearchChoices,
    this.selectedSubtitleSearchIndex,
  });

  final MediaDetailTarget seedTarget;
  final MediaDetailTarget resolvedTarget;
  final DetailMetadataRefreshStatus? metadataRefreshStatus;
  final List<MediaDetailTarget>? libraryMatchChoices;
  final int? selectedLibraryMatchIndex;
  final List<CachedSubtitleSearchOption>? subtitleSearchChoices;
  final int? selectedSubtitleSearchIndex;
}

extension DetailMetadataRefreshStatusX on DetailMetadataRefreshStatus {
  static DetailMetadataRefreshStatus fromJsonValue(Object? value) {
    final normalized = '$value'.trim().toLowerCase();
    switch (normalized) {
      case 'succeeded':
        return DetailMetadataRefreshStatus.succeeded;
      case 'failed':
        return DetailMetadataRefreshStatus.failed;
      case 'never':
      case '':
        return DetailMetadataRefreshStatus.never;
      default:
        return DetailMetadataRefreshStatus.never;
    }
  }
}

class CachedDetailState {
  const CachedDetailState({
    required this.target,
    this.libraryMatchChoices = const [],
    this.selectedLibraryMatchIndex = 0,
    this.subtitleSearchChoices = const [],
    this.selectedSubtitleSearchIndex = -1,
    this.metadataRefreshStatus = DetailMetadataRefreshStatus.never,
  });

  final MediaDetailTarget target;
  final List<MediaDetailTarget> libraryMatchChoices;
  final int selectedLibraryMatchIndex;
  final List<CachedSubtitleSearchOption> subtitleSearchChoices;
  final int selectedSubtitleSearchIndex;
  final DetailMetadataRefreshStatus metadataRefreshStatus;
}

class CachedEmbyLibrarySnapshot {
  const CachedEmbyLibrarySnapshot({
    this.refreshedAt,
    this.collections = const <MediaCollection>[],
    this.fallbackItems = const <MediaItem>[],
    this.itemsBySection = const <String, List<MediaItem>>{},
  });

  final DateTime? refreshedAt;
  final List<MediaCollection> collections;
  final List<MediaItem> fallbackItems;
  final Map<String, List<MediaItem>> itemsBySection;

  bool get hasData {
    if (fallbackItems.isNotEmpty) {
      return true;
    }
    return itemsBySection.values.any((items) => items.isNotEmpty);
  }
}
