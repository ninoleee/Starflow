import 'package:starflow/features/library/domain/media_models.dart';

enum NasMetadataFetchStatus {
  never,
  succeeded,
  failed,
}

extension NasMetadataFetchStatusX on NasMetadataFetchStatus {
  bool get hasAttempted => this != NasMetadataFetchStatus.never;

  bool get isSuccessful => this == NasMetadataFetchStatus.succeeded;

  static NasMetadataFetchStatus fromJsonValue(Object? value) {
    final normalized = '$value'.trim().toLowerCase();
    switch (normalized) {
      case 'succeeded':
        return NasMetadataFetchStatus.succeeded;
      case 'failed':
        return NasMetadataFetchStatus.failed;
      case 'never':
      case '':
        return NasMetadataFetchStatus.never;
      default:
        return NasMetadataFetchStatus.never;
    }
  }
}

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
    required this.sidecarStatus,
    required this.wmdbStatus,
    required this.tmdbStatus,
    required this.imdbStatus,
    required this.item,
    this.manualMetadataLocked = false,
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
  final NasMetadataFetchStatus sidecarStatus;
  final NasMetadataFetchStatus wmdbStatus;
  final NasMetadataFetchStatus tmdbStatus;
  final NasMetadataFetchStatus imdbStatus;
  final MediaItem item;
  final bool manualMetadataLocked;

  bool get sidecarMatched => sidecarStatus.isSuccessful;

  bool get wmdbMatched => wmdbStatus.isSuccessful;

  bool get tmdbMatched => tmdbStatus.isSuccessful;

  bool get imdbMatched => imdbStatus.isSuccessful;

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
      'sidecarStatus': sidecarStatus.name,
      'wmdbStatus': wmdbStatus.name,
      'tmdbStatus': tmdbStatus.name,
      'imdbStatus': imdbStatus.name,
      'manualMetadataLocked': manualMetadataLocked,
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
      sidecarStatus: NasMetadataFetchStatusX.fromJsonValue(
        json['sidecarStatus'],
      ),
      wmdbStatus: NasMetadataFetchStatusX.fromJsonValue(json['wmdbStatus']),
      tmdbStatus: NasMetadataFetchStatusX.fromJsonValue(json['tmdbStatus']),
      imdbStatus: NasMetadataFetchStatusX.fromJsonValue(json['imdbStatus']),
      manualMetadataLocked: json['manualMetadataLocked'] as bool? ?? false,
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
    this.emptyAutoRebuildAttempted = false,
  });

  final String sourceId;
  final DateTime lastIndexedAt;
  final int recordCount;
  final String scopeKey;
  final bool emptyAutoRebuildAttempted;

  NasMediaIndexSourceState copyWith({
    String? sourceId,
    DateTime? lastIndexedAt,
    int? recordCount,
    String? scopeKey,
    bool? emptyAutoRebuildAttempted,
  }) {
    return NasMediaIndexSourceState(
      sourceId: sourceId ?? this.sourceId,
      lastIndexedAt: lastIndexedAt ?? this.lastIndexedAt,
      recordCount: recordCount ?? this.recordCount,
      scopeKey: scopeKey ?? this.scopeKey,
      emptyAutoRebuildAttempted:
          emptyAutoRebuildAttempted ?? this.emptyAutoRebuildAttempted,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sourceId': sourceId,
      'lastIndexedAt': lastIndexedAt.toIso8601String(),
      'recordCount': recordCount,
      'scopeKey': scopeKey,
      'emptyAutoRebuildAttempted': emptyAutoRebuildAttempted,
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
      emptyAutoRebuildAttempted:
          json['emptyAutoRebuildAttempted'] as bool? ?? false,
    );
  }
}
