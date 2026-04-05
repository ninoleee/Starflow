import 'package:starflow/features/library/domain/media_models.dart';

class NasMediaIndexRecord {
  const NasMediaIndexRecord({
    required this.id,
    required this.sourceId,
    required this.sectionId,
    required this.sectionName,
    required this.resourceId,
    required this.resourcePath,
    required this.fingerprint,
    required this.fileSizeBytes,
    required this.modifiedAt,
    required this.indexedAt,
    required this.scrapedAt,
    required this.recognizedTitle,
    required this.searchQuery,
    required this.originalFileName,
    required this.parentTitle,
    required this.recognizedYear,
    required this.recognizedItemType,
    required this.preferSeries,
    required this.sidecarMatched,
    required this.wmdbMatched,
    required this.tmdbMatched,
    required this.imdbMatched,
    required this.item,
    this.recognizedSeasonNumber,
    this.recognizedEpisodeNumber,
  });

  final String id;
  final String sourceId;
  final String sectionId;
  final String sectionName;
  final String resourceId;
  final String resourcePath;
  final String fingerprint;
  final int fileSizeBytes;
  final DateTime? modifiedAt;
  final DateTime indexedAt;
  final DateTime scrapedAt;
  final String recognizedTitle;
  final String searchQuery;
  final String originalFileName;
  final String parentTitle;
  final int recognizedYear;
  final String recognizedItemType;
  final bool preferSeries;
  final int? recognizedSeasonNumber;
  final int? recognizedEpisodeNumber;
  final bool sidecarMatched;
  final bool wmdbMatched;
  final bool tmdbMatched;
  final bool imdbMatched;
  final MediaItem item;

  static String buildRecordId({
    required String sourceId,
    required String resourceId,
  }) {
    return '$sourceId|$resourceId';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceId': sourceId,
      'sectionId': sectionId,
      'sectionName': sectionName,
      'resourceId': resourceId,
      'resourcePath': resourcePath,
      'fingerprint': fingerprint,
      'fileSizeBytes': fileSizeBytes,
      'modifiedAt': modifiedAt?.toIso8601String(),
      'indexedAt': indexedAt.toIso8601String(),
      'scrapedAt': scrapedAt.toIso8601String(),
      'recognizedTitle': recognizedTitle,
      'searchQuery': searchQuery,
      'originalFileName': originalFileName,
      'parentTitle': parentTitle,
      'recognizedYear': recognizedYear,
      'recognizedItemType': recognizedItemType,
      'preferSeries': preferSeries,
      'recognizedSeasonNumber': recognizedSeasonNumber,
      'recognizedEpisodeNumber': recognizedEpisodeNumber,
      'sidecarMatched': sidecarMatched,
      'wmdbMatched': wmdbMatched,
      'tmdbMatched': tmdbMatched,
      'imdbMatched': imdbMatched,
      'item': item.toJson(),
    };
  }

  factory NasMediaIndexRecord.fromJson(Map<String, dynamic> json) {
    return NasMediaIndexRecord(
      id: json['id'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
      sectionId: json['sectionId'] as String? ?? '',
      sectionName: json['sectionName'] as String? ?? '',
      resourceId: json['resourceId'] as String? ?? '',
      resourcePath: json['resourcePath'] as String? ?? '',
      fingerprint: json['fingerprint'] as String? ?? '',
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt() ?? 0,
      modifiedAt: DateTime.tryParse(json['modifiedAt'] as String? ?? ''),
      indexedAt: DateTime.tryParse(json['indexedAt'] as String? ?? '') ??
          DateTime.now(),
      scrapedAt: DateTime.tryParse(json['scrapedAt'] as String? ?? '') ??
          DateTime.now(),
      recognizedTitle: json['recognizedTitle'] as String? ?? '',
      searchQuery: json['searchQuery'] as String? ?? '',
      originalFileName: json['originalFileName'] as String? ?? '',
      parentTitle: json['parentTitle'] as String? ?? '',
      recognizedYear: (json['recognizedYear'] as num?)?.toInt() ?? 0,
      recognizedItemType: json['recognizedItemType'] as String? ?? '',
      preferSeries: json['preferSeries'] as bool? ?? false,
      recognizedSeasonNumber: (json['recognizedSeasonNumber'] as num?)?.toInt(),
      recognizedEpisodeNumber:
          (json['recognizedEpisodeNumber'] as num?)?.toInt(),
      sidecarMatched: json['sidecarMatched'] as bool? ?? false,
      wmdbMatched: json['wmdbMatched'] as bool? ?? false,
      tmdbMatched: json['tmdbMatched'] as bool? ?? false,
      imdbMatched: json['imdbMatched'] as bool? ?? false,
      item: MediaItem.fromJson(
        Map<String, dynamic>.from(json['item'] as Map? ?? const {}),
      ),
    );
  }
}

class NasMediaIndexSourceState {
  const NasMediaIndexSourceState({
    required this.sourceId,
    required this.lastIndexedAt,
    required this.recordCount,
    required this.scopeKey,
  });

  final String sourceId;
  final DateTime lastIndexedAt;
  final int recordCount;
  final String scopeKey;

  Map<String, dynamic> toJson() {
    return {
      'sourceId': sourceId,
      'lastIndexedAt': lastIndexedAt.toIso8601String(),
      'recordCount': recordCount,
      'scopeKey': scopeKey,
    };
  }

  factory NasMediaIndexSourceState.fromJson(Map<String, dynamic> json) {
    return NasMediaIndexSourceState(
      sourceId: json['sourceId'] as String? ?? '',
      lastIndexedAt:
          DateTime.tryParse(json['lastIndexedAt'] as String? ?? '') ??
              DateTime.now(),
      recordCount: (json['recordCount'] as num?)?.toInt() ?? 0,
      scopeKey: json['scopeKey'] as String? ?? '',
    );
  }
}
